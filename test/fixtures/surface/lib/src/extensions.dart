/// Referenced only from an unnamed extension → must stay alive.
int helperForUnnamed(int value) => value * 2;

extension NamedFlags on int {
  /// Referenced only by [isOff] → used → clean.
  bool get isOn => this != 0;

  /// Referenced only from an unnamed extension → used → clean.
  bool get isOff => !isOn;

  /// Nobody reads it → FLAGGED.
  bool get isNeverRead => false;
}

extension on int {
  int get doubled => helperForUnnamed(this);

  bool get viaNamed => isOff;
}

String usesExtension() => '${2.doubled} ${0.viaNamed}';
