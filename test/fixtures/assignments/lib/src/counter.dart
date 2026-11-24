class Counter {
  /// Read only through `++` → used → clean.
  int _postIncremented = 0;

  /// Read only through a prefix `++` → used → clean.
  int _preIncremented = 0;

  /// Read only through `??=` → used → clean.
  String? _lazilyAssigned;

  /// Read only through `+=` → used → clean.
  int _accumulated = 0;

  /// Read only through a static `++` → used → clean.
  static int _staticCounter = 0;

  /// Assigned but never read → FLAGGED.
  int _writeOnly = 0;

  int _backing = 0;

  /// An explicit setter invoked only by assignment → used → clean.
  set _viaSetter(int value) => _backing = value;

  /// An explicit setter nobody assigns → FLAGGED.
  set _unusedSetter(int value) => _backing = value;

  int bump() {
    _postIncremented++;
    ++_preIncremented;
    _lazilyAssigned ??= 'ready';
    _accumulated += 2;
    _staticCounter++;
    _writeOnly = 5;
    _viaSetter = 1;
    return _backing;
  }
}
