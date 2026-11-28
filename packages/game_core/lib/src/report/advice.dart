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

const BigNum _zero = BigNum.zero();

/// Paybacks past this many seconds (some 30 million years) read as none:
/// a gain that small is no gain, and the division stays finite.
const double maxPaybackSeconds = 1e15;

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
  /// creditsDeltaPerSec`, worked out in [BigNum]; null when it gains
  /// nothing, or so little it would take over [maxPaybackSeconds].
  final double? paybackSeconds;

  /// Whether it gains nothing because something else holds the building
  /// back with every flow steady: an input, its crew, or the faction's
  /// housing. Set when a speed or efficiency level, or a crewed building's
  /// capacity level, leaves the steady surplus's worth exactly where it
  /// was; never for a habitat's or warehouse's capacity level, whose
  /// housing or storage makes nothing to sell of its own, and never for a
  /// level that loses worth ([creditsDeltaPerSec] negative).
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
/// It is [UpgradePreviewer] for one level; to preview many, use that, or
/// [upgradePreviews], which copy [s] once.
UpgradePreview? upgradePreview(
  GameState s,
  Content c,
  String factionId,
  String buildingId,
  UpgradeTrack track, {
  FlowReport? before,
}) => UpgradePreviewer(
  s,
  c,
  factionId,
  before: before,
).preview(buildingId, track);

/// [UpgradePreviewer.preview] of every level in [levels] (building id and
/// track), in order, from one copy of [s] and one report of it.
List<UpgradePreview?> upgradePreviews(
  GameState s,
  Content c,
  String factionId,
  Iterable<(String, UpgradeTrack)> levels, {
  FlowReport? before,
}) {
  final previewer = UpgradePreviewer(s, c, factionId, before: before);
  return [for (final (id, t) in levels) previewer.preview(id, t)];
}

/// Previews many upgrade levels of one state, each as [upgradePreview]
/// does, for about one flow report each.
///
/// It copies the state once, when made, with the steady surplus of
/// [before] (the report of that state, built when not given); each
/// [preview] runs the level's command on that copy, reports it, and puts
/// back what the command changed (the faction's credits, and the
/// building's level, crew and awaiting-crew flag) before the next. So it
/// stays the state it was made from, whatever the state it was made from
/// does next: [s] can tick on, and the previews stay those of the moment
/// it was made.
final class UpgradePreviewer {
  /// Makes a previewer of [s] for [factionId].
  UpgradePreviewer(GameState s, this._c, this._factionId, {FlowReport? before})
    : _work = s.copy(),
      _base = _surplusOf(before ?? buildFlowReport(s, _c, _factionId), _c);

  final Content _c;
  final String _factionId;

  /// The copy the levels are tried on, put back after each.
  final GameState _work;

  /// Resource id to the steady surplus of the state as it was made.
  final Map<String, BigNum> _base;

  /// What one more level of [track] on [buildingId] would bring; see
  /// [upgradePreview].
  UpgradePreview? preview(String buildingId, UpgradeTrack track) {
    final found = _building(_work, buildingId);
    if (found == null) return null;
    final (_, b) = found;
    final def = _c.buildings[b.defId]!;
    if (!def.upgrades.containsKey(track)) return null;
    final cost = upgradeCost(_c, b, track)[creditsKey] ?? _zero;
    final f = _work.faction(_factionId);
    final credits = f.credits;
    final level = b.levels[track]!;
    final crew = b.crew;
    final awaiting = b.awaitingCrew;
    f.credits = credits + cost;
    try {
      final r = applyCommand(
        _work,
        _c,
        UpgradeCommand(_factionId, buildingId, track),
      );
      if (r is! CommandOk) return null;
      final after = _surplusOf(buildFlowReport(_work, _c, _factionId), _c);
      final (:delta, :worth) = _worthOf(_work, _c, _factionId, _base, after);
      final gains = worth > _zero;
      // Speed and efficiency always raise what the building could make
      // or save; a crewed building's capacity level adds a crew slot.
      // When the surplus's worth does not move, something else holds it:
      // an input, the crew, the housing. A habitat's or warehouse's
      // capacity adds housing or storage, worth no output of its own.
      final raisesOutput = track != UpgradeTrack.capacity || def.crewSlots > 0;
      return UpgradePreview(
        cost: cost,
        outputDeltaPerSec: delta,
        creditsDeltaPerSec: worth,
        paybackSeconds: gains ? _payback(cost, worth) : null,
        limitedElsewhere: worth.isZero && raisesOutput,
      );
    } finally {
      f.credits = credits;
      b.levels[track] = level;
      b.crew = crew;
      b.awaitingCrew = awaiting;
    }
  }
}

/// [cost] ÷ [worth] seconds, in [BigNum] so a late game's figures never
/// overflow; null past [maxPaybackSeconds].
double? _payback(BigNum cost, BigNum worth) {
  final t = (cost / worth).toDouble();
  return t.isFinite && t <= maxPaybackSeconds ? t : null;
}

