import 'dart:async';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/lazy_list.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/spend_confirm.dart';
import 'package:space_idle/ui/projects/contract_card.dart';
import 'package:space_idle/ui/projects/station_card.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/project_views.dart';

/// A request to show one system's Survey row, as a tap on the star map's
/// signal marker makes: [serial] tells one tap from the next on the same
/// system.
@immutable
final class SurveyFocus {
  /// Creates a request.
  const SurveyFocus(this.systemId, this.serial);

  /// The system whose signal was tapped.
  final String systemId;

  /// Counts the requests, so a second tap scrolls to the row again.
  final int serial;

  @override
  bool operator ==(Object other) =>
      other is SurveyFocus &&
      other.systemId == systemId &&
      other.serial == serial;

  @override
  int get hashCode => Object.hash(systemId, serial);
}

/// The Projects tab: every project under way with its countdown, a Survey
/// row per system with signals, a card for each megaproject, and the
/// contracts board.
///
/// [focus] scrolls to its system's Survey row and marks it.
class ProjectsTab extends StatefulWidget {
  /// Creates the tab.
  const ProjectsTab({super.key, this.focus});

  /// The Survey row to show, from the star map's signal marker.
  final SurveyFocus? focus;

  @override
  State<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<ProjectsTab> {
  final ScrollController _scroll = ScrollController();

  /// One key per row that can be scrolled to, by name.
  final Map<String, GlobalKey> _keys = {};

  /// The system whose Survey row is marked, after a focus.
  String? _focused;

  GlobalKey _anchor(String name) => _keys.putIfAbsent(name, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _focus();
  }

  @override
  void didUpdateWidget(ProjectsTab old) {
    super.didUpdateWidget(old);
    if (widget.focus != old.focus) _focus();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focus() {
    final f = widget.focus;
    if (f == null) return;
    _focused = f.systemId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = ControllerScope.of(context);
      final has = surveyViews(c).any((s) => s.systemId == f.systemId);
      unawaited(_reveal(_anchor(has ? 'survey-${f.systemId}' : 'survey')));
    });
  }

  /// Scrolls the row under [key] into view. The list is lazy, so a row
  /// below the fold may not be built yet: it steps down a screen at a time
  /// from the top until the row is.
  Future<void> _reveal(GlobalKey key) async {
    if (key.currentContext == null && _scroll.hasClients) _scroll.jumpTo(0);
    for (var i = 0; i < 40; i++) {
      if (!mounted) return;
      final still = MediaQuery.disableAnimationsOf(context);
      if (key.currentContext case final at? when at.mounted) {
        await Scrollable.ensureVisible(
          at,
          alignment: 0.1,
          duration: still ? Duration.zero : const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.pixels >= p.maxScrollExtent) return;
      _scroll.jumpTo(
        math.min(p.pixels + p.viewportDimension * 0.8, p.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final projects = projectViews(c);
    final surveys = surveyViews(c);
    final contracts = contractViews(c);
    final next = nextContractIn(c);
    Widget heading(String title, String key) => Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(title, style: text.titleMedium),
      ),
    );
    final items = <Widget>[
      heading('Under way', 'h-projects'),
      if (projects.isEmpty)
        Text(
          key: const ValueKey('projects-none'),
          'No projects under way.',
          style: muted,
        ),
      for (final p in projects)
        _ProjectRow(key: ValueKey('project-${p.id}'), view: p),
      heading('Survey', 'h-survey'),
      if (surveys.isEmpty)
        KeyedSubtree(
          key: _anchor('survey'),
          child: const _NoSurvey(key: ValueKey('survey-none')),
        ),
      for (final s in surveys)
        KeyedSubtree(
          key: _anchor('survey-${s.systemId}'),
          child: _SurveyRow(
            key: ValueKey('survey-${s.systemId}'),
            view: s,
            focused: _focused == s.systemId,
          ),
        ),
      heading('Megaprojects', 'h-megaprojects'),
      for (final m in megaprojectViews(c))
        MegaprojectCard(
          key: ValueKey('mp-${m.id}'),
          view: m,
          onGoToContract: (id) => unawaited(_reveal(_anchor('contract-$id'))),
        ),
      heading('Contracts', 'h-contracts'),
      if (contracts.isEmpty)
        Text(
          key: const ValueKey('contracts-none'),
          'No contracts on the board.',
          style: muted,
        ),
      for (final k in contracts)
        KeyedSubtree(
          key: _anchor('contract-${k.id}'),
          child: ContractCard(key: ValueKey('contract-${k.id}'), view: k),
        ),
      if (next != null)
        Padding(
          key: const ValueKey('next-contract'),
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: Palette.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  next == 'due now'
                      ? 'Next contract due now'
                      : 'Next contract in $next',
                  style: muted,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(key: ValueKey('end'), height: 24),
    ];
    return ColoredBox(
      color: Palette.panel,
      child: LazyList(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        items: items,
      ),
    );
  }
}

/// A project under way: what it is, its countdown, and a Go to its body.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({super.key, required this.view});

  final ProjectView view;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = view;
    final body = v.bodyId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_icon(v.kind), color: Palette.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.title, style: text.bodyLarge),
                Text('${v.remaining} left', style: monoText(text.bodyMedium)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: v.progress,
                  color: Palette.cyan,
                  backgroundColor: Palette.border,
                  semanticsLabel: '${v.title}, ${v.remaining} left',
                  semanticsValue: '${(v.progress * 100).floor()}%',
                ),
              ],
            ),
          ),
          if (body != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: ValueKey('project-go-${v.id}'),
              onPressed: () => ShellScope.of(context).openOnMap(body),
              child: const Text('Go'),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(ProjectKind k) => switch (k) {
    ProjectKind.claim => Icons.flag_outlined,
    ProjectKind.survey => Icons.radar,
    ProjectKind.expandSlots => Icons.add_box_outlined,
    ProjectKind.megaprojectStage => Icons.account_balance_outlined,
  };
}

