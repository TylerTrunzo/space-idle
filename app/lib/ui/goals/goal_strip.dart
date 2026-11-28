import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/guide.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/goals/guide_scope.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/goal_strip_view.dart';

/// The goal strip, under the top bar on every tab: Now, Today and Long,
/// each an icon, a title, a bar when it has a measure and a chevron when a
/// tap opens something. Folds to its Now row (the fold is kept in the
/// settings). Informational only.
///
/// When the guide passes a step it says "Done: …" once, in a short
/// message.
class GoalStrip extends StatefulWidget {
  /// Creates the strip.
  const GoalStrip({super.key});

  /// The most of the screen's height the strip takes; past it, it
  /// scrolls.
  static const double maxShare = 0.25;

  @override
  State<GoalStrip> createState() => _GoalStripState();
}

class _GoalStripState extends State<GoalStrip> {
  Guide? _guide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = GuideScope.maybeOf(context);
    if (g != _guide) {
      _guide?.lastDone.removeListener(_done);
      _guide = g?..lastDone.addListener(_done);
    }
  }

  @override
  void dispose() {
    _guide?.lastDone.removeListener(_done);
    super.dispose();
  }

  void _done() {
    final title = _guide?.lastDone.value;
    if (title == null) return;
    _guide!.lastDone.value = null;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('Done: $title')));
  }

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final guide = GuideScope.maybeOf(context);
    return ValueListenableBuilder<int>(
      valueListenable: c.previewsVersion,
      builder: (context, _, _) {
        final step = guide?.step;
        // The best upgrade is asked for only when Now would show it, and
        // is searched in the fills, never here.
        final wantsBest = step == null && c.flow.bottlenecks.isEmpty;
        final best = wantsBest ? c.bestUpgradeNow() : null;
        final view = goalStripView(
          c,
          guideStep: step,
          best: best?.best,
          bestReady: best?.ready ?? true,
          nextGoal: c.measuredNow().goal,
        );
        final collapsed = guide?.collapsed ?? false;
        // At most a quarter of the screen: past that, at large text on a
        // small phone, the strip scrolls and the tab below keeps its room.
        return Material(
          color: Palette.background,
          shape: const Border(bottom: BorderSide(color: Palette.border)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * GoalStrip.maxShare,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _Goal(goal: view.now),
                          if (!collapsed) ...[
                            _Goal(goal: view.today),
                            _Goal(goal: view.long),
                          ],
                        ],
                      ),
                    ),
                    if (guide != null)
                      IconButton(
                        key: const ValueKey('goals-fold'),
                        icon: Icon(
                          collapsed ? Icons.expand_more : Icons.expand_less,
                        ),
                        tooltip: collapsed
                            ? 'Show all goals'
                            : 'Fold the goals',
                        onPressed: () => guide.setCollapsed(!collapsed),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One slot's row.
class _Goal extends StatelessWidget {
  const _Goal({required this.goal});

  final GoalView goal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final g = goal;
    final slot = switch (g.slot) {
      GoalSlot.now => 'Now',
      GoalSlot.today => 'Today',
      GoalSlot.long => 'Long',
    };
    final action = g.action;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(_icon(g.kind), size: 20, color: _color(g.kind)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$slot  ',
                          style: monoText(text.labelSmall)
                              .copyWith(color: Palette.muted),
                        ),
                        TextSpan(text: g.title, style: text.bodyMedium),
                      ],
                    ),
                  ),
                  if (g.detail case final d?)
                    Text(
                      d,
                      style: text.bodySmall?.copyWith(color: Palette.muted),
                    ),
                  if (g.progress case final p?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: LinearProgressIndicator(
                        value: p,
                        color: Palette.cyan,
                        backgroundColor: Palette.border,
                      ),
                    ),
                ],
              ),
            ),
            if (action != null)
              const Icon(Icons.chevron_right, color: Palette.cyan),
          ],
        ),
      ),
    );
    final key = ValueKey('goal-${g.slot.name}');
    if (action == null) return KeyedSubtree(key: key, child: row);
    return InkWell(
      key: key,
      onTap: () => switch (action) {
        SelectBodyAction(:final bodyId) => ShellScope.of(
          context,
        ).openOnMap(bodyId),
      },
      child: row,
    );
  }

  static IconData _icon(GoalKind k) => switch (k) {
    GoalKind.guide => Icons.school_outlined,
    GoalKind.problem => Icons.warning_amber_outlined,
    GoalKind.upgrade => Icons.trending_up,
    GoalKind.milestone => Icons.flag_outlined,
    GoalKind.contract => Icons.assignment_outlined,
    GoalKind.megaproject => Icons.account_balance_outlined,
    GoalKind.claim => Icons.public,
    GoalKind.survey => Icons.radar,
    GoalKind.none => Icons.check_circle_outline,
  };

  static Color _color(GoalKind k) => switch (k) {
    GoalKind.problem => Palette.amber,
    GoalKind.none => Palette.muted,
    _ => Palette.cyan,
  };
}
