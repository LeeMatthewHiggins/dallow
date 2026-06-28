// dallow targets analyzer's unified element model (analyzer >= 14): the legacy
// `Element`/`Element2` split has collapsed back into a single `Element` model
// with a parallel `Fragment` tree. Source locations and `isSynthetic` now live
// on fragments; declaration nodes expose `declaredFragment` rather than
// `declaredElement`.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
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

/// A declared symbol in the analysed package — either a top-level declaration
/// or, when [isMember] is true, a class/mixin/enum/extension member.
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
    this.isMember = false,
    this.owner,
    this.enclosingName,
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
  /// exported API surface. Always false for members (a member's API status is
  /// derived from its [owner]).
  final bool isPublicApi;

  /// True when this node is a class member (method, getter, setter or field)
  /// rather than a top-level declaration.
  final bool isMember;

  /// The top-level node enclosing this member, or null for a top-level node.
  final CodeNode? owner;

  /// The simple name of the enclosing type, for member findings (e.g. `Foo`
  /// in `Foo.bar`).
  final String? enclosingName;

  final Set<CodeNode> references = {};
}

/// A function-like body whose cyclomatic complexity can be measured without
/// re-parsing source files outside [CodeGraph.build].
class FunctionComplexity {
  const FunctionComplexity({
    required this.symbol,
    required this.relativePath,
    required this.line,
    required this.complexity,
  });

  final String symbol;
  final String relativePath;
  final int line;
  final int complexity;
}

/// The resolved symbol graph for a single package, plus the file-level import
/// graph used for circular-dependency detection.
class CodeGraph {
  CodeGraph._(this.rootPath);

  final String rootPath;

  final Map<Element, CodeNode> _nodes = {};

  /// Class/mixin/enum/extension members, keyed by their declaring element.
  final Map<Element, CodeNode> _memberNodes = {};

  /// File-level import edges, keyed by absolute path, restricted to files
  /// inside the analysed package.
  final Map<String, Set<String>> imports = {};

  final Set<CodeNode> _exportedApi = {};
  final List<FunctionComplexity> _functions = [];

  Iterable<CodeNode> get nodes => _nodes.values;

  /// All registered class members (methods, getters, setters, fields).
  Iterable<CodeNode> get memberNodes => _memberNodes.values;

