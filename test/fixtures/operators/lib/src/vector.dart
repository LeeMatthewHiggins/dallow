class Vector {
  const Vector(this._x, this._y);

  final int _x;
  final int _y;

  /// Used only as `a + b` → clean.
  Vector operator +(Vector other) => Vector(_x + other._x, _y + other._y);

  /// Used only as `a[0]` → clean.
  int operator [](int index) => index == 0 ? _x : _y;

  /// Used only as `-a` → clean.
  Vector operator -() => Vector(-_x, -_y);

  /// Used only as `a(2)` → clean.
  Vector call(int scale) => Vector(_x * scale, _y * scale);

  /// Read only through an object pattern → clean.
  int get magnitude => _x.abs() + _y.abs();

  /// Used only as `a ^= b` → clean.
  Vector operator ^(Vector other) => Vector(_x ^ other._x, _y ^ other._y);

  /// Nobody multiplies vectors → FLAGGED.
  Vector operator *(int scale) => Vector(_x * scale, _y * scale);
}
