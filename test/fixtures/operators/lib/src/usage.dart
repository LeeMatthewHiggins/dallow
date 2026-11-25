import 'grid.dart';
import 'layout.dart';
import 'properties.dart';
import 'vector.dart';

String useEverything() {
  const a = Vector(1, 2);
  const b = Vector(3, 4);
  final sum = a + b;
  final negated = -sum;
  final scaled = negated(2);
  final described = switch (scaled) {
    Vector(magnitude: final m) => '$m',
  };
  final box = Box()..value = scaled[0];
  var mixed = a;
  mixed ^= b;
  final grid = Grid();
  grid[0] = mixed[1];
  return '$described ${box.readLonely()} ${layoutSize()} ${grid.total}';
}
