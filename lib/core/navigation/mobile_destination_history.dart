/// Session-local history for retained mobile destinations, never Navigator
/// routes. Going Home deliberately clears the trail; Back never records itself.
class MobileDestinationHistory {
  static const _allowed = {0, 3, 1, 5, 2};
  final List<int> _entries = [0];

  bool get canGoBack => _entries.length > 1;
  int get current => _entries.last;

  void resetTo(int destination) {
    _entries
      ..clear()
      ..add(0);
    if (destination != 0 && _allowed.contains(destination)) {
      _entries.add(destination);
    }
  }

  void select(int destination) {
    if (!_allowed.contains(destination) || current == destination) return;
    if (destination == 0) {
      resetTo(0);
      return;
    }
    _entries.add(destination);
    // Always preserve the Home baseline, even after a long tab-switch session.
    if (_entries.length > 24) _entries.removeAt(1);
  }

  int? back() {
    if (!canGoBack) return null;
    _entries.removeLast();
    return current;
  }
}
