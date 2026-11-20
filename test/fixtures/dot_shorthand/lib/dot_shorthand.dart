// @dart = 3.10

// Regression fixture: Dart 3.10 dot shorthands where the analyzer must write
// them into a library summary (parameter defaults and other const contexts).
// An analyzer older than 14 throws `Missing implementation of
// visitDotShorthandInvocation` / `visitDotShorthandPropertyAccess` from its
// BundleWriter here, which crashed the released dallow binary (exit 255).

enum Mode { fast, slow }

class Box {
  const Box.make();

  static Box empty() => const Box.make();
}

class Pair {
  const Pair(this.mode, this.box);

  final Mode mode;
  final Box box;
}

/// Dot-shorthand constructor invocation in a default value.
void takeBox({Box box = const .make()}) {}

/// Dot-shorthand property access in a default value.
void takeMode({Mode mode = .fast}) {}

/// Dot-shorthand constructor call and enum value nested in a const context.
const Pair defaultPair = Pair(.slow, .make());

/// Dot-shorthand unnamed constructor (`.new`) as a top-level const.
const Pair newPair = .new(Mode.fast, Box.make());

/// Dot-shorthand static method call in a non-const context.
Box freshBox() => .empty();
