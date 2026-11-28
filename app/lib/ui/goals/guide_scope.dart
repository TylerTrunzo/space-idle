import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/guide.dart';

/// Hands the [Guide] down the tree; its dependents rebuild as it moves.
class GuideScope extends InheritedNotifier<Guide> {
  /// Puts [guide] above [child].
  const GuideScope({super.key, required Guide guide, required super.child})
    : super(notifier: guide);

  /// The guide above [context], or null where there is none.
  static Guide? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuideScope>()?.notifier;
}
