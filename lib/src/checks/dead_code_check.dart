import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';

/// Flags top-level symbols that are unreachable from any entrypoint.
///
/// Roots (treated as reachable) are: every symbol declared in a consumer file
/// (bin, test, example, …) and every public symbol on the package's `lib/`
/// API surface. A symbol is reported when it is unreachable from those roots
/// and is either private or lives under `lib/src/`, i.e. it can never be a
/// legitimately-unused export.
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
    final seeds =
        graph.nodes.where((n) => n.isConsumerFile || n.isPublicApi).toList();

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
    final element = node.element.runtimeType.toString();
    if (element.contains('Class')) return 'class';
    if (element.contains('Enum')) return 'enum';
    if (element.contains('Mixin')) return 'mixin';
    if (element.contains('Extension')) return 'extension';
    if (element.contains('TypeAlias')) return 'typedef';
    if (element.contains('PropertyAccessor') ||
        element.contains('TopLevelVariable')) {
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