/// Resource id to [r]'s steady surplus, every resource of [c].
Map<String, BigNum> _surplusOf(FlowReport r, Content c) => {
  for (final id in c.resources.keys) id: r.steadySurplusPerSec(id),
};

/// The change from [before] to [after] (steady surpluses), zero changes
/// left out, and its worth at [factionId]'s sale prices in [s].
({Map<String, BigNum> delta, BigNum worth}) _worthOf(
  GameState s,
  Content c,
  String factionId,
  Map<String, BigNum> before,
  Map<String, BigNum> after,
) {
  final delta = <String, BigNum>{};
  var worth = _zero;
  for (final id in c.resources.keys) {
    final d = (after[id] ?? _zero) - (before[id] ?? _zero);
    if (d.isZero) continue;
    delta[id] = d;
    worth = worth + d * salePrice(s, c, factionId, id);
  }
  return (delta: delta, worth: worth);
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
/// candidate level, on one copy of [s] ([UpgradePreviewer]).
List<UpgradeAdvice> bestUpgrades(
  GameState s,
  Content c,
  String factionId, {
  int limit = 3,
}) {
  if (limit <= 0) return const [];
  final search = BestUpgradeSearch(s, c, factionId);
  while (!search.step()) {}
  return search.result(limit: limit);
}

/// One level [bestUpgrades] weighs: a track of a building on a body.
typedef UpgradeCandidate = ({
  String bodyId,
  String buildingId,
  UpgradeTrack track,
});

/// The levels [bestUpgrades] weighs for [factionId]: every track of every
/// building on its bodies that is not maxed ([upgradeMaxedReason]) and
/// costs no more than its credits, in body, building and track order.
List<UpgradeCandidate> upgradeCandidates(
  GameState s,
  Content c,
  String factionId,
) {
  final credits = s.faction(factionId).credits;
  return [
    for (final body in s.bodies)
      if (body.ownerId == factionId)
        for (final b in body.buildings)
          for (final t in UpgradeTrack.values)
            if (c.buildings[b.defId]!.upgrades.containsKey(t) &&
                upgradeMaxedReason(c, b, t) == null &&
                (upgradeCost(c, b, t)[creditsKey] ?? _zero) <= credits)
              (bodyId: body.id, buildingId: b.id, track: t),
  ];
}

/// [bestUpgrades] a level at a time, for a caller that spreads the work
/// over frames: each [step] previews one candidate ([upgradeCandidates]).
///
/// Nothing is worked out when it is made: the first [step] copies the
/// state as it is then ([UpgradePreviewer]) and lists the candidates from
/// it, so the search is of that moment, however [s] goes on after.
final class BestUpgradeSearch {
  /// Makes a search of [s] for [factionId]; [before], when given, is the
  /// flow report of [s] as the first [step] will find it.
  BestUpgradeSearch(this._s, this._c, this._factionId, {FlowReport? before})
    : _before = before;

  final GameState _s;
  final Content _c;
  final String _factionId;
  final FlowReport? _before;
  UpgradePreviewer? _previewer;
  List<UpgradeCandidate>? _candidates;
  int _next = 0;
  final List<UpgradeAdvice> _found = [];

  /// The game time of the state searched; null before the first [step].
  double? get at => _at;
  double? _at;

  /// Whether every candidate has been previewed.
  bool get done => _candidates != null && _next >= _candidates!.length;

  /// Previews the next candidate (the first call also copies the state
  /// and lists them); true once none is left.
  bool step() {
    final candidates = _candidates ??= () {
      _at = _s.time;
      _previewer = UpgradePreviewer(_s, _c, _factionId, before: _before);
      return upgradeCandidates(_s, _c, _factionId);
    }();
    if (_next >= candidates.length) return true;
    final (:bodyId, :buildingId, :track) = candidates[_next++];
    final p = _previewer!.preview(buildingId, track);
    if (p != null && p.paybackSeconds != null) {
      _found.add(
        UpgradeAdvice(
          bodyId: bodyId,
          buildingId: buildingId,
          track: track,
          preview: p,
        ),
      );
    }
    return _next >= candidates.length;
  }

  /// The [limit] found so far that pay back soonest, soonest first, ties
  /// in candidate order: once [done], [bestUpgrades]' answer.
  List<UpgradeAdvice> result({int limit = 3}) {
    final sorted = List.of(_found);
    _stableSort(
      sorted,
      (x, y) => x.preview.paybackSeconds!.compareTo(y.preview.paybackSeconds!),
    );
    return sorted.take(limit).toList();
  }
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
    final have = id == creditsKey ? f.credits : body.stock[id] ?? _zero;
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
  });

  /// Crew the faction supports now ([CrewTotals.supported]).
  final int housing;

  /// Crew every one of its buildings would take at its most ([maxCrew]),
  /// summed.
  final int demand;

  /// Seconds until its housing falls below the crew assigned, or null
  /// while it holds:
  ///
  /// - 0 when it already has, or will on the next tick: a habitat whose
  ///   next step (the flow report's) runs below its last one, and whose
  ///   lost housing would leave too few, as when a life-support input has
  ///   just run out;
  /// - else the soonest a habitat's life-support input, falling, runs out
  ///   at its rate now, if losing that habitat's housing would leave too
  ///   few.
  ///
  /// The second case takes a habitat that runs dry to lose all its
  /// housing: the engine then runs it at what the input's inflow supports,
  /// so it can warn of a shortage a partial fall would not quite cause. It
  /// errs early, never late.
  final double? secondsUntilShortage;
}

