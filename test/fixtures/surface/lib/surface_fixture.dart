import 'src/extensions.dart';
import 'src/internal.dart';
import 'src/platform_stub.dart' if (dart.library.io) 'src/platform_io.dart';
import 'src/snippet.dart';

export 'src/derived.dart' show Derived;

String runSurface() =>
    '${usesExtension()} ${Internal().used()} $snippet ${1.label()}';
