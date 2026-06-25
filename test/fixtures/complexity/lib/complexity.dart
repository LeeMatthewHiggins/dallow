int complexDecision(int value, bool enabled) {
  if (value > 0 && enabled) {
    return value;
  }
  for (var i = 0; i < value; i++) {
    value += i;
  }
  final int? maybe = enabled ? value : null;
  return maybe ?? 0;
}
