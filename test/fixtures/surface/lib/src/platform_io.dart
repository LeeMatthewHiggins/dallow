extension PlatformLabel on int {
  /// The counterpart of the stub's `label`, chosen at compile time on the VM
  /// → reachable whenever the stub's is → clean.
  String label() => _format(this);

  /// Nobody calls this, on any platform → FLAGGED.
  String neverCalled() => 'unused';
}

String _format(int value) => 'io $value';
