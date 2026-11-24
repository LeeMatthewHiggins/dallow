/// Complexity 4: over the configured maximum of 2, under the default of 10.
int decide(int v) {
  if (v == 1) return 1;
  if (v == 2) return 2;
  if (v == 3) return 3;
  return 0;
}

/// Nobody calls this → dead, reported at the configured `error` severity.
int _unused() => 0;
