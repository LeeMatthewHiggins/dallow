// dallow targets analyzer's unified element model (analyzer >= 14); the element
// subtype checks below use the current `GetterElement`/`SetterElement` split and
// read inheritance annotations through `Element.metadata`.

import 'package:analyzer/dart/element/element.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';

/// Flags symbols — both top-level declarations and class members — that are
/// unreachable from any entrypoint.
///
/// **Top-level roots** (treated as reachable) are every symbol declared in a
/// consumer file (bin, test, example, …), every public symbol declared directly
/// under `lib/`, and every symbol surfaced through a public library's export
/// namespace (re-exports from `lib/src/`). A top-level symbol is reported when
/// it is unreachable from those roots and is either private or lives under
/// `lib/src/`.
///
/// **Member roots** (reachable) are: members declared in consumer files; public
/// members of public-API classes (callable by external code); and members that
/// participate in inheritance — anything annotated `@override`/`@protected`/…,
/// any member overriding a supertype member, and any member overridden by a
/// subtype (it may be invoked through dynamic dispatch). A member is reported
/// when it is unreachable, not an inheritance participant, and either private
/// or declared on a non-public-API (e.g. `lib/src`) type. Public members of
/// public-API classes are never reported — exactly as for top-level symbols.
///
/// The check is deliberately conservative: a false "dead member" is worse than
/// a miss, so anything reachable through inheritance or an annotation is kept.
class DeadCodeCheck {
  const DeadCodeCheck();

  List<Finding> run(CodeGraph graph) {
    final participants = _inheritanceParticipants(graph);
    final reachable = _reachableFrom(graph, participants);

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

    for (final node in graph.memberNodes) {
      if (reachable.contains(node)) continue;
      if (participants.contains(node)) continue;
      if (node.isConsumerFile) continue;
      // If the enclosing type is itself dead it is already reported; listing
      // its members too would be redundant noise.
      final owner = node.owner;
      if (owner != null && !reachable.contains(owner)) continue;
      if (!_memberReportable(node, graph)) continue;

      final qualified = '${node.enclosingName}.${node.name}';
      findings.add(
        Finding(
          kind: CheckKind.deadCode,
          severity: Severity.warning,
          message: "Unused ${_describeMember(node)} '$qualified' is never "
              'referenced from any entrypoint.',
          file: node.relativePath,
          line: node.line,
          symbol: qualified,
        ),
      );
    }

    findings.sort(_byLocation);
    return findings;
  }

  Set<CodeNode> _reachableFrom(CodeGraph graph, Set<CodeNode> participants) {
    final seeds = <CodeNode>[
      ...graph.nodes.where((n) => n.isConsumerFile || n.isPublicApi),
      ...graph.exportedApi,
      ...graph.memberNodes.where(
        (m) =>
            m.isConsumerFile ||
            participants.contains(m) ||
            (!m.isPrivate && _enclosingIsPublicSurface(m, graph)),
      ),
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

  /// A member is reportable when it is private, or its enclosing type is not
  /// part of the public API surface (e.g. a `lib/src` class). Public members of
  /// public-API classes are never reportable — the same rule as for top-level
  /// public symbols.
  bool _memberReportable(CodeNode node, CodeGraph graph) =>
      node.isPrivate || !_enclosingIsPublicSurface(node, graph);

  bool _enclosingIsPublicSurface(CodeNode member, CodeGraph graph) {
    final owner = member.owner;
    if (owner == null) return false;
    return owner.isPublicApi || graph.exportedApi.contains(owner);
  }

  /// Members that take part in an inheritance relationship and so may be
  /// reached through dynamic dispatch: anything carrying an inheritance-signal
  /// annotation, any member overriding a supertype member, and (the reverse)
  /// any member overridden by a subtype member.
  Set<CodeNode> _inheritanceParticipants(CodeGraph graph) {
    final participants = <CodeNode>{};
    for (final node in graph.memberNodes) {
      final element = node.element;
      if (_hasInheritanceAnnotation(element)) participants.add(node);

      final enclosing = element.enclosingElement;
      final name = element.name;
      if (enclosing is! InterfaceElement || name == null) continue;

      for (final supertype in enclosing.allSupertypes) {
        final superMember = _lookupMember(supertype.element, name, element);
        if (superMember == null) continue;
        // This member overrides a supertype member …
        participants.add(node);
        // … and (the reverse edge) the supertype member is overridden, so it
        // too must be kept even if nothing calls it directly.
        final superNode = graph.memberNodeOf(superMember);
        if (superNode != null) participants.add(superNode);
      }
    }
    return participants;
  }

  bool _hasInheritanceAnnotation(Element e) =>
      e.metadata.hasOverride ||
      e.metadata.hasProtected ||
      e.metadata.hasVisibleForTesting ||
      e.metadata.hasVisibleForOverriding ||
      e.metadata.hasMustBeOverridden;

  /// Looks up a member named [name] declared directly on [type], matching the
  /// kind of [reference] (method/getter/setter/field).
  Element? _lookupMember(
    InterfaceElement type,
    String name,
    Element reference,
  ) {
    if (reference is MethodElement) return type.getMethod(name);
    if (reference is GetterElement) return type.getGetter(name);
    if (reference is SetterElement) return type.getSetter(name);
    if (reference is FieldElement) {
      return type.getField(name) ?? type.getGetter(name);
    }
    return type.getMethod(name) ??
        type.getGetter(name) ??
        type.getSetter(name) ??
        type.getField(name);
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

  String _describeMember(CodeNode node) {
    final element = node.element;
    if (element is GetterElement) return 'getter';
    if (element is SetterElement) return 'setter';
    if (element is FieldElement) return 'field';
    return 'method';
  }

  int _byLocation(Finding a, Finding b) {
    final byFile = (a.file ?? '').compareTo(b.file ?? '');
    if (byFile != 0) return byFile;
    return (a.line ?? 0).compareTo(b.line ?? 0);
  }
}
