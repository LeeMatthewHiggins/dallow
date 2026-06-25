String deadFunction() => 'nobody calls me';

extension type DeadId(int value) {}

/// An unreachable private class. It is reported as a dead *class*; its members
/// must NOT be reported separately (that would be redundant noise).
class _DeadClass {
  void orphanMethod() {}
}
