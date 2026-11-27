import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';

/// Shows the "while you were away" dialog whenever the controller holds
/// pending away summaries (after start or resume), one dialog at a time.
class AwaySummaryGate extends StatefulWidget {
  /// Wraps [child], which must be under a Navigator.
  const AwaySummaryGate({super.key, required this.child});

  /// The screen under the dialog.
  final Widget child;

  @override
  State<AwaySummaryGate> createState() => _AwaySummaryGateState();
}

class _AwaySummaryGateState extends State<AwaySummaryGate> {
  bool _open = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the scope brings this back on every notification.
    final c = ControllerScope.of(context);
    if (_open || c.pendingAwaySummaries.isEmpty) return;
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show(c));
  }

  Future<void> _show(GameController c) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AwayDialog(controller: c),
    );
    _open = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A placeholder away summary: the time away and credits gained across
/// every pending catch-up. Task 11 replaces it with the full summary.
class AwayDialog extends StatelessWidget {
  /// Creates the dialog for [controller]'s pending summaries.
  const AwayDialog({super.key, required this.controller});

  /// Whose summaries to show and clear.
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final all = controller.pendingAwaySummaries;
        final away = all.fold(0.0, (t, s) => t + s.secondsAway);
        final gained = all.fold(
          const BigNum.zero(),
          (BigNum t, s) => t + s.creditsGained,
        );
        final mono = monoText(Theme.of(context).textTheme.bodyLarge);
        return AlertDialog(
          title: const Text('While you were away'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Away for ${formatDuration(away)}', style: mono),
              const SizedBox(height: 4),
              Text(
                '${gained.isNegative ? '' : '+'}${formatNumber(gained)} credits',
                style: mono,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.clearAwaySummary();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
