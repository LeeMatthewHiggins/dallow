/// Used only as an annotation on a field → clean.
const _marker = Object();

class Box {
  @_marker
  int _value = 0;

  /// Never read, but its setter is in use → clean.
  int get value => _value;

  set value(int next) => _value = next;

  /// A getter with no setter that nobody reads → FLAGGED.
  int get neverRead => _value;

  int get _lonely => _value;

  /// A setter nobody assigns, beside a getter that is read → FLAGGED.
  set _lonely(int next) => _value = next;

  int readLonely() => _lonely;
}
