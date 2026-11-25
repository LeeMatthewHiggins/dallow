int register() => 0;

/// Invoked by the VM from native code, never from Dart → must stay alive.
@pragma('vm:entry-point')
void _backgroundCallback() {}

/// Nobody calls this and it has no pragma → FLAGGED.
void _plainDead() {}

/// A header-like phrase below the first declaration is not a banner:
// GENERATED CODE - DO NOT MODIFY BY HAND
void _afterCode() {}
