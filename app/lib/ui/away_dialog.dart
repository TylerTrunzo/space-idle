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
/// It is worked out when it opens and again only when another summary
/// lands, so what it says holds still while the game ticks under it. OK or
/// a Go clears the summaries and closes it; a Go pops with its target.
class AwayDialog extends StatefulWidget {
  /// Creates the dialog for [controller]'s pending summaries.
  const AwayDialog({super.key, required this.controller});

  /// Whose summaries to show and clear.
  final GameController controller;

  @override
  State<AwayDialog> createState() => _AwayDialogState();
}

class _AwayDialogState extends State<AwayDialog> {
  late AwayView _view;
  int _count = 0;

  GameController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _work();
    _c.addListener(_follow);
  }

  @override
  void dispose() {
    _c.removeListener(_follow);
    super.dispose();
  }

  void _work() {
    _count = _c.pendingAwaySummaries.length;
    _view = awayView(_c, _c.pendingAwaySummaries);
  }

  /// A new summary (a resume while open) is the only reason to work it
  /// out again; once cleared there is nothing to show.
  void _follow() {
    final n = _c.pendingAwaySummaries.length;
    if (n == _count || n == 0) return;
    setState(_work);
  }

  void _close([AwayGo? go]) {
    _c.clearAwaySummary();
    Navigator.of(context).pop(go);
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
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
        children: [..._top(context, v), ..._sections(v)],
      ),
      actions: [
        TextButton(
          key: const ValueKey('away-ok'),
          onPressed: _close,
          child: const Text('OK'),
        ),
      ],
    );
  }

  /// The time away, the net credits and where they came from.
  List<Widget> _top(BuildContext context, AwayView v) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    return [
      _AwayRow(
        key: const ValueKey('away-time'),
        icon: v.capped ? Icons.hourglass_bottom : Icons.schedule,
        color: v.capped ? Palette.amber : Palette.muted,
        text: v.timeLine,
        style: monoText(text.bodyMedium),
        gap: 0,
      ),
      _AwayRow(
        key: const ValueKey('away-net'),
        icon: Icons.account_balance_wallet_outlined,
        color: Palette.cyan,
        text: v.net,
        style: monoText(text.titleMedium),
      ),
      for (final g in v.gains) Text(g, style: muted),
    ];
  }

  /// Each list of the summary under its heading, and the closing lines.
  List<Widget> _sections(AwayView v) {
    _AwayRow problem(AwayProblem p, String key, String goKey, IconData icon) =>
        _AwayRow(
          key: ValueKey(key),
          icon: icon,
          color: Palette.amber,
          text: p.text,
          goKey: goKey,
          onGo: switch (p.go) {
            final go? => () => _close(go),
            null => null,
          },
        );
    return [
      if (v.attention.isNotEmpty)
        _Section('Needs your attention', 'away-attention', [
          for (final (i, p) in v.attention.indexed)
            problem(
              p,
              'away-attention-$i',
              'away-attention-go-$i',
              Icons.assignment_late_outlined,
            ),
        ]),
      if (v.problems.isNotEmpty)
        _Section('Worth a look', 'away-problems', [
          for (final (i, p) in v.problems.indexed)
            problem(
              p,
              'away-problem-$i',
              'away-go-$i',
              Icons.warning_amber_outlined,
            ),
        ]),
      if (v.finished.isNotEmpty)
        _Section('Finished', 'away-finished', [
          for (final f in v.finished)
            _AwayRow(
              icon: Icons.check_circle_outline,
              color: Palette.green,
              text: f,
            ),
        ]),
      if (v.milestones.isNotEmpty)
        _Section('Milestones', 'away-milestones', [
          for (final m in v.milestones)
            _AwayRow(icon: Icons.flag_outlined, color: Palette.cyan, text: m),
        ]),
      if (v.contracts.isNotEmpty)
        _Section('New contracts', 'away-contracts', [
          for (final k in v.contracts)
            _AwayRow(
              icon: Icons.assignment_outlined,
              color: Palette.cyan,
              text: k,
            ),
        ]),
      if (v.stock.isNotEmpty)
        _Section('Stock', 'away-stock', [
          for (final s in v.stock)
            _AwayRow(
              icon: s.gain ? Icons.arrow_upward : Icons.arrow_downward,
              color: s.gain ? Palette.green : Palette.red,
              text: '${s.name} ${s.amount}',
              mono: true,
            ),
        ]),
      if (v.waste case final w?)
        _AwayRow(
          key: const ValueKey('away-waste'),
          icon: Icons.delete_outline,
          color: Palette.amber,
          text: w,
          gap: 8,
        ),
      if (v.afford case final a?)
        _AwayRow(
          key: const ValueKey('away-afford'),
          icon: Icons.shopping_cart_outlined,
          color: Palette.green,
          text: a,
          gap: 8,
        ),
      if (v.nextGoal case final g?)
        _AwayRow(
          key: const ValueKey('away-next'),
          icon: Icons.trending_up,
          color: Palette.cyan,
          text: g,
          gap: 8,
        ),
    ];
  }
}

/// A heading and its rows.
class _Section extends StatelessWidget {
  const _Section(this.title, this.id, this.rows);

  final String title;
  final String id;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey(id),
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        ...rows,
      ],
    ),
  );
}

/// One line of the summary: an icon and its text, so no state is told by
/// colour alone, and a Go when there is somewhere to go.
class _AwayRow extends StatelessWidget {
  const _AwayRow({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.style,
    this.mono = false,
    this.gap = 4,
    this.onGo,
    this.goKey,
  });

  final IconData icon;
  final Color color;
  final String text;
  final TextStyle? style;

  /// Whether the text is a figure, in the monospace face.
  final bool mono;

  /// Space above the row.
  final double gap;

  /// Closes the dialog for the row's target; null hides Go.
  final VoidCallback? onGo;

  /// Names the Go button, for tests.
  final String? goKey;

  @override
  Widget build(BuildContext context) {
    final go = onGo;
    final body = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: EdgeInsets.only(top: gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: style ?? (mono ? monoText(body) : null)),
          ),
          if (go != null)
            TextButton(
              key: switch (goKey) {
                final k? => ValueKey<String>(k),
                null => null,
              },
              onPressed: go,
              child: const Text('Go'),
            ),
        ],
      ),
    );
  }
}
