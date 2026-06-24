import 'used.dart';

/// A package-internal (`lib/src`, not re-exported) class. Because it is not
/// part of the public API surface, *both* its public and private members are
/// reachability-reportable when unused.
class InternalService {
  InternalService(this._seed);

  /// Private field, read by [compute] → used → clean.
  final int _seed;

  /// Public method of an internal class, called by [describeService] → used.
  int compute() => _multiply(_seed);

  /// Private method, called by [compute] → used → clean.
  int _multiply(int value) => value * 2;

  /// Private method that nobody calls → FLAGGED.
  int _unusedHelper() => 99;

  /// Public method of an *internal* class that nobody calls → FLAGGED
  /// (public members are reportable when the enclosing type is not public API).
  int unusedPublicOnInternal() => 0;
}

/// A reachable internal class whose only field is set through the constructor
/// (`this.label`) and never read. The constructor parameter counts as a use, so
/// the field must NOT be flagged.
class CtorOnlyField {
  CtorOnlyField(this.label);

  final String label;
}

/// Reachable from the public API (called by `runSample`), so it keeps
/// [InternalService] and the members it touches alive.
String describeService() {
  final service = InternalService(used().length);
  CtorOnlyField('set-but-never-read');
  return '${service.compute()}';
}

/// A private interface implemented in-package. Its abstract member is overridden
/// by [_Circle], so it participates in dispatch and must NOT be flagged even
/// though nothing calls `area()` directly.
abstract class _Shape {
  double area();
}

class _Circle implements _Shape {
  const _Circle(this.radius);

  /// Read only by [area] → used → clean.
  final double radius;

  @override
  double area() => 3.14159 * radius * radius;
}

/// Keeps [_Circle]/[_Shape] reachable without ever invoking `area()` directly,
/// exercising the override-as-reachable-root rule.
_Shape makeCircle() => const _Circle(1);
