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
