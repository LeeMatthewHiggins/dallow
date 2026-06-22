import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';
import 'package:path/path.dart' as p;

/// The number of member files named inline before a cycle's message is
/// truncated with an "(+N more)" suffix, to keep barrel-induced mega-cycles
/// from flooding the report.
const _maxListedMembers = 8;

/// Detects dependency cycles between files in the analysed package.
///
/// The graph folds both `import` and `export` edges, so a cycle is any
/// strongly-connected component of that graph with more than one member.
/// Members are listed in sorted order for determinism; this is the cycle's
/// membership, not a traversal path.
class CircularImportCheck {
  const CircularImportCheck();

  /// Cycles whose membership exceeds [maxCycleSize] are skipped. A large
  /// strongly-connected component is almost always a single barrel re-exported
  /// across the package rather than a fixable local cycle; this lets a project
  /// gate on small new cycles without drowning in the known mega-cycle. Null
  /// (the default) reports every cycle.
  List<Finding> run(CodeGraph graph, {int? maxCycleSize}) {
    final components = _stronglyConnected(graph.imports);

    final findings = <Finding>[];
    for (final component in components) {
      if (component.length < 2) continue;
      if (maxCycleSize != null && component.length > maxCycleSize) continue;

      final cycle = component
          .map((f) => p.relative(f, from: graph.rootPath))
          .toList()
        ..sort();
      findings.add(
        Finding(
          kind: CheckKind.circularImport,
          severity: Severity.warning,
          message: 'Dependency cycle among ${cycle.length} files: '
              '${_summarise(cycle)}.',
          file: cycle.first,
        ),
      );
    }

    findings.sort((a, b) => (a.file ?? '').compareTo(b.file ?? ''));
    return findings;
  }

  String _summarise(List<String> cycle) {
    if (cycle.length <= _maxListedMembers) return cycle.join(', ');
    final shown = cycle.take(_maxListedMembers).join(', ');
    return '$shown (+${cycle.length - _maxListedMembers} more)';
  }

  /// Tarjan's strongly-connected-components algorithm.
  List<List<String>> _stronglyConnected(Map<String, Set<String>> graph) {
    final index = <String, int>{};
    final lowLink = <String, int>{};
    final onStack = <String>{};
    final stack = <String>[];
    final result = <List<String>>[];
    var counter = 0;

    void strongConnect(String node) {
      index[node] = counter;
      lowLink[node] = counter;
      counter++;
      stack.add(node);
      onStack.add(node);

      for (final next in graph[node] ?? const <String>{}) {
        if (!index.containsKey(next)) {
          strongConnect(next);
          lowLink[node] =
              lowLink[node]! < lowLink[next]! ? lowLink[node]! : lowLink[next]!;
        } else if (onStack.contains(next)) {
          lowLink[node] =
              lowLink[node]! < index[next]! ? lowLink[node]! : index[next]!;
        }
      }

      if (lowLink[node] == index[node]) {
        final component = <String>[];
        String member;
        do {
          member = stack.removeLast();
          onStack.remove(member);
          component.add(member);
        } while (member != node);
        result.add(component);
      }
    }

    for (final node in graph.keys) {
      if (!index.containsKey(node)) strongConnect(node);
    }
    return result;
  }
}
