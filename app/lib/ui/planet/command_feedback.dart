import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/messages.dart';

/// Runs [cmd] on [c] and tells the player how it went.
///
/// A failure always shows the controller's [GameController.lastError],
/// on the messenger nearest [context]. A success shows its outcome's
/// sentence when [announce] is set (builds, claims, demolitions, buy
/// max), on [okMessenger] when given (a sheet that closes on success
/// passes the one under it), and stays quiet for small steps such as one
/// crew or one upgrade level.
///
/// Only one command message shows at a time: rapid taps replace it
/// rather than queue a pile of them, and other messages are left alone.
CommandResult runAndReport(
  BuildContext context,
  GameController c,
  Command cmd, {
  bool announce = false,
  ScaffoldMessengerState? okMessenger,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = c.run(cmd);
  switch (result) {
    case CommandFailed():
      if ((messenger, c.lastError) case (final m?, final why?)) _show(m, why);
    case CommandOk(:final outcome?) when announce:
      final m = okMessenger ?? messenger;
      if (m != null) {
        _show(m, outcomeMessage(c.state, c.content, cmd, outcome));
      }
    case CommandOk():
      break;
  }
  return result;
}

/// The command message last shown on each messenger.
final Expando<_Message> _last = Expando('command message');

/// One command message and where it stands in its messenger's queue.
final class _Message {
  _Message(String text) : text = ValueNotifier(text);

  /// What it says; a newer message waiting behind others rewrites it.
  final ValueNotifier<String> text;

  /// Whether it has been built: a messenger builds only the SnackBar it
  /// is showing.
  bool shown = false;

  /// Whether it has gone.
  bool closed = false;
}

/// Shows [text] on [m], replacing the last command message there: the
/// one showing is removed, and one still waiting behind another message
/// takes the new text instead of a second joining the queue.
void _show(ScaffoldMessengerState m, String text) {
  final last = _last[m];
  if (last != null && !last.closed) {
    if (!last.shown) {
      last.text.value = text;
      return;
    }
    m.removeCurrentSnackBar();
  }
  final message = _Message(text);
  _last[m] = message;
  m
      .showSnackBar(SnackBar(content: _MessageText(message)))
      .closed
      .then((_) => message.closed = true);
}

class _MessageText extends StatefulWidget {
  const _MessageText(this.message);

  final _Message message;

  @override
  State<_MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<_MessageText> {
  @override
  void initState() {
    super.initState();
    widget.message.shown = true;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.message.text,
    builder: (context, text, _) => Text(text),
  );
}
