/// Not exported, but its public members are callable through the exported
/// `Derived`, so they are public API.
class Base {
  /// Nobody in this package reads it; external code can → clean.
  bool get inheritedGetter => true;

  /// Private, so no external caller can reach it → FLAGGED.
  int _privateUnused() => 0;
}