/// One system's Survey row: signals, cost, time, and the button.
class _SurveyRow extends StatelessWidget {
  const _SurveyRow({super.key, required this.view, required this.focused});

  final SurveyView view;

  /// Whether the star map's signal marker asked for it.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final v = view;
    final source = v.sourceBodyId;
    final row = Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: Palette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${v.systemName}: ${v.signals == 1 ? '1 signal' : '${v.signals} signals'}',
                  style: text.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: text.bodyMedium,
              children: [
                const TextSpan(text: 'Costs '),
                TextSpan(text: v.cost, style: monoText(text.bodyMedium)),
                if (v.sourceName case final n?)
                  TextSpan(text: ' (drones from $n)'),
                const TextSpan(text: ', done in '),
                TextSpan(text: v.time, style: monoText(text.bodyMedium)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SpendConfirm(
            // One per paying body: a confirm asked with another body's
            // drones never goes through with these.
            key: ValueKey('survey-confirm-${v.systemId}-$source'),
            id: 'survey-${v.systemId}',
            builder: (context, ask) => FilledButton.icon(
              key: ValueKey('survey-start-${v.systemId}'),
              icon: const Icon(Icons.radar),
              label: const Text('Survey'),
              onPressed: v.blockedReason == null && source != null
                  ? () => ask(
                      Spend(
                        price: v.price,
                        what: 'to survey a signal in ${v.systemName}',
                        run: () => runAndReport(
                          context,
                          c,
                          SurveyCommand(c.playerId, null, source),
                          announce: true,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          if (v.blockedReason case final why?) BlockedReason(why),
        ],
      ),
    );
    if (!focused) return row;
    return DecoratedBox(
      key: ValueKey('survey-focus-${v.systemId}'),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.cyan, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Semantics(
        liveRegion: true,
        label: 'Survey ${v.systemName}',
        child: row,
      ),
    );
  }
}

/// Survey with no signal left anywhere: disabled, and why.
class _NoSurvey extends StatelessWidget {
  const _NoSurvey({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          key: const ValueKey('survey-start-none'),
          icon: const Icon(Icons.radar),
          label: const Text('Survey'),
          onPressed: null,
        ),
        const BlockedReason(
          'No signals left to survey in the systems you are in',
        ),
      ],
    ),
  );
}
