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
    this.maxedReason,
    this.payback,
  });

  /// "Speed", "Efficiency" or "Capacity".
  final String label;

  /// Credits it costs, formatted.
  final String cost;

  /// Whether it can be bought now: the building is on a body the player
  /// owns, the track is not maxed, and the player holds that many credits.
  final bool affordable;

  /// Why the track can go no higher (the core's `upgradeMaxedReason`,
  /// such as "its inputs are at the 25% floor"); null while it can.
  final String? maxedReason;

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
    this.neededResourceId,
  });

  /// Building id.
  final String id;

  /// Its type's display name; an extractor's with the resource it mines,
  /// such as "Mine (Iron Ore)".
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

  /// Share of full rate, 0 to 1: the lower of its input supply and its
  /// output against base crew (staffing and housing).
  final double runFraction;

  /// [runFraction] as ok, warning (between 0 and 1) or stopped (0); a
  /// building a bottleneck names is at least a warning.
  final Severity severity;

  /// What holds it back, in plain English; null when nothing does.
  final String? problem;

  /// Its upgrade tracks, in track order.
  final Map<UpgradeTrack, UpgradeButtonView> upgrades;

  /// Whether one more crew can go in: below its most crew, and crew free.
  final bool canAddCrew;

  /// Whether it has crew to take out.
  final bool canRemoveCrew;

  /// The input it is short of, when its problem is one ("not enough Iron
  /// Ore"), so the panel can offer what makes it; else null.
  final String? neededResourceId;
}

/// What every building row of one body view shares, worked out once for
/// the view rather than once a row.
@immutable
final class RowContext {
  /// Creates a context.
  const RowContext({
    required this.owned,
    required this.credits,
    required this.freeCrew,
    required this.bottlenecks,
    this.crewShort,
    this.preview,
  });

  /// [playerId]'s context for the rows of [body], from [s] and its flow
  /// report's per-building [bottlenecks].
  factory RowContext.of(
    GameState s,
    Content c,
    String playerId,
    BodyState body,
    List<Bottleneck> bottlenecks, {
    UpgradePreview? Function(String buildingId, UpgradeTrack track)? preview,
  }) => RowContext(
    owned: body.ownerId == playerId,
    credits: s.faction(playerId).credits,
    freeCrew: availableCrew(s, c, playerId),
    bottlenecks: {for (final n in bottlenecks.reversed) ?n.buildingId: n},
    crewShort: bottlenecks.any((n) => n.kind == BottleneckKind.crewShortage)
        ? crewShortText(s, c, playerId)
        : null,
    preview: preview,
  );

  /// Whether the player owns the body: on anyone else's, its rows offer
  /// no crew or upgrade actions.
  final bool owned;

  /// Credits the player holds.
  final BigNum credits;

  /// Crew the player can still assign.
  final int freeCrew;

  /// Building id to the first bottleneck the report names it in.
  final Map<String, Bottleneck> bottlenecks;

  /// While the faction's housing falls short of its assigned crew, the
  /// line a crewed building that housing holds back shows when no
  /// bottleneck names it; else null. The shortage names no building, so
  /// the per-building lookup misses it.
  final String? crewShort;

  /// What one more level of a track would bring (the core's
  /// `upgradePreview`, cached by the controller); null for no paybacks.
  final UpgradePreview? Function(String buildingId, UpgradeTrack track)?
  preview;
}

