// The analyzer is mid-migration to the Element2 API. dallow targets the
// stable legacy Element model, which still resolves cleanly across the
// supported SDK range. Revisit when Element2 stabilises.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

/// Thrown when no Dart SDK can be located to back the analyzer. dallow
/// resolves the package against a real SDK, so one must be discoverable.
class SdkNotFoundException implements Exception {
  const SdkNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Locates a Dart SDK root, or null if none can be found. Resolution order:
/// the `DART_SDK` environment variable, the running VM's own SDK (when dallow
/// is invoked via `dart`), then the first `dart` on `PATH` — covering both a
/// stand-alone SDK and a Flutter-bundled one. This lets a compiled binary,
/// which has no SDK of its own, resolve against whatever Dart is installed.
String? resolveSdkPath() {
  bool isSdkRoot(String dir) =>
      File(p.join(dir, 'version')).existsSync() &&
      Directory(p.join(dir, 'lib', '_internal')).existsSync();

  final env = Platform.environment['DART_SDK'];
  if (env != null && env.isNotEmpty && isSdkRoot(env)) return env;

  final vmSdk = p.dirname(p.dirname(Platform.resolvedExecutable));
  if (isSdkRoot(vmSdk)) return vmSdk;

  final dartOnPath = _which('dart');
  if (dartOnPath != null) {
    final binDir = p.dirname(_realpath(dartOnPath));
    final candidates = [
      p.dirname(binDir), // stand-alone SDK: <sdk>/bin/dart
      p.join(binDir, 'cache', 'dart-sdk'), // Flutter: <flutter>/bin/cache/...
    ];
    for (final candidate in candidates) {
      if (isSdkRoot(candidate)) return candidate;
    }
  }
  return null;
}

String? _which(String executable) {
  final command = Platform.isWindows ? 'where' : 'which';
  try {
    final result = Process.runSync(command, [executable]);
    if (result.exitCode != 0) return null;
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return null;
    return output.split(RegExp(r'[\r\n]')).first.trim();
  } on ProcessException {
    return null;
  }
}

String _realpath(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}

/// A declared top-level symbol in the analysed package.
class CodeNode {
  CodeNode({
    required this.element,
    required this.name,
    required this.absolutePath,
    required this.relativePath,
    required this.line,
    required this.isPrivate,
    required this.isUnderLibSrc,
    required this.isConsumerFile,
    required this.isPublicApi,
  });

  final Element element;
  final String name;
  final String absolutePath;
  final String relativePath;
  final int line;
  final bool isPrivate;

  /// Declared under `lib/src/`, i.e. package-internal by convention.
  final bool isUnderLibSrc;

  /// Declared outside `lib/` (bin, test, example, tool, web, …) — a place
  /// that consumes the library rather than defining its public surface.
  final bool isConsumerFile;

  /// A public symbol declared directly under `lib/`, forming the package's
  /// exported API surface.
  final bool isPublicApi;

  final Set<CodeNode> references = {};
}

/// The resolved symbol graph for a single package, plus the file-level import
/// graph used for circular-dependency detection.
class CodeGraph {
  CodeGraph._(this.rootPath);

  final String rootPath;

  final Map<Element, CodeNode> _nodes = {};

  /// File-level import edges, keyed by absolute path, restricted to files
  /// inside the analysed package.
  final Map<String, Set<String>> imports = {};

  final Set<CodeNode> _exportedApi = {};

  Iterable<CodeNode> get nodes => _nodes.values;

  /// Nodes that form the package's public API surface, including symbols
  /// surfaced from `lib/src/` through a re-`export` from a public library.
  /// These are reachability roots: exporting a symbol is using it.
  Set<CodeNode> get exportedApi => _exportedApi;

  /// Resolves every `.dart` file reachable from [rootPath] and builds the
  /// symbol and import graphs.
  ///
  /// [sdkPath] overrides Dart SDK discovery; when omitted the SDK is located
  /// via [resolveSdkPath]. Throws [SdkNotFoundException] when none is found.
  static Future<CodeGraph> build(String rootPath, {String? sdkPath}) async {
    final sdk = sdkPath ?? resolveSdkPath();
    if (sdk == null) {
      throw const SdkNotFoundException(
        'Could not locate a Dart SDK. Install Dart and ensure `dart` is on '
        'PATH, or set the DART_SDK environment variable to the SDK root.',
      );
    }

    final graph = CodeGraph._(rootPath);
    final collection = AnalysisContextCollection(
      includedPaths: [rootPath],
      sdkPath: sdk,
    );

    final paths = <String>[];
    for (final context in collection.contexts) {
      paths.addAll(context.contextRoot.analyzedFiles());
    }
    final dartFiles = paths.where((f) => f.endsWith('.dart')).toSet().toList()
      ..sort();

    final resolvedUnits = <ResolvedUnitResult>[];
    for (final path in dartFiles) {
      final context = collection.contextFor(path);
      final result = await context.currentSession.getResolvedUnit(path);
      if (result is ResolvedUnitResult) {
        resolvedUnits.add(result);
        graph._registerDeclarations(result);
      }
    }

    for (final unit in resolvedUnits) {
      graph
        .._registerReferences(unit)
        .._registerImports(unit)
        .._registerExportedApi(unit);
    }

    return graph;
  }

