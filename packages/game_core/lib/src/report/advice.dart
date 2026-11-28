import 'dart:math' as math;

import '../commands/apply.dart';
import '../commands/command.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../sim/crew.dart';
import '../sim/market.dart';
import '../sim/megaprojects.dart';
import '../state/game_state.dart';
import 'flow_report.dart';

// Advice for the app: what an upgrade would bring, the best ones to buy,
// what makes a resource, where a building can go, and how the crew holds
// up. Every helper is pure: it reads the state, works on copies, and
// changes nothing. An upgrade's effect is never re-derived here: the real
// command runs on a copy, and the two flow reports are compared.

/// Credits key in costs.
const String _credits = 'credits';

const BigNum _zero = BigNum.zero();

/// What one more level of an upgrade track would bring ([upgradePreview]).
final class UpgradePreview {
  /// Creates a preview.
  UpgradePreview({
    required this.cost,
    required Map<String, BigNum> outputDeltaPerSec,
    required this.creditsDeltaPerSec,
    required this.paybackSeconds,
    required this.limitedElsewhere,
  }) : outputDeltaPerSec = Map.unmodifiable(outputDeltaPerSec);

  /// Credits the level costs.
  final BigNum cost;

  /// Resource id to the change in what the faction has left over a second
  /// with every flow steady ([FlowReport.steadySurplusPerSec]), in content
  /// order, zero changes left out. An input the upgrade saves shows as a
  /// gain; one a faster recipe uses up as a loss.
  final Map<String, BigNum> outputDeltaPerSec;

  /// What [outputDeltaPerSec] is worth a second at the faction's sale
  /// prices now ([salePrice]): its gain in value, whether or not it is
  /// sold. Negative when the level costs more input than it adds output.
  final BigNum creditsDeltaPerSec;

  /// Seconds the gain takes to pay back [cost]: `cost ÷
  /// creditsDeltaPerSec`; null when it gains nothing.
  final double? paybackSeconds;

  /// Whether it gains nothing because something else holds the building
  /// back with every flow steady: an input, its crew, or the faction's
  /// housing. Set when a speed or efficiency level, or a crewed building's
  /// capacity level, leaves the steady surplus no higher; never for a
  /// habitat's or warehouse's capacity level, whose housing or storage
  /// makes nothing to sell of its own.
  final bool limitedElsewhere;
}

/// What one more level of [track] on building [buildingId] would bring
/// [factionId]: its cost, the change in steady surplus it makes, that
/// change's worth at sale prices, and how soon it pays back.
///
/// It runs the real `UpgradeCommand` on a copy of [s] (with the level's
/// credits added, so a level the faction cannot afford yet still
/// previews; its crew fill-up for a capacity level runs as the command
/// does) and compares the copy's flow report with [before], the report
/// of [s] itself, built when not given. Null when the command refuses
/// for anything but the credits: a maxed track, a building the faction
/// does not own, a track its type lacks.
///
/// It builds a flow report for the copy, and one for [s] when [before] is
/// not given, so a caller previewing many levels passes one [before].
UpgradePreview? upgradePreview(
  GameState s,
  Content c,
  String factionId,
  String buildingId,
  UpgradeTrack track, {
  FlowReport? before,
}) {
  final found = _building(s, buildingId);
  if (found == null) return null;
  final (_, b) = found;
  final def = c.buildings[b.defId]!;
  if (!def.upgrades.containsKey(track)) return null;
  final cost = upgradeCost(c, b, track)[_credits] ?? _zero;
  final copy = s.copy();
  final f = copy.faction(factionId);
  f.credits = f.credits + cost;
  final r = applyCommand(copy, c, UpgradeCommand(factionId, buildingId, track));
  if (r is! CommandOk) return null;
  final base = before ?? buildFlowReport(s, c, factionId);
  final after = buildFlowReport(copy, c, factionId);
  final delta = <String, BigNum>{};
  var worth = _zero;
  for (final id in c.resources.keys) {
    final d = after.steadySurplusPerSec(id) - base.steadySurplusPerSec(id);
    if (d.isZero) continue;
    delta[id] = d;
    worth = worth + d * salePrice(s, c, factionId, id);
  }
  final gains = worth > _zero;
  // Speed and efficiency always raise what the building could make or
  // save; a crewed building's capacity level adds a crew slot. When the
  // steady surplus does not rise, something else holds it: an input, the
  // crew, the housing. A habitat's or warehouse's capacity adds housing
  // or storage, worth no output of its own.
  final raisesOutput = track != UpgradeTrack.capacity || def.crewSlots > 0;
  return UpgradePreview(
    cost: cost,
    outputDeltaPerSec: delta,
    creditsDeltaPerSec: worth,
    paybackSeconds: gains ? cost.toDouble() / worth.toDouble() : null,
    limitedElsewhere: !gains && raisesOutput,
  );
}

/// One upgrade worth buying ([bestUpgrades]).
final class UpgradeAdvice {
  /// Creates advice.
  const UpgradeAdvice({
    required this.bodyId,
    required this.buildingId,
    required this.track,
    required this.preview,
  });

  /// Body the building is on.
  final String bodyId;

