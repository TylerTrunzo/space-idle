import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/projects/projects_tab.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/away_view.dart';

/// Shows the "while you were away" dialog whenever the controller holds
/// pending away summaries (after start or resume), one dialog at a time.
///
/// A Go on the dialog closes it and opens its target from here: the
/// shell's scope is above this widget, not above the dialog's route.
class AwaySummaryGate extends StatefulWidget {
  /// Wraps [child], which must be under a Navigator and a [ShellScope].
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
    final go = await showDialog<AwayGo>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AwayDialog(controller: c),
    );
    _open = false;
    if (go == null || !mounted) return;
    final shell = ShellScope.of(context);
    switch (go) {
      case AwayGoBody(:final bodyId):
        shell.openOnMap(bodyId);
      case AwayGoMegaproject(:final megaprojectId):
        shell.openProjects(ProjectsAnchor.megaproject, megaprojectId);
      case AwayGoContract(:final contractId):
        shell.openProjects(ProjectsAnchor.contract, contractId);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What happened while the player was away, every pending summary
/// together ([awayView]): the headline, the time away and what counted,
/// the credits and where they came from, what finished, new contracts,
/// milestones, stock changes, waste, the problems worth a look with a Go
/// each, contracts that need attention, and what became affordable.
///
/// OK or a Go clears the summaries and closes it; a Go pops with its
/// target.
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
        final v = awayView(controller, controller.pendingAwaySummaries);
        final text = Theme.of(context).textTheme;
        final mono = monoText(text.bodyMedium);
        final muted = text.bodyMedium?.copyWith(color: Palette.muted);
        void close([AwayGo? go]) {
          controller.clearAwaySummary();
          Navigator.of(context).pop(go);
        }

        Widget section(String title, String key, List<Widget> rows) => Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: text.titleSmall),
              ),
              ...rows,
            ],
          ),
        );
        Widget line(IconData icon, Color color, String s, {TextStyle? style}) =>
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s, style: style)),
                ],
              ),
            );
        Widget problem(
          AwayProblem p,
          String key,
          String goKey,
          Color color,
          IconData icon,
        ) => Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(p.text)),
              if (p.go case final go?)
                TextButton(
                  key: ValueKey(goKey),
                  onPressed: () => close(go),
                  child: const Text('Go'),
                ),
            ],
          ),
        );
        return AlertDialog(
          scrollable: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('While you were away', style: muted),
              const SizedBox(height: 4),
              Text(v.headline, style: text.titleMedium),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                key: const ValueKey('away-time'),
                padding: EdgeInsets.zero,
                child: line(
                  v.capped ? Icons.hourglass_bottom : Icons.schedule,
                  v.capped ? Palette.amber : Palette.muted,
                  v.timeLine,
                  style: mono,
                ),
              ),
              Padding(
                key: const ValueKey('away-net'),
                padding: EdgeInsets.zero,
                child: line(
                  Icons.account_balance_wallet_outlined,
                  Palette.cyan,
                  v.net,
                  style: monoText(text.titleMedium),
                ),
              ),
              for (final g in v.gains) Text(g, style: muted),
              if (v.attention.isNotEmpty)
                section('Needs your attention', 'away-attention', [
                  for (final (i, p) in v.attention.indexed)
                    problem(
                      p,
                      'away-attention-$i',
                      'away-attention-go-$i',
                      Palette.amber,
                      Icons.assignment_late_outlined,
                    ),
                ]),
              if (v.problems.isNotEmpty)
                section('Worth a look', 'away-problems', [
                  for (final (i, p) in v.problems.indexed)
                    problem(
                      p,
                      'away-problem-$i',
                      'away-go-$i',
                      Palette.amber,
                      Icons.warning_amber_outlined,
                    ),
                ]),
              if (v.finished.isNotEmpty)
                section('Finished', 'away-finished', [
                  for (final f in v.finished)
                    line(Icons.check_circle_outline, Palette.green, f),
                ]),
              if (v.milestones.isNotEmpty)
                section('Milestones', 'away-milestones', [
                  for (final m in v.milestones)
                    line(Icons.flag_outlined, Palette.cyan, m),
                ]),
              if (v.contracts.isNotEmpty)
                section('New contracts', 'away-contracts', [
                  for (final k in v.contracts)
                    line(Icons.assignment_outlined, Palette.cyan, k),
                ]),
              if (v.stock.isNotEmpty)
                section('Stock', 'away-stock', [
                  for (final s in v.stock)
                    line(
                      s.gain ? Icons.arrow_upward : Icons.arrow_downward,
                      s.gain ? Palette.green : Palette.red,
                      '${s.name} ${s.amount}',
                      style: mono,
                    ),
                ]),
              if (v.waste case final w?)
                Padding(
                  key: const ValueKey('away-waste'),
                  padding: const EdgeInsets.only(top: 8),
                  child: line(Icons.delete_outline, Palette.amber, w),
                ),
              if (v.afford case final a?)
                Padding(
                  key: const ValueKey('away-afford'),
                  padding: const EdgeInsets.only(top: 8),
                  child: line(Icons.shopping_cart_outlined, Palette.green, a),
                ),
              if (v.nextGoal case final g?)
                Padding(
                  key: const ValueKey('away-next'),
                  padding: const EdgeInsets.only(top: 8),
                  child: line(Icons.trending_up, Palette.cyan, g),
                ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('away-ok'),
              onPressed: close,
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
