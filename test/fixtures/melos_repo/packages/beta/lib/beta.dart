// Imports `collection`, which is not declared in beta's pubspec.yaml — a
// missing-dependency error that recursive analysis must attribute to the
// `packages/beta` package.
import 'package:collection/collection.dart';

int? firstOrNull(List<int> values) => values.firstOrNull;
