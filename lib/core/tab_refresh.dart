/// Lets the desktop "R" shortcut refresh whichever tab is currently shown.
/// Each tab registers its refresh callback under its tab index; HomeShell calls
/// the active index when R is pressed.
class TabRefresh {
  final Map<int, Future<void> Function()> _handlers = {};

  void register(int index, Future<void> Function() handler) =>
      _handlers[index] = handler;

  void unregister(int index) => _handlers.remove(index);

  void refresh(int index) => _handlers[index]?.call();
}
