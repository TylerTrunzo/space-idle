import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/build_picker.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/spend_confirm.dart';
import 'package:space_idle/view/spend_view.dart';
import 'package:space_idle/view/view_models.dart';

/// One building in Mission Control: its name and level, crew pips with
/// − and +, what it uses and makes, what holds it back, and its upgrades.
///
/// A long press on the name offers Demolish, confirmed in a row of its
/// own; a long press on an upgrade buys up to [bulkLevels] levels.
class BuildingRow extends StatefulWidget {
  /// Creates the row for [view].
  const BuildingRow({super.key, required this.view});

  /// What to show.
  final BuildingRowView view;

  /// Most levels a long press on an upgrade buys, one command each.
  static const int bulkLevels = 10;

  @override
  State<BuildingRow> createState() => _BuildingRowState();
}

class _BuildingRowState extends State<BuildingRow> {
  bool _confirmDemolish = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      key: const ValueKey('building-row'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: () => setState(() => _confirmDemolish = true),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: v.name, style: text.titleMedium),
                        TextSpan(
                          text: '  Lv ${v.level}',
                          style: monoText(text.bodyMedium)
                              .copyWith(color: Palette.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (v.crewMax > 0) _CrewLine(view: v),
          _Flows(view: v),
          if (v.problem case final problem?)
            _Problem(view: v, problem: problem),
          _Upgrades(view: v),
          if (_confirmDemolish)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Demolish ${v.name}? Half its credits come back.'),
                TextButton(
                  key: ValueKey('demolish-${v.id}'),
                  onPressed: () {
                    setState(() => _confirmDemolish = false);
                    runAndReport(
                      context,
                      c,
                      DemolishCommand(c.playerId, v.id),
                      announce: true,
                    );
                  },
                  child: const Text('Demolish'),
                ),
                TextButton(
                  onPressed: () => setState(() => _confirmDemolish = false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Crew pips (filled per crew, hollow up to the most, a bar after the
/// base slots) between − and +.
class _CrewLine extends StatelessWidget {
  const _CrewLine({required this.view});

  final BuildingRowView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final c = ControllerScope.of(context);
    void set(int crew) =>
        runAndReport(context, c, AssignCrewCommand(c.playerId, v.id, crew));
    final slots = v.crewBaseSlots == 1 ? 'slot' : 'slots';
    return Row(
      children: [
        IconButton(
          key: ValueKey('crew-remove-${v.id}'),
          icon: const Icon(Icons.remove),
          tooltip: 'Take one crew out',
          onPressed: v.canRemoveCrew ? () => set(v.crew - 1) : null,
        ),
        Flexible(
          child: Semantics(
            container: true,
            label:
                'Crew ${v.crew} of ${v.crewMax}, ${v.crewBaseSlots} base $slots',
            excludeSemantics: true,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < v.crewMax; i++) ...[
                  if (i == v.crewBaseSlots && i > 0)
                    Container(width: 2, height: 14, color: Palette.muted),
                  _Pip(filled: i < v.crew),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          key: ValueKey('crew-add-${v.id}'),
          icon: const Icon(Icons.add),
          tooltip: 'Add one crew',
          onPressed: v.canAddCrew ? () => set(v.crew + 1) : null,
        ),
      ],
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? Palette.cyan : null,
      border: Border.all(color: Palette.cyan, width: 1.5),
    ),
  );
}

/// "Iron Ore -0.4/s → Steel +0.2/s".
class _Flows extends StatelessWidget {
  const _Flows({required this.view});

  final BuildingRowView view;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final mono = monoText(style);
    List<InlineSpan> part(List<NamedValue> items) => [
      for (final (i, n) in items.indexed) ...[
        if (i > 0) const TextSpan(text: ', '),
        TextSpan(text: '${n.name} '),
        TextSpan(text: n.value, style: mono),
      ],
    ];
    if (view.uses.isEmpty && view.makes.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          ...part(view.uses),
          if (view.uses.isNotEmpty && view.makes.isNotEmpty)
            const TextSpan(text: '  →  '),
          ...part(view.makes),
        ],
      ),
    );
  }
}

/// What holds the building back, amber when slowed and red when stopped,
/// with an icon; when it is a missing input, tapping it opens the
/// catalog at what makes that input.
class _Problem extends StatelessWidget {
  const _Problem({required this.view, required this.problem});

  final BuildingRowView view;
  final String problem;

  @override
  Widget build(BuildContext context) {
    final color = view.severity == Severity.stopped
        ? Palette.red
        : Palette.amber;
    final needs = view.neededResourceId;
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            view.severity == Severity.stopped
                ? Icons.error_outline
                : Icons.warning_amber_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              needs == null ? problem : '$problem. Tap to see what makes it.',
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
    if (needs == null) return line;
    return InkWell(
      key: ValueKey('problem-${view.id}'),
      onTap: () => showCatalog(context, makes: needs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: line,
      ),
    );
  }
}

/// The three upgrade buttons: label and cost, a lock when unaffordable,
/// the payback when known, and a maxed track's reason below them.
class _Upgrades extends StatelessWidget {
  const _Upgrades({required this.view});

  final BuildingRowView view;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final mono = monoText(Theme.of(context).textTheme.bodySmall);
    // The first level reports a failure; further levels of a long press
    // stop quietly at the first one the player cannot afford.
    void buy(UpgradeTrack t, {int times = 1}) {
      final cmd = UpgradeCommand(c.playerId, view.id, t);
      if (runAndReport(context, c, cmd) is CommandFailed) return;
      for (var i = 1; i < times; i++) {
        if (c.run(cmd) is CommandFailed) return;
      }
    }

    // One level: its price is on the button, so only a big one confirms.
    // Priced from the state at the tap, not the button: after a rapid
    // tap the button is stale, and an unaffordable level goes straight
    // to the command to say why.
    Spend one(UpgradeTrack t, UpgradeButtonView u) => Spend(
      price: bulkUpgrade(c, view.id, t, 1).price,
      what: 'on ${u.label} for ${view.name}',
      run: () => buy(t),
    );

    // Up to ten: the button shows one level's price, so the total always
    // shows first.
    Spend bulk(UpgradeTrack t, UpgradeButtonView u) {
      final b = bulkUpgrade(c, view.id, t, BuildingRow.bulkLevels);
      // None affordable any more (a stale button): the command says why.
      if (b.levels == 0) return one(t, u);
      final levels = b.levels == 1 ? 'level' : 'levels';
      return Spend(
        price: b.price,
        what: 'on ${b.levels} ${u.label} $levels for ${view.name}',
        run: () => buy(t, times: b.levels),
        always: true,
      );
    }

    final maxed = [
      for (final MapEntry(key: t, value: u) in view.upgrades.entries)
        if (u.maxedReason case final why?) (t, u.label, why),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpendConfirm(
          id: 'upgrade-${view.id}',
          builder: (context, ask) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(key: t, value: u) in view.upgrades.entries)
                if (u.maxedReason == null)
                  OutlinedButton(
                    key: ValueKey('upgrade-${view.id}-${t.name}'),
                    onPressed: u.affordable ? () => ask(one(t, u)) : null,
                    onLongPress: u.affordable ? () => ask(bulk(t, u)) : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!u.affordable) ...[
                              const Icon(Icons.lock_outline, size: 16),
                              const SizedBox(width: 4),
                            ],
                            Text(u.label),
                          ],
                        ),
                        Text('${u.cost} credits', style: mono),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        // Each track's payback on a line of its own, kept while it is
        // worked out, so a button never changes size as it lands.
        for (final MapEntry(key: t, value: u) in view.upgrades.entries)
          if (u.previewable)
            _Payback(
              key: ValueKey('payback-${view.id}-${t.name}'),
              buildingId: view.id,
              track: t,
              label: u.label,
              style: mono,
            ),
        for (final (_, label, why) in maxed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$label is at its best: $why',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Palette.muted),
            ),
          ),
      ],
    );
  }
}

/// An upgrade track's payback line ([paybackText]), "Speed: pays back in
/// 8m", asked for as it is drawn: the controller fills previews a few a
/// frame, so the line stays blank (its height kept) until this one is
/// ready, and rebuilds alone when previews land.
class _Payback extends StatelessWidget {
  const _Payback({
    super.key,
    required this.buildingId,
    required this.track,
    required this.label,
    required this.style,
  });

  final String buildingId;
  final UpgradeTrack track;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: c.previewsVersion,
      builder: (context, _, _) {
        final (:ready, :preview) = c.previewFor(buildingId, track);
        final text = ready ? paybackText(preview) : null;
        return Text(text == null ? ' ' : '$label: $text', style: style);
      },
    );
  }
}
