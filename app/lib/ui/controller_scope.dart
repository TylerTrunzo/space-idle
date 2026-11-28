import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';

/// Hands the [GameController] down the tree and rebuilds its dependents
/// whenever [changes] notifies: the game itself by default (each tick and
/// command), or a [ControllerGate] that holds notifications back while
/// its part of the screen is hidden.
class ControllerScope extends InheritedNotifier<Listenable> {
  /// Puts [controller] above [child]; its dependents rebuild when
  /// [changes] (by default [controller]) notifies.
  const ControllerScope({
    super.key,
    required this.controller,
    Listenable? changes,
    required super.child,
  }) : super(notifier: changes ?? controller);

  /// The game.
  final GameController controller;

  /// The controller above [context], without rebuilding the caller when
  /// it notifies: for widgets that listen in their own way.
  static GameController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ControllerScope>();
    assert(scope != null, 'No ControllerScope above this widget.');
    return scope!.controller;
  }

  /// The controller above [context]; the caller rebuilds when the scope's
  /// change signal notifies.
  static GameController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ControllerScope>();
    assert(scope != null, 'No ControllerScope above this widget.');
    return scope!.controller;
  }
}

/// Passes on the game's notifications only while [open]: a hidden tab's
/// scope uses one, so the tab doesn't rebuild on every tick while nobody
/// sees it. Opening it after a notification was held back notifies once,
/// so the tab catches up as it is shown.
class ControllerGate extends ChangeNotifier {
  /// Creates a gate on [controller], open or shut as [open] says.
  ControllerGate(this.controller, {bool open = true}) : _isOpen = open {
    controller.addListener(_onGame);
  }

  /// The game it listens to.
  final GameController controller;

  bool _isOpen;
  bool _missed = false;

  /// Whether notifications pass now.
  bool get open => _isOpen;

  set open(bool value) {
    if (value == _isOpen) return;
    _isOpen = value;
    if (value && _missed) {
      _missed = false;
      notifyListeners();
    }
  }

  void _onGame() {
    if (_isOpen) {
      notifyListeners();
    } else {
      _missed = true;
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onGame);
    super.dispose();
  }
}
