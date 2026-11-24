class Grid {
  final List<int> _cells = List.filled(4, 0);

  /// Used only as `grid[0] = 1` → clean.
  void operator []=(int index, int value) => _cells[index] = value;

  int get total => _cells.fold(0, (sum, cell) => sum + cell);
}
