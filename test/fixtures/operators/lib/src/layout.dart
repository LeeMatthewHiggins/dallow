import 'dart:ffi';

/// A native memory layout: every field matters, read from Dart or not.
final class Layout extends Struct {
  @Int32()
  external int width;

  @Int32()
  external int height;
}

int layoutSize() => sizeOf<Layout>();
