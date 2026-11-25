/// Neither exported nor a supertype of anything exported.
class Internal {
  int used() => 1;

  /// Public, but unreachable from outside the package → FLAGGED.
  int unusedPublic() => 0;
}
