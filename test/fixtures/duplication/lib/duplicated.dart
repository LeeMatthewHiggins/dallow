int calculateAlpha(int input) {
  final adjusted = input + 1;
  final doubled = adjusted * 2;
  if (doubled > 10) {
    return doubled - 3;
  }
  return doubled + 3;
}

int calculateBeta(int value) {
  final adjusted = value + 1;
  final doubled = adjusted * 2;
  if (doubled > 10) {
    return doubled - 3;
  }
  return doubled + 3;
}