/// [factionId]'s crew forecast: housing, demand and how long until housing
/// falls short. Cheap: it reads [report], the flow report of [s] (built
/// when not given), and builds nothing else, so a caller with the report
/// in hand pays for a pass over the buildings. What a further crew would
/// bring, which costs a report a building, is [extraCrewValue].
CrewForecast crewForecast(
  GameState s,
  Content c,
  String factionId, {
  FlowReport? report,
}) {
  final totals = crewTotals(s, c, factionId);
  var demand = 0;
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    for (final b in body.buildings) {
      demand += maxCrew(c.rules, c.buildings[b.defId]!, b);
    }
  }
  return CrewForecast(
    housing: totals.supported,
    demand: demand,
    secondsUntilShortage: _untilShortage(
      s,
      c,
      factionId,
      totals,
      report ?? buildFlowReport(s, c, factionId),
    ),
  );
}

/// What one more crew is worth to [factionId] a second at most, in
/// credits at sale prices.
///
/// While the faction's housing falls short of its assigned crew, a further
/// crew can work nowhere new (there is no free crew to assign): it houses
/// one already assigned, and is worth what relieving the shortage that
/// much brings. Otherwise it is the best of putting it on each building
/// with room for it, each against the same state with that crew housed
/// but not assigned, so no building is credited with anything but its own
/// gain. Zero when none gains.
///
/// Costly: a flow report for the state with a crew more housed, and one
/// per building with room for crew. Not for a frame; [crewForecast] is the
/// cheap part.
BigNum extraCrewValue(GameState s, Content c, String factionId) {
  final roomy = <String>[
    for (final body in s.bodies)
      if (body.ownerId == factionId)
        for (final b in body.buildings)
          if (b.crew < maxCrew(c.rules, c.buildings[b.defId]!, b)) b.id,
  ];
  return _bestExtraCrew(s, c, factionId, crewTotals(s, c, factionId), roomy);
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
  // Housing that would leave too few for the crew assigned if lost.
  bool tooFewWithout(double lost) =>
      totals.supported - lost.ceil() < totals.assigned;
  double? soonest;
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    final flow = report.bodies.where((f) => f.bodyId == body.id).firstOrNull;
    final next = {
      for (final st in flow?.buildings ?? const <BuildingStatus>[])
        st.buildingId: st.runFraction,
    };
    for (final b in body.buildings) {
      final def = c.buildings[b.defId]!;
      if (def.kind != BuildingKind.habitat) continue;
      final full = habitatHousing(c.rules, def, b) * housingBonus;
      // The next tick: the report's sample step is what it runs.
      final drop = b.lastRunFraction - (next[b.id] ?? b.lastRunFraction);
      if (drop > 1e-9 && tooFewWithout(full * drop)) return 0;
      if (!tooFewWithout(full * b.lastRunFraction)) continue;
      for (final id in def.inputs.keys) {
        final falling = flow?.netPerSec[id] ?? _zero;
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
  CrewTotals totals,
  List<String> roomy,
) {
  final short = totals.overAssigned > 0;
  if (!short && roomy.isEmpty) return _zero;
  // The same state with one more crew housed and none assigned.
  final housed = s.copy();
  housed.faction(factionId).baseCrew += 1;
  final before = _surplusOf(buildFlowReport(housed, c, factionId), c);
  if (short) {
    // It can only house a crew already assigned: worth the relief.
    final now = _surplusOf(buildFlowReport(s, c, factionId), c);
    final (delta: _, :worth) = _worthOf(s, c, factionId, now, before);
    return worth > _zero ? worth : _zero;
  }
  var best = _zero;
  for (final id in roomy) {
    final (_, b) = _building(housed, id)!;
    final copy = housed.copy();
    final r = applyCommand(
      copy,
      c,
      AssignCrewCommand(factionId, id, b.crew + 1),
    );
    if (r is! CommandOk) continue;
    final after = _surplusOf(buildFlowReport(copy, c, factionId), c);
    final (delta: _, :worth) = _worthOf(s, c, factionId, before, after);
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