/// The row of building [b], from [status] (its line in the flow report;
/// null for a body the report does not cover) and [ctx].
BuildingRowView buildingRowView(
  GameState s,
  Content c,
  String playerId,
  BuildingState b,
  BuildingStatus? status,
  RowContext ctx,
) {
  final def = c.buildings[b.defId]!;
  final inputs = def.inputs.keys;
  final outputs = def.kind == BuildingKind.extractor
      ? [?b.depositResourceId]
      : def.outputs.keys;
  BigNum rate(Map<String, BigNum>? m, String id) =>
      m?[id] ?? const BigNum.zero();
  final fraction = runsRecipe(def) ? _fraction(b, status) : 1.0;
  final neck = ctx.bottlenecks[b.id];
  final housing = ctx.crewShort != null && _shortOfHousing(def, b, status);
  final most = maxCrew(c.rules, def, b);
  return BuildingRowView(
    id: b.id,
    name: switch (b.depositResourceId) {
      final id? when def.kind == BuildingKind.extractor =>
        '${def.name} (${c.resources[id]?.name ?? id})',
      _ => def.name,
    },
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
    severity: switch (fraction) {
      <= 0 => Severity.stopped,
      < 1 => Severity.warning,
      // Held back by a bottleneck or by housing, whatever its share.
      _ => neck == null && !housing ? Severity.ok : Severity.warning,
    },
    problem: neck != null
        ? bottleneckText(s, c, playerId, neck)
        : (housing ? ctx.crewShort : null),
    upgrades: {
      for (final t in UpgradeTrack.values)
        if (def.upgrades.containsKey(t)) t: _upgrade(c, b, t, ctx),
    },
    canAddCrew: ctx.owned && b.crew < most && ctx.freeCrew > 0,
    canRemoveCrew: ctx.owned && b.crew > 0,
    neededResourceId: switch (neck?.kind) {
      BottleneckKind.input || BottleneckKind.routeLimited => neck?.resourceId,
      _ => null,
    },
  );
}

/// A recipe building's share of full rate, 0 to 1: the lower of its supply
/// share ([BuildingStatus.runFraction]) and its output share
/// ([BuildingStatus.effectiveFraction]). Capacity crew lifts the output
/// share above 1, which on its own would hide a starved input.
double _fraction(BuildingState b, BuildingStatus? status) {
  final supply = status?.runFraction ?? b.lastRunFraction;
  final output = status?.effectiveFraction ?? supply;
  return (supply < output ? supply : output).clamp(0.0, 1.0);
}

/// Whether housing holds [b] back: it makes less than its own crew would
/// with every input it got, `runFraction × crew / base slots`, the gap
/// being the faction's crew efficiency. Compared against what the building
/// wants, not 1, since capacity crew lifts that above 1; and false for a
/// building with no crew or no slots, so crew is never blamed where it is
/// not the cause.
bool _shortOfHousing(BuildingDef def, BuildingState b, BuildingStatus? st) {
  if (b.crew <= 0 || def.crewSlots <= 0) return false;
  if (st case BuildingStatus(
    runFraction: final run?,
    effectiveFraction: final out?,
  )) {
    final wants = run * b.crew / def.crewSlots;
    return out < wants * (1 - 1e-9);
  }
  return false;
}

UpgradeButtonView _upgrade(
  Content c,
  BuildingState b,
  UpgradeTrack t,
  RowContext ctx,
) {
  final cost = upgradeCost(c, b, t)[creditsKey] ?? const BigNum.zero();
  final maxed = upgradeMaxedReason(c, b, t);
  return UpgradeButtonView(
    label: switch (t) {
      UpgradeTrack.speed => 'Speed',
      UpgradeTrack.efficiency => 'Efficiency',
      UpgradeTrack.capacity => 'Capacity',
    },
    cost: formatNumber(cost),
    affordable: ctx.owned && maxed == null && ctx.credits >= cost,
    maxedReason: maxed,
    payback: ctx.owned && maxed == null
        ? paybackText(ctx.preview?.call(b.id, t))
        : null,
  );
}

/// An upgrade button's payback line from preview [p]: "pays back in 8m",
/// or, when the level gains nothing because something else holds the
/// building, "no gain now: its inputs or crew hold it"; null otherwise
/// (no preview, or a level whose gain is not output, such as a
/// warehouse's storage).
String? paybackText(UpgradePreview? p) => switch (p) {
  null => null,
  UpgradePreview(paybackSeconds: final s?) =>
    'pays back in ${formatDuration(s)}',
  UpgradePreview(limitedElsewhere: true) =>
    'no gain now: its inputs or crew hold it',
  _ => null,
};
