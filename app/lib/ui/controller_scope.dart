import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';

/// Hands the [GameController] down the tree and rebuilds its dependents
/// whenever the game notifies (each tick and command).
class ControllerScope extends InheritedNotifier<GameController> {
  /// Puts [controller] above [child].
  const ControllerScope({
    super.key,
    required GameController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller above [context]; the caller rebuilds when it notifies.
  static GameController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ControllerScope>();
    assert(scope != null, 'No ControllerScope above this widget.');
    return scope!.notifier!;
  }
}
