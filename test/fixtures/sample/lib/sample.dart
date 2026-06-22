import 'package:collection/collection.dart';

import 'src/used.dart';

String runSample() {
  final items = [used()];
  return items.firstOrNull ?? '';
}