  /// Records the public export surface of each public (`lib/`, non-`src`)
  /// library. Walking the resolved export namespace captures re-exports and
  /// `show`/`hide` combinators without re-implementing combinator logic.
  void _registerExportedApi(ResolvedUnitResult result) {
    final library = result.libraryElement;
    if (library.source.fullName != result.path) return;

    final relativePath = p.relative(result.path, from: rootPath);
    final isUnderLib = _isUnder(relativePath, 'lib');
    final isUnderLibSrc = _isUnder(relativePath, p.join('lib', 'src'));
    if (!isUnderLib || isUnderLibSrc) return;

    for (final element in library.exportNamespace.definedNames.values) {
      final node = ownerOf(element);
      if (node != null) _exportedApi.add(node);
    }
  }

  void _registerDeclarations(ResolvedUnitResult result) {
    final relativePath = p.relative(result.path, from: rootPath);
    final isUnderLib = _isUnder(relativePath, 'lib');
    final isUnderLibSrc = _isUnder(relativePath, p.join('lib', 'src'));
    final isConsumerFile = !isUnderLib;

    for (final element in _topLevelElements(result.libraryElement)) {
      final name = element.name;
      if (name == null || name.isEmpty) continue;
      if (element.isSynthetic) continue;
      if (result.path != element.source?.fullName) continue;

      final isPrivate = name.startsWith('_');
      _nodes[element] = CodeNode(
        element: element,
        name: name,
        absolutePath: result.path,
        relativePath: relativePath,
        line: _lineOf(result, element.nameOffset),
        isPrivate: isPrivate,
        isUnderLibSrc: isUnderLibSrc,
        isConsumerFile: isConsumerFile,
        isPublicApi: isUnderLib && !isUnderLibSrc && !isPrivate,
      );
    }
  }

  void _registerReferences(ResolvedUnitResult result) {
    result.unit.accept(_ReferenceVisitor(this));
  }

  void _registerImports(ResolvedUnitResult result) {
    final from = result.path;
    final library = result.libraryElement;
    final edges = imports.putIfAbsent(from, () => {});
    final targets = <LibraryElement>[
      ...library.importedLibraries,
      ...library.exportedLibraries,
    ];
    for (final target in targets) {
      final resolved = target.source.fullName;
      if (resolved != from && p.isWithin(rootPath, resolved)) {
        edges.add(resolved);
      }
    }
  }

  /// Maps an arbitrary referenced [element] back to the top-level [CodeNode]
  /// that owns it, or null when it lives outside this package.
  CodeNode? ownerOf(Element? element) {
    var current = element;
    while (current != null) {
      if (current is PropertyAccessorElement && current.isSynthetic) {
        final variable = current.variable2;
        if (variable == null) break;
        current = variable;
        continue;
      }
      final node = _nodes[current];
      if (node != null) return node;
      final enclosing = current.enclosingElement3;
      if (enclosing is CompilationUnitElement || enclosing == null) break;
      current = enclosing;
    }
    return null;
  }

  Iterable<Element> _topLevelElements(LibraryElement library) sync* {
    for (final unit in library.units) {
      yield* unit.functions;
      yield* unit.classes;
      yield* unit.enums;
      yield* unit.mixins;
      yield* unit.extensions;
      yield* unit.typeAliases;
      yield* unit.topLevelVariables;
      for (final accessor in unit.accessors) {
        if (!accessor.isSynthetic) yield accessor;
      }
    }
  }

  int _lineOf(ResolvedUnitResult result, int offset) {
    if (offset < 0) return 0;
    return result.lineInfo.getLocation(offset).lineNumber;
  }

  static bool _isUnder(String relativePath, String dir) {
    final normalized = p.normalize(relativePath);
    return normalized == dir || p.isWithin(dir, normalized);
  }
}

class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  _ReferenceVisitor(this._graph);

  final CodeGraph _graph;
  CodeNode? _current;

  void _withOwner(Element? owner, void Function() body) {
    final node = _graph.ownerOf(owner);
    final previous = _current;
    if (node != null) _current = node;
    body();
    _current = previous;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _withOwner(
      node.declaredElement,
      () => super.visitFunctionDeclaration(node),
    );
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _withOwner(node.declaredElement, () => super.visitClassDeclaration(node));
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _withOwner(node.declaredElement, () => super.visitEnumDeclaration(node));
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _withOwner(node.declaredElement, () => super.visitMixinDeclaration(node));
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _withOwner(
      node.declaredElement,
      () => super.visitExtensionDeclaration(node),
    );
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _withOwner(node.declaredElement, () => super.visitGenericTypeAlias(node));
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    _withOwner(node.declaredElement, () => super.visitFunctionTypeAlias(node));
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    final variables = node.variables.variables;
    final first = variables.isEmpty ? null : variables.first.declaredElement;
    _withOwner(first, () => node.variables.type?.accept(this));
    for (final variable in variables) {
      _withOwner(variable.declaredElement, () => variable.accept(this));
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _record(node.staticElement);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _record(node.element);
    super.visitNamedType(node);
  }

  void _record(Element? referenced) {
    if (referenced == null) return;
    final target = _graph.ownerOf(referenced);
    if (target == null) return;
    final from = _current;
    if (from == null || identical(from, target)) return;
    from.references.add(target);
  }
}
