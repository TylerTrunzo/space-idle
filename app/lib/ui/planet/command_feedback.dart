import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/messages.dart';

/// Runs [cmd] on [c] and tells the player how it went.
///
/// A failure always shows the controller's [GameController.lastError]. A
/// success shows its outcome's sentence when [announce] is set (builds,
/// claims, demolitions, buy max), and stays quiet for small steps such as
/// one crew or one upgrade level. Only one message shows at a time: rapid
/// taps replace it rather than queue a pile of them.
CommandResult runAndReport(
  BuildContext context,
  GameController c,
  Command cmd, {
  bool announce = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = c.run(cmd);
  final text = switch (result) {
    CommandFailed() => c.lastError,
    CommandOk(:final outcome?) when announce => outcomeMessage(
      c.state,
      c.content,
      cmd,
      outcome,
    ),
    CommandOk() => null,
  };
  if (text != null && messenger != null) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
  return result;
}
