import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'src/internal_for_typedef.dart';
import 'src/used.dart';

export 'src/exported.dart';

typedef Handler = void Function(TypedefThing thing);

Handler? handler;

String runSample() {
  final items = [used(), p.basename('a/b')];
  return items.firstOrNull ?? '';
}