  /// The building.
  final String buildingId;

  /// The track to raise.
  final UpgradeTrack track;

  /// What the level brings; its [UpgradePreview.paybackSeconds] is set.
  final UpgradePreview preview;
}

/// The [limit] upgrades [factionId] can afford now that pay back soonest:
/// every track of every building on its bodies that is not maxed
/// ([upgradeMaxedReason]) and costs no more than its credits, previewed
/// ([upgradePreview]) against one report of [s], those that gain nothing
/// left out, soonest payback first (ties in body, building and track
/// order).
///
/// It is advice beside `BuyUpgradesCommand`, which buys the cheapest
/// levels; this ranks by what they bring. It builds a flow report per
/// candidate level.
List<UpgradeAdvice> bestUpgrades(
  GameState s,
  Content c,
  String factionId, {
  int limit = 3,
}) {
  if (limit <= 0) return const [];
  final credits = s.faction(factionId).credits;
  final before = buildFlowReport(s, c, factionId);
  final found = <UpgradeAdvice>[];
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    for (final b in body.buildings) {
      final def = c.buildings[b.defId]!;
      for (final t in UpgradeTrack.values) {
        if (!def.upgrades.containsKey(t)) continue;
        if (upgradeMaxedReason(c, b, t) != null) continue;
        if ((upgradeCost(c, b, t)[_credits] ?? _zero) > credits) continue;
        final p = upgradePreview(s, c, factionId, b.id, t, before: before);
        if (p == null || p.paybackSeconds == null) continue;
        found.add(
          UpgradeAdvice(
            bodyId: body.id,
            buildingId: b.id,
            track: t,
            preview: p,
          ),
        );
      }
    }
  }
  // A stable merge sort keeps the order they were found in on a tie.
  _stableSort(
    found,
    (x, y) => x.preview.paybackSeconds!.compareTo(y.preview.paybackSeconds!),
  );
  return found.take(limit).toList();
}

/// Building type ids whose output includes [resourceId]: extractors that
/// mine it and recipes that make it, in content order.
List<String> makersOf(Content c, String resourceId) => [
  for (final d in c.buildings.values)
    if (d.kind == BuildingKind.extractor
        ? d.extracts.contains(resourceId)
        : d.outputs.containsKey(resourceId))
      d.id,
];

/// Why a body cannot take a building now ([hostChecks]).
enum BuildBlockKind {
  /// It has no free build slot.
  noFreeSlot,

  /// It lacks the deposit the extractor would mine.
  noDeposit,

  /// The faction, or the body, holds less of something the build costs.
  short,
}

/// Why a body cannot take a building now, as the build command would
/// refuse it, in the order it checks: a free slot, the deposit, then each
/// cost in the building's cost order.
final class BuildBlock {
  /// Creates a block.
  const BuildBlock(this.kind, {this.resourceId, this.need, this.have});

  /// What blocks it.
  final BuildBlockKind kind;

  /// For [BuildBlockKind.noDeposit], the deposit wanted (null when an
  /// extractor was asked for with none named); for [BuildBlockKind.short],
  /// what is short: `credits`, held by the faction, or a resource, held
  /// on the body.
  final String? resourceId;

  /// For [BuildBlockKind.short], what the build costs of it.
  final BigNum? need;

  /// For [BuildBlockKind.short], what there is of it.
  final BigNum? have;
}

/// One of a faction's bodies as a place for a building, and what blocks
/// it there now; null [block] when it can go there.
typedef HostCheck = ({String bodyId, BuildBlock? block});

/// Each body [factionId] owns, in body order, as a place for building
/// type [defId] now ([BuildBlock]), checked as `BuildCommand` checks it:
/// a free slot ([buildSlots]); for an extractor, [depositResourceId] among
/// what the type mines and among the body's deposits; then each build cost,
/// credits from the faction and goods from the body's stock. Throws an
/// [ArgumentError] for a type [c] does not have.
List<HostCheck> hostChecks(
  GameState s,
  Content c,
  String factionId,
  String defId, {
  String? depositResourceId,
}) {
  final def = c.buildings[defId];
  if (def == null) {
    throw ArgumentError.value(defId, 'defId', 'no such building type');
  }
  final f = s.faction(factionId);
  return [
    for (final body in s.bodies)
      if (body.ownerId == factionId)
        (bodyId: body.id, block: _block(c, f, body, def, depositResourceId)),
  ];
}

/// The bodies [factionId] owns that can take building type [defId] now,
/// in body order: those [hostChecks] finds nothing blocking. For an
/// extractor, [depositResourceId] is the deposit it would mine, as
/// `BuildCommand` takes it.
List<String> hostsFor(
  GameState s,
  Content c,
  String factionId,
  String defId, {
  String? depositResourceId,
}) => [
  for (final h in hostChecks(
    s,
    c,
    factionId,
    defId,
    depositResourceId: depositResourceId,
  ))
    if (h.block == null) h.bodyId,
];

