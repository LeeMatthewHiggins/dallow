import 'package:collection/collection.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path/path.dart' as p;

import 'src/internal_for_typedef.dart';
import 'src/members.dart';
import 'src/platform_stub.dart' if (dart.library.io) 'src/platform_io.dart';
import 'src/used.dart';

export 'src/exported.dart';

typedef Handler = void Function(TypedefThing thing);

Handler? handler;

String get _viaGetter => used();

String get exposedViaGetter => _viaGetter;

String runSample() {
  final items = [
    used(),
    p.basename('a/b'),
    describeService(),
    platformName(),
    '${makeCircle()}'
  ];
  return items.firstOrNull ?? '';
}
