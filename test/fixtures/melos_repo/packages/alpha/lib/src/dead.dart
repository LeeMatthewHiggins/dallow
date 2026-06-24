// Declared under lib/src/, never exported and never referenced — a dead
// symbol that recursive analysis must attribute to the `packages/alpha`
// package.
String deadAlphaSymbol() => 'nobody calls me';
