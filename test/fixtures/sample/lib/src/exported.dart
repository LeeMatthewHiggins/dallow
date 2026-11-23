class ExportedWidget {
  String render() => _decorate('hi');

  /// Public method of a *public* (re-exported) class, never called internally —
  /// it is part of the API surface, so it must NOT be flagged.
  String describe() => 'widget';

  /// Private method, called by [render] → used → clean.
  String _decorate(String s) => '[$s]$_suffix';

  /// Private field read internally by [_decorate] → used → clean.
  final String _suffix = '!';

  /// Private member of a public class, never referenced → FLAGGED (private
  /// members are reportable even on public-API classes).
  void _unusedInternal() {}
}

/// A generic public class. Inside it, references to its own members resolve
/// to members substituted with the type parameter, not to the declarations.
class GenericBox<T> {
  T? get value => _value;

  void put(T item) => _store(item);

  void forEach(void Function(void Function(T) store) visit) => visit(_store);

  /// Read and written only inside the generic class → used → clean.
  T? _value;

  /// Called and torn off only inside the generic class → used → clean.
  void _store(T item) => _value = item;

  /// Never referenced → FLAGGED.
  void _unusedInGeneric() {}
}
