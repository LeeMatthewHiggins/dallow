int arrangeFirst(int a, int b) {
  final sum = a + b;
  final product = a * b;
  final difference = a - b;
  return sum * product + difference * sum - product;
}

int arrangeSecond(int x, int y) {
  final sum = x + y;
  final product = x * y;
  final difference = x - y;
  return sum * product + difference * sum - product;
}
