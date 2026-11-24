/// A generic internal class. Its members are reached through an instantiated
/// type (`Box<int>`), so the analyzer resolves each call to a substituted
/// member rather than the declaration; the call must still count as a use.
class Box<T> {
  Box(this._value);

  final T _value;

  /// Called on a `Box<int>` → used → clean.
  T unwrap() => _value;

  /// Nobody calls this → FLAGGED.
  T neverUnwrapped() => _value;
}

extension _FirstOrFallback<E> on List<E> {
  /// Called on a `List<int>` → used → clean.
  E firstOrFallback(E fallback) => isEmpty ? fallback : first;

  /// Nobody calls this → FLAGGED.
  E lastOrFallback(E fallback) => isEmpty ? fallback : last;
}

/// Reachable from the public API (called by `runGenerics`).
int unwrapGenerics() => [Box(1).unwrap()].firstOrFallback(0);
