// dallow targets the stable legacy Element model (see code_graph.dart); the
// Element2 migration is deferred package-wide, so the element subtype checks
// below intentionally use the legacy classes.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/element/element.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';

/// Flags top-level symbols that are unreachable from any entrypoint.
///
/// Roots (treated as reachable) are: every symbol declared in a consumer file
/// (bin, test, example, …), every public symbol declared directly under
/// `lib/`, and every symbol surfaced through a public library's export
/// namespace (re-exports from `lib/src/`). A symbol is reported when it is
/// unreachable from those roots and is either private or lives under
/// `lib/src/`, i.e. it can never be a legitimately-unused export.
class DeadCodeCheck {
  const DeadCodeCheck();

  List<Finding> run(CodeGraph graph) {
    final reachable = _reachableFrom(graph);

    final findings = <Finding>[];
    for (final node in graph.nodes) {
      if (reachable.contains(node)) continue;
      final isReportable = node.isPrivate || node.isUnderLibSrc;
      if (!isReportable) continue;

      findings.add(
        Finding(
          kind: CheckKind.deadCode,
          severity: Severity.warning,
          message: "Unused ${_describe(node)} '${node.name}' is never "
              'referenced from any entrypoint.',
          file: node.relativePath,
          line: node.line,
          symbol: node.name,
        ),
      );
    }

    findings.sort(_byLocation);
    return findings;
  }

  Set<CodeNode> _reachableFrom(CodeGraph graph) {
    final seeds = [
      ...graph.nodes.where((n) => n.isConsumerFile || n.isPublicApi),
      ...graph.exportedApi,
    ];

    final reachable = <CodeNode>{};
    final queue = <CodeNode>[...seeds];
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      if (!reachable.add(node)) continue;
      queue.addAll(node.references);
    }
    return reachable;
  }

  String _describe(CodeNode node) {
    final element = node.element;
    if (element is TypeAliasElement) return 'typedef';
    if (element is EnumElement) return 'enum';
    if (element is MixinElement) return 'mixin';
    if (element is ExtensionTypeElement) return 'extension type';
    if (element is ExtensionElement) return 'extension';
    if (element is ClassElement) return 'class';
    if (element is PropertyAccessorElement ||
        element is TopLevelVariableElement) {
      return 'variable';
    }
    return 'function';
  }

  int _byLocation(Finding a, Finding b) {
    final byFile = (a.file ?? '').compareTo(b.file ?? '');
    if (byFile != 0) return byFile;
    return (a.line ?? 0).compareTo(b.line ?? 0);
  }
}
