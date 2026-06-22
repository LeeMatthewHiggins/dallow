import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';
import 'package:path/path.dart' as p;

/// Detects import cycles between files in the analysed package.
///
/// Cycles are the strongly-connected components of the file-level import graph
/// with more than one member, plus any single file that imports itself.
class CircularImportCheck {
  const CircularImportCheck();

  List<Finding> run(CodeGraph graph) {
    final components = _stronglyConnected(graph.imports);

    final findings = <Finding>[];
    for (final component in components) {
      final first = component.first;
      final selfCycle = component.length == 1 &&
          (graph.imports[first]?.contains(first) ?? false);
      if (component.length < 2 && !selfCycle) continue;

      final cycle = component
          .map((f) => p.relative(f, from: graph.rootPath))
          .toList()
        ..sort();
      findings.add(
        Finding(
          kind: CheckKind.circularImport,
          severity: Severity.warning,
          message: 'Import cycle between ${cycle.length} files: '
              '${cycle.join(' → ')}.',
          file: cycle.first,
        ),
      );
    }

    findings.sort((a, b) => (a.file ?? '').compareTo(b.file ?? ''));
    return findings;
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
