import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/messages.dart';

/// How a building is doing, for its row's icon, label and color.
enum Severity {
  /// Running at full rate.
  ok,

  /// Running, but below full rate.
  warning,

  /// Making nothing.
  stopped,
}

/// A display name and a formatted value, such as `Iron Ore` and `-0.4/s`.
@immutable
final class NamedValue {
  /// Creates a pair.
  const NamedValue(this.name, this.value);

  /// Display name.
  final String name;

  /// The formatted value.
  final String value;
}

/// One upgrade track's button: what it is, what it costs, whether it can
/// be bought now.
@immutable
final class UpgradeButtonView {
  /// Creates a button view.
  const UpgradeButtonView({
    required this.label,
    required this.cost,
    required this.affordable,
    this.payback,
  });

  /// "Speed", "Efficiency" or "Capacity".
  final String label;

  /// Credits it costs, formatted.
  final String cost;

  /// Whether the player holds that many credits.
  final bool affordable;

  /// How soon it pays for itself, such as "8m"; null until the core's
  /// upgrade advice (stage 2 Task 0) fills it in.
  final String? payback;
}

/// A building's row in the Mission Control panel.
@immutable
final class BuildingRowView {
  /// Creates a row view.
  const BuildingRowView({
    required this.id,
    required this.name,
    required this.level,
    required this.crew,
    required this.crewBaseSlots,
    required this.crewMax,
    required this.uses,
    required this.makes,
    required this.runFraction,
    required this.severity,
    required this.problem,
    required this.upgrades,
    required this.canAddCrew,
    required this.canRemoveCrew,
  });

  /// Building id.
  final String id;

  /// Its type's display name.
  final String name;

  /// Its speed level, shown as "Lv".
  final int level;

  /// Crew assigned.
  final int crew;

  /// Its type's base crew slots.
  final int crewBaseSlots;

  /// Most crew it can hold, capacity levels included.
  final int crewMax;

  /// Each input and what it actually uses a second (`-0.4/s`), every
  /// input listed, so a starved one shows at `0/s`.
  final List<NamedValue> uses;

  /// Each output and what it actually makes a second (`+0.2/s`).
  final List<NamedValue> makes;

  /// Output as a share of full rate (supply, staffing and housing), 0 to 1.
  final double runFraction;

  /// [runFraction] as ok, warning (between 0 and 1) or stopped (0).
  final Severity severity;

  /// What holds it back, in plain English; null when nothing does.
  final String? problem;

  /// Its upgrade tracks, in track order.
  final Map<UpgradeTrack, UpgradeButtonView> upgrades;

  /// Whether one more crew can go in: below its most crew, and crew free.
  final bool canAddCrew;

  /// Whether it has crew to take out.
  final bool canRemoveCrew;
}

/// The row of building [b] on [body], from [status] (its line in the flow
/// report; null for a body the report does not cover) and the report's
/// per-building [bottlenecks].
BuildingRowView buildingRowView(
  GameState s,
  Content c,
  String playerId,
  BodyState body,
  BuildingState b,
  BuildingStatus? status,
  List<Bottleneck> bottlenecks,
) {
  final def = c.buildings[b.defId]!;
  final inputs = def.inputs.keys;
  final outputs = def.kind == BuildingKind.extractor
      ? [?b.depositResourceId]
      : def.outputs.keys;
  BigNum rate(Map<String, BigNum>? m, String id) =>
      m?[id] ?? const BigNum.zero();
  final fraction = !runsRecipe(def)
      ? 1.0
      : (status?.effectiveFraction ?? b.lastRunFraction).clamp(0.0, 1.0);
  final neck = bottlenecks.where((n) => n.buildingId == b.id).firstOrNull;
  final credits = s.faction(playerId).credits;
  final most = maxCrew(c.rules, def, b);
  return BuildingRowView(
    id: b.id,
    name: def.name,
    level: b.levels[UpgradeTrack.speed] ?? 0,
    crew: b.crew,
    crewBaseSlots: def.crewSlots,
    crewMax: most,
    uses: [
      for (final id in inputs)
        NamedValue(
          c.resources[id]!.name,
          formatRate(-rate(status?.inputsPerSec, id)),
        ),
    ],
    makes: [
      for (final id in outputs)
        NamedValue(
          c.resources[id]!.name,
          formatRate(rate(status?.outputsPerSec, id)),
        ),
    ],
    runFraction: fraction,
    severity: fraction <= 0
        ? Severity.stopped
        : (fraction < 1 ? Severity.warning : Severity.ok),
    problem: neck == null ? null : bottleneckText(s, c, playerId, neck),
    upgrades: {
      for (final t in UpgradeTrack.values)
        if (def.upgrades.containsKey(t)) t: _upgrade(c, b, t, credits),
    },
    canAddCrew: b.crew < most && availableCrew(s, c, playerId) > 0,
    canRemoveCrew: b.crew > 0,
  );
}

UpgradeButtonView _upgrade(
  Content c,
  BuildingState b,
  UpgradeTrack t,
  BigNum credits,
) {
  final cost = upgradeCost(c, b, t)[creditsKey] ?? const BigNum.zero();
  return UpgradeButtonView(
    label: switch (t) {
      UpgradeTrack.speed => 'Speed',
      UpgradeTrack.efficiency => 'Efficiency',
      UpgradeTrack.capacity => 'Capacity',
    },
    cost: formatNumber(cost),
    affordable: credits >= cost,
  );
}
