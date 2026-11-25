// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model.dart';

String _$encodeModel(Model instance) =>
    '${_usedOnlyByGenerated(instance.value)}${_$branchy(instance.value)}';

/// Dead generated helper → reported only when generated code is included.
String _$unusedGenerated(Model instance) => '${instance.value}';

/// Complexity 12 → reported only when generated code is included.
int _$branchy(int v) {
  if (v == 1) return 1;
  if (v == 2) return 2;
  if (v == 3) return 3;
  if (v == 4) return 4;
  if (v == 5) return 5;
  if (v == 6) return 6;
  if (v == 7) return 7;
  if (v == 8) return 8;
  if (v == 9) return 9;
  if (v == 10) return 10;
  if (v == 11) return 11;
  return 0;
}

int _$copyOne(int a, int b) {
  final sum = a + b;
  final product = a * b;
  final difference = a - b;
  final scaled = sum * product + difference;
  final shifted = scaled + sum - product * difference;
  final folded = shifted * scaled + sum * product - difference;
  return folded + shifted + scaled + sum + product + difference;
}

int _$copyTwo(int x, int y) {
  final sum = x + y;
  final product = x * y;
  final difference = x - y;
  final scaled = sum * product + difference;
  final shifted = scaled + sum - product * difference;
  final folded = shifted * scaled + sum * product - difference;
  return folded + shifted + scaled + sum + product + difference;
}
