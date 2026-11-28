import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/view/spend_view.dart';

/// One spend a button asks for: its price, what it buys, and how to make
/// it.
@immutable
final class Spend {
  /// Creates a spend.
  const Spend({
    required this.price,
    required this.what,
    required this.run,
    this.always = false,
  });

  /// Credits it spends.
  final BigNum price;

  /// What it buys, completing "Spend X of Y credits …?", such as "to
  /// claim Cinder" or "on 10 Speed levels for Smelter".
  final String what;

  /// Makes the spend, through the game controller.
  final VoidCallback run;

  /// Whether to confirm whatever its share: for a spend whose price the
  /// button does not show, so the player sees it before it goes through.
  final bool always;
}

/// Wraps spending buttons so a spend over half the credits held
/// ([needsConfirm]) takes a second, inline tap: "Spend 5K of 7.5K
/// credits to claim Cinder? Confirm / Cancel" below the buttons.
///
/// [builder] makes the buttons and gets `ask`, which a button calls with
/// its [Spend] instead of spending: a small one goes straight through.
/// The confirm and cancel buttons are keyed `confirm-<id>` and
/// `cancel-<id>`.
class SpendConfirm extends StatefulWidget {
  /// Creates the wrapper.
  const SpendConfirm({super.key, required this.id, required this.builder});

  /// Names the confirm's keys.
  final String id;

  /// The buttons, given the function they call to spend.
  final Widget Function(BuildContext context, void Function(Spend) ask) builder;

  @override
  State<SpendConfirm> createState() => _SpendConfirmState();
}

class _SpendConfirmState extends State<SpendConfirm> {
  Spend? _pending;

  void _ask(Spend s) {
    final c = ControllerScope.of(context);
    if (s.always ||
        needsConfirm(s.price, c.state.faction(c.playerId).credits)) {
      setState(() => _pending = s);
    } else {
      s.run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final pending = _pending;
    final held = c.state.faction(c.playerId).credits;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.builder(context, _ask),
        if (pending != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Spend ${formatNumber(pending.price)} of '
                    '${formatNumber(held, rounding: NumberRounding.down)} '
                    'credits ${pending.what}?',
                  ),
                ),
                FilledButton(
                  key: ValueKey('confirm-${widget.id}'),
                  onPressed: () {
                    setState(() => _pending = null);
                    pending.run();
                  },
                  child: const Text('Confirm'),
                ),
                TextButton(
                  key: ValueKey('cancel-${widget.id}'),
                  onPressed: () => setState(() => _pending = null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
