int triangular(int count) {
  var total = 0;
  for (var index = 1; index <= count; index++) {
    total += index;
  }
  return total;
}

String labelFor(int value) {
  if (value.isEven) {
    return 'even-$value';
  }
  return 'odd-$value';
}