BuildBlock? _block(
  Content c,
  FactionState f,
  BodyState body,
  BuildingDef def,
  String? deposit,
) {
  if (body.buildings.length >= buildSlots(c, body)) {
    return const BuildBlock(BuildBlockKind.noFreeSlot);
  }
  if (def.kind == BuildingKind.extractor &&
      (deposit == null ||
          !def.extracts.contains(deposit) ||
          !body.deposits.any((d) => d.resourceId == deposit))) {
    return BuildBlock(BuildBlockKind.noDeposit, resourceId: deposit);
  }
  for (final MapEntry(key: id, value: need) in def.buildCost.entries) {
    final have = id == _credits ? f.credits : body.stock[id] ?? _zero;
    if (have < need) {
      return BuildBlock(
        BuildBlockKind.short,
        resourceId: id,
        need: need,
        have: have,
      );
    }
  }
  return null;
}

/// How a faction's crew holds up ([crewForecast]).
final class CrewForecast {
  /// Creates a forecast.
  const CrewForecast({
    required this.housing,
    required this.demand,
    required this.secondsUntilShortage,
    required this.creditsPerExtraCrew,
  });

  /// Crew the faction supports now ([CrewTotals.supported]).
  final int housing;

  /// Crew every one of its buildings would take at its most ([maxCrew]),
  /// summed.
  final int demand;

  /// Seconds until its housing falls below the crew assigned: 0 when it
  /// already has; the soonest a habitat's life-support input runs dry, if
  /// housing without that habitat would fall short; null while it holds.
  final double? secondsUntilShortage;

  /// What one more crew is worth a second at most, in credits at sale
  /// prices: the best of putting it on each building with room for it,
  /// each tried on a copy with one more base crew; zero when no building
  /// has room or none gains.
  final BigNum creditsPerExtraCrew;
}

/// [factionId]'s crew forecast: housing, demand, how long until housing
/// falls short, and the best a further crew would bring. It builds a flow
/// report for [s] and one per building with room for a crew.
CrewForecast crewForecast(GameState s, Content c, String factionId) {
  final totals = crewTotals(s, c, factionId);
  final report = buildFlowReport(s, c, factionId);
  var demand = 0;
  final roomy = <String>[];
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    for (final b in body.buildings) {
      final most = maxCrew(c.rules, c.buildings[b.defId]!, b);
      demand += most;
      if (b.crew < most) roomy.add(b.id);
    }
  }
  return CrewForecast(
    housing: totals.supported,
    demand: demand,
    secondsUntilShortage: _untilShortage(s, c, factionId, totals, report),
    creditsPerExtraCrew: _bestExtraCrew(s, c, factionId, roomy, report),
  );
}

double? _untilShortage(
  GameState s,
  Content c,
  String factionId,
  CrewTotals totals,
  FlowReport report,
) {
  if (totals.overAssigned > 0) return 0;
  final housingBonus = bonusesFor(s, c, factionId).housingMultiplier;
  double? soonest;
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    final net = report.bodies
        .where((f) => f.bodyId == body.id)
        .firstOrNull
        ?.netPerSec;
    for (final b in body.buildings) {
      final def = c.buildings[b.defId]!;
      if (def.kind != BuildingKind.habitat) continue;
      final houses =
          habitatHousing(c.rules, def, b) * b.lastRunFraction * housingBonus;
      if (totals.supported - houses.ceil() >= totals.assigned) continue;
      for (final id in def.inputs.keys) {
        final falling = net?[id] ?? _zero;
        if (!falling.isNegative) continue;
        final left = (body.stock[id] ?? _zero).toDouble();
        final t = math.max(0.0, left / -falling.toDouble());
        soonest = soonest == null ? t : math.min(soonest, t);
      }
    }
  }
  return soonest;
}

BigNum _bestExtraCrew(
  GameState s,
  Content c,
  String factionId,
  List<String> roomy,
  FlowReport before,
) {
  var best = _zero;
  for (final id in roomy) {
    final (_, b) = _building(s, id)!;
    final copy = s.copy();
    copy.faction(factionId).baseCrew += 1;
    final r = applyCommand(
      copy,
      c,
      AssignCrewCommand(factionId, id, b.crew + 1),
    );
    if (r is! CommandOk) continue;
    final after = buildFlowReport(copy, c, factionId);
    var worth = _zero;
    for (final res in c.resources.keys) {
      final d =
          after.steadySurplusPerSec(res) - before.steadySurplusPerSec(res);
      if (!d.isZero) worth = worth + d * salePrice(s, c, factionId, res);
    }
    if (worth > best) best = worth;
  }
  return best;
}

(BodyState, BuildingState)? _building(GameState s, String id) {
  for (final body in s.bodies) {
    for (final b in body.buildings) {
      if (b.id == id) return (body, b);
    }
  }
  return null;
}

/// Sorts [list] by [compare], keeping the order of equal elements.
void _stableSort<T>(List<T> list, int Function(T, T) compare) {
  final indexed = [for (final (i, x) in list.indexed) (i, x)];
  indexed.sort((a, b) {
    final by = compare(a.$2, b.$2);
    return by != 0 ? by : a.$1.compareTo(b.$1);
  });
  list
    ..clear()
    ..addAll(indexed.map((e) => e.$2));
}