  /// Function, method, constructor, and closure complexity measurements.
  Iterable<FunctionComplexity> get functions => _functions;

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
        .._registerExportedApi(unit)
        .._registerComplexity(unit);
    }

    return graph;
  }

  /// Records the public export surface of each public (`lib/`, non-`src`)
  /// library. Walking the resolved export namespace captures re-exports and
  /// `show`/`hide` combinators without re-implementing combinator logic.
  void _registerExportedApi(ResolvedUnitResult result) {
    final library = result.libraryElement;
    if (library.firstFragment.source.fullName != result.path) return;

    final relativePath = p.relative(result.path, from: rootPath);
    final isUnderLib = _isUnder(relativePath, 'lib');
    final isUnderLibSrc = _isUnder(relativePath, p.join('lib', 'src'));
    if (!isUnderLib || isUnderLibSrc) return;

    for (final element in library.exportNamespace.definedNames2.values) {
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
      final fragment = element.firstFragment;
      final name = element.name;
      if (name == null || name.isEmpty) continue;
      if (_isSyntheticProperty(element)) continue;
      if (result.path != fragment.libraryFragment?.source.fullName) continue;

      final isPrivate = name.startsWith('_');
      final node = CodeNode(
        element: element,
        name: name,
        absolutePath: result.path,
        relativePath: relativePath,
        line: _lineOf(result, fragment.nameOffset),
        isPrivate: isPrivate,
        isUnderLibSrc: isUnderLibSrc,
        isConsumerFile: isConsumerFile,
        isPublicApi: isUnderLib && !isUnderLibSrc && !isPrivate,
      );
      _nodes[element] = node;

      // Register the members of types so dead-code analysis can reach below the
      // top-level granularity (unused methods/fields). Functions, typedefs and
      // variables have no members.
      if (element is InstanceElement) {
        _registerMembers(
          node,
          element,
          result,
          relativePath: relativePath,
          isUnderLibSrc: isUnderLibSrc,
          isConsumerFile: isConsumerFile,
        );
      }
    }
  }

  /// Registers the declared members (methods, explicit getters/setters and
  /// fields) of [type] as member nodes owned by [owner]. Synthetic members,
  /// constructors and enum constants are skipped: they are either implicit or
  /// reached through their type rather than as standalone dead candidates.
  void _registerMembers(
    CodeNode owner,
    InstanceElement type,
    ResolvedUnitResult result, {
    required String relativePath,
    required bool isUnderLibSrc,
    required bool isConsumerFile,
  }) {
    // The representation field of an `extension type` is implicit to the type
    // and always "used"; never report it as a standalone dead field.
    final representation =
        type is ExtensionTypeElement ? type.representation : null;
    final members = <Element>[
      ...type.methods,
      ...type.fields.where(
        (f) =>
            !_isSyntheticProperty(f) &&
            !f.isEnumConstant &&
            f != representation,
      ),
      ...type.getters.where((a) => !_isSyntheticProperty(a)),
      ...type.setters.where((a) => !_isSyntheticProperty(a)),
    ];

    for (final element in members) {
      final fragment = element.firstFragment;
      final name = element.name;
      if (name == null || name.isEmpty) continue;
      if (_isSyntheticProperty(element)) continue;
      if (result.path != fragment.libraryFragment?.source.fullName) continue;

      _memberNodes[element] = CodeNode(
        element: element,
        name: name,
        absolutePath: result.path,
        relativePath: relativePath,
        line: _lineOf(result, fragment.nameOffset),
        isPrivate: name.startsWith('_'),
        isUnderLibSrc: isUnderLibSrc,
        isConsumerFile: isConsumerFile,
        isPublicApi: false,
        isMember: true,
        owner: owner,
        enclosingName: type.name,
      );
    }
  }

  void _registerReferences(ResolvedUnitResult result) {
    result.unit.accept(_ReferenceVisitor(this));
  }

  void _registerComplexity(ResolvedUnitResult result) {
    result.unit.accept(_ComplexityCollector(this, result));
  }

  void _registerImports(ResolvedUnitResult result) {
    final from = result.path;
    final library = result.libraryElement;
    final edges = imports.putIfAbsent(from, () => {});
    final targets = <LibraryElement>[
      ...library.fragments.expand((fragment) => fragment.importedLibraries),
      ...library.exportedLibraries,
    ];
    for (final target in targets) {
      final resolved = target.firstFragment.source.fullName;
      if (resolved != from && p.isWithin(rootPath, resolved)) {
        edges.add(resolved);
      }
    }
  }

  /// Maps a referenced [element] to its member node, or null when it is not a
  /// registered member. A synthetic property accessor (the implicit getter or
  /// setter of a field) is unwrapped to its backing field, so reading or
  /// writing a field resolves to the field's node.
  CodeNode? memberNodeOf(Element? element) {
    var current = element;
    if (current is PropertyAccessorElement && _isSyntheticProperty(current)) {
      current = current.variable;
    }
    if (current == null) return null;
    return _memberNodes[current];
  }

  /// Maps an arbitrary referenced [element] back to the top-level [CodeNode]
  /// that owns it, or null when it lives outside this package.
  CodeNode? ownerOf(Element? element) {
    var current = element;
    while (current != null) {
      if (current is PropertyAccessorElement && _isSyntheticProperty(current)) {
        current = current.variable;
        continue;
      }
      final node = _nodes[current];
      if (node != null) return node;
      final enclosing = current.enclosingElement;
      if (enclosing is LibraryElement || enclosing == null) break;
      current = enclosing;
    }
    return null;
  }

  /// Whether [element] is an implicitly-induced property: the synthetic getter
  /// or setter of a variable, or the synthetic backing variable of an explicit
  /// getter/setter. The unified model has no blanket `isSynthetic` flag, so the
  /// induced-vs-declared distinction is read from `isOriginDeclaration`.
  static bool _isSyntheticProperty(Element element) {
    if (element is PropertyAccessorElement) return !element.isOriginDeclaration;
    if (element is PropertyInducingElement) return !element.isOriginDeclaration;
    return false;
  }

  Iterable<Element> _topLevelElements(LibraryElement library) sync* {
    // The unified element model exposes top-level declarations directly on the
    // library, merged across its fragments. Synthetic accessors that back a
    // top-level variable are filtered out at registration via
    // `_isSyntheticProperty`, so getters and setters can be yielded wholesale
    // here.
    yield* library.topLevelFunctions;
    yield* library.classes;
    yield* library.enums;
    yield* library.mixins;
    yield* library.extensions;
    yield* library.extensionTypes;
    yield* library.typeAliases;
    yield* library.topLevelVariables;
    yield* library.getters;
    yield* library.setters;
  }

  int _lineOf(ResolvedUnitResult result, int? offset) {
    if (offset == null || offset < 0) return 0;
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
    // Prefer the most specific (member) node so references made inside a member
    // body are attributed to that member, not just its enclosing type.
    final node = _graph.memberNodeOf(owner) ?? _graph.ownerOf(owner);
    final previous = _current;
    if (node != null) _current = node;
    body();
    _current = previous;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _withOwner(
      node.declaredFragment?.element,
      () => super.visitFunctionDeclaration(node),
    );
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _withOwner(node.declaredFragment?.element,
        () => super.visitClassDeclaration(node));
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _withOwner(
        node.declaredFragment?.element, () => super.visitEnumDeclaration(node));
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _withOwner(node.declaredFragment?.element,
        () => super.visitMixinDeclaration(node));
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _withOwner(
      node.declaredFragment?.element,
      () => super.visitExtensionDeclaration(node),
    );
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _withOwner(node.declaredFragment?.element,
        () => super.visitGenericTypeAlias(node));
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    _withOwner(node.declaredFragment?.element,
        () => super.visitFunctionTypeAlias(node));
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Covers methods, operators and explicit getters/setters.
    _withOwner(node.declaredFragment?.element,
        () => super.visitMethodDeclaration(node));
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final variables = node.fields.variables;
    final first =
        variables.isEmpty ? null : variables.first.declaredFragment?.element;
    _withOwner(first, () => node.fields.type?.accept(this));
    for (final variable in variables) {
      _withOwner(
          variable.declaredFragment?.element, () => variable.accept(this));
    }
  }

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    // `MyClass(this.x)` initialises field `x`; treat it as a use so a field
    // only ever set through a constructor is not reported as dead.
    final element = node.declaredFragment?.element;
    if (element is FieldFormalParameterElement) _record(element.field);
    super.visitFieldFormalParameter(node);
  }

  @override
  void visitSuperFormalParameter(SuperFormalParameter node) {
    // `MyClass(super.x)` forwards to a superclass field formal; keep that
    // field alive too.
    final element = node.declaredFragment?.element;
    if (element is SuperFormalParameterElement) {
      final forwarded = element.superConstructorParameter;
      if (forwarded is FieldFormalParameterElement) _record(forwarded.field);
    }
    super.visitSuperFormalParameter(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    final variables = node.variables.variables;
    final first =
        variables.isEmpty ? null : variables.first.declaredFragment?.element;
    _withOwner(first, () => node.variables.type?.accept(this));
    for (final variable in variables) {
      _withOwner(
          variable.declaredFragment?.element, () => variable.accept(this));
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _record(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _record(node.element);
    super.visitNamedType(node);
  }

  void _record(Element? referenced) {
    if (referenced == null) return;
    final from = _current;
    if (from == null) return;

    final memberTarget = _graph.memberNodeOf(referenced);
    final topLevelTarget = _graph.ownerOf(referenced);

    // The enclosing scope reaches both the referenced member (if the reference
    // resolves to one) and its top-level owner, so member-level and top-level
    // reachability stay independently correct.
    _addEdge(from, memberTarget);
    _addEdge(from, topLevelTarget);

    // Preserve the pre-member-analysis invariant: a reference made inside a
    // member body also counts as a *top-level* use by the enclosing type —
    // exactly as it did when the type was the only recorded scope. This keeps
    // top-level reachability a true superset of the old behaviour (byte-for-
    // byte), independent of whether the member itself is reachable, so a
    // member-level false positive can never demote a top-level symbol. Only the
    // top-level owner edge is replayed (not the member edge): leaking the
    // member target through the owner would mask genuinely-dead members
    // referenced only from other dead members.
    if (from.isMember) _addEdge(from.owner, topLevelTarget);
  }

  void _addEdge(CodeNode? from, CodeNode? target) {
    if (from == null || target == null || identical(from, target)) return;
    from.references.add(target);
  }
}

class _ComplexityCollector extends RecursiveAstVisitor<void> {
  _ComplexityCollector(this._graph, this._result);

  final CodeGraph _graph;
  final ResolvedUnitResult _result;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _record(node.name.lexeme, node.functionExpression.body);
    node.functionExpression.body.accept(this);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final owner = _enclosingTypeName(node);
    final name =
        owner == null ? node.name.lexeme : '$owner.${node.name.lexeme}';
    _record(name, node.body);
    node.body.accept(this);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final owner = _enclosingTypeName(node) ?? '<constructor>';
    final suffix = node.name == null ? '' : '.${node.name!.lexeme}';
    _record('$owner$suffix', node.body);
    node.body.accept(this);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is FunctionDeclaration) return;
    final line = _result.lineInfo.getLocation(node.offset).lineNumber;
    _record('${_enclosingCallableName(node) ?? '<closure>'}.<closure>:$line',
        node.body);
    node.body.accept(this);
  }

  void _record(String symbol, FunctionBody body) {
    _graph._functions.add(
      FunctionComplexity(
        symbol: symbol,
        relativePath: p.relative(_result.path, from: _graph.rootPath),
        line: _result.lineInfo.getLocation(body.parent!.offset).lineNumber,
        complexity: _ComplexityCounter.count(body),
      ),
    );
  }

  String? _enclosingTypeName(AstNode node) {
    var current = node.parent;
    while (current != null) {
      // `ClassDeclaration`/`EnumDeclaration` moved their name token onto a
      // `namePart` in the unified AST; mixins and extensions keep `name`.
      if (current is ClassDeclaration) return current.namePart.typeName.lexeme;
      if (current is MixinDeclaration) return current.name.lexeme;
      if (current is EnumDeclaration) return current.namePart.typeName.lexeme;
      if (current is ExtensionDeclaration) {
        return current.name?.lexeme ?? '<extension>';
      }
      current = current.parent;
    }
    return null;
  }

  String? _enclosingCallableName(AstNode node) {
    var current = node.parent;
    while (current != null) {
      if (current is FunctionDeclaration) return current.name.lexeme;
      if (current is MethodDeclaration) {
        final owner = _enclosingTypeName(current);
        return owner == null
            ? current.name.lexeme
            : '$owner.${current.name.lexeme}';
      }
      if (current is ConstructorDeclaration) {
        final owner = _enclosingTypeName(current);
        if (owner == null) return null;
        final suffix = current.name == null ? '' : '.${current.name!.lexeme}';
        return '$owner$suffix';
      }
      if (current is VariableDeclaration) return current.name.lexeme;
      current = current.parent;
    }
    return null;
  }
}

class _ComplexityCounter extends RecursiveAstVisitor<void> {
  _ComplexityCounter();

  int complexity = 1;

  static int count(FunctionBody body) {
    final counter = _ComplexityCounter();
    body.accept(counter);
    return counter.complexity;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitIfStatement(IfStatement node) {
    complexity++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    complexity++;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    complexity++;
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    complexity++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    complexity++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    complexity++;
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    complexity++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    complexity++;
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    complexity++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    complexity++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final type = node.operator.type;
    if (type == TokenType.AMPERSAND_AMPERSAND ||
        type == TokenType.BAR_BAR ||
        type == TokenType.QUESTION_QUESTION) {
      complexity++;
    }
    super.visitBinaryExpression(node);
  }
}
