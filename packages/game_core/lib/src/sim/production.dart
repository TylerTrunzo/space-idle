import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'crew.dart';
import 'megaprojects.dart';

const _zero = BigNum.zero();

/// Cycle-rate multiplier at speed [level]:
/// `speedPerLevel^level × speedMilestoneMult^(level ~/ speedMilestoneEvery)`.
double speedMultiplier(RulesDef r, int level) =>
    math.pow(r.speedPerLevel, level).toDouble() *
    math.pow(r.speedMilestoneMult, level ~/ r.speedMilestoneEvery).toDouble();

/// Input multiplier at efficiency [level]:
/// `max(efficiencyFloor, efficiencyPerLevel^level)`.
double efficiencyMultiplier(RulesDef r, int level) => math.max(
  r.efficiencyFloor,
  math.pow(r.efficiencyPerLevel, level).toDouble(),
);

/// Whether a [def] building runs its recipe with no crew at all: a
/// habitat with no crew slots, which runs at the share of its inputs that
/// stock supplies, whatever the crew situation.
bool runsWithoutCrew(BuildingDef def) =>
    def.kind == BuildingKind.habitat && def.crewSlots == 0;

/// Whether a [def] building runs a recipe: it has crew slots or
/// [runsWithoutCrew]. Warehouses do not.
bool runsRecipe(BuildingDef def) =>
    (def.crewSlots > 0 && def.kind != BuildingKind.warehouse) ||
    runsWithoutCrew(def);

/// Units of each resource body [b] can store.
///
/// `baseStorageCap × (1 + Σ warehouse storageBonus)
/// × (1 + capacityStoragePerLevel × Σ capacity levels)
/// × storageMultiplier`, both sums over the buildings on [b]; the last is
/// its owner's megaproject bonus ([bonusesFor]), 1 for an unowned body.
/// Warehouse `storageBonus` is a fraction of the base cap.
BigNum storageCap(GameState s, Content c, BodyState b) {
  final r = c.rules;
  var bonus = 0.0;
  var capacityLevels = 0;
  for (final bs in b.buildings) {
    final def = c.buildings[bs.defId]!;
    if (def.kind == BuildingKind.warehouse) bonus += def.storageBonus;
    capacityLevels += bs.levels[UpgradeTrack.capacity]!;
  }
  return BigNum.from(
    r.baseStorageCap *
        (1 + bonus) *
        (1 + r.capacityStoragePerLevel * capacityLevels) *
        bonusesFor(s, c, b.ownerId).storageMultiplier,
  );
}

/// Runs every building on every owned body for [dt] game seconds.
///
/// Factions run in list order, each one's bodies in list order. On each
/// body, habitats are planned first: life support has first claim on its
/// inputs. Their demand is held back from the stock as it comes in, so no
/// other building takes food, water or oxygen a habitat needs; but they
/// claim only the share they can use, so a habitat short of one input
/// does not sit on another that would have made it ([_runBody]). The
/// other buildings then run in groups by [recipeDepth], lowest first,
/// list order within a group: each group's input demand is summed per
/// resource and shared out in proportion from the body's stock less what
/// the habitats claimed, so no stock goes negative, and its outputs are
/// added before the next group plans its inputs. The habitats run last,
/// on everything the body holds, so they use what the body made of their
/// inputs in the same step. So a chain on one body moves its goods from
/// extractor to final product within a step, whatever the step's length.
/// Outputs are added in full, even past the body's [storageCap]: the
/// engine ships and auto-sells first and clamps to the cap at the end of
/// the tick ([clampStorage]), so a long step loses no more to the cap
/// than many short ones. Each building's [BuildingState.lastRunFraction]
/// and [BuildingState.lastLimitReason] are updated: the limit is
/// `noCrew`, `input:<resourceId>` for the input that ran shortest,
/// `understaffed` for a fully supplied building with crew below its base
/// slots, or null. What each body makes is added to its owner's
/// [FactionState.lifetimeProduced].
///
/// Every building's output is scaled by its owner's
/// [EmpireBonuses.outputMultiplier], and its crew work at the faction's
/// crew efficiency for the step: the share of its crew that the step's own
/// habitat run fractions house, so [crewEfficiency] read after the step
/// is the one it ran at ([_stepFaction]). Habitats with no crew slots run
/// at full rate whatever the crew ([runsWithoutCrew]); other buildings
/// with no crew slots (warehouses) and unowned bodies run nothing.
void stepProduction(GameState s, Content c, double dt) {
  for (final f in s.factions) {
    final bodies = [
      for (final b in s.bodies)
        if (b.ownerId == f.id) b,
    ];
    if (bodies.isNotEmpty) _stepFaction(s, c, f, bodies, dt);
  }
}

/// Crew efficiencies [_stepFaction] tells apart.
const double _crewTolerance = 1e-9;

/// Steps [_stepFaction] tries at most after the first.
const int _maxCrewPasses = 12;

/// Runs [f]'s buildings on its owned [bodies] for [dt] game seconds at
/// the crew efficiency the step's own housing gives.
///
/// Housing and crew work on each other: habitats house the crew, and the
/// crew make the habitats' inputs, or take what the habitats' inputs are
/// made from. Read from the step before, the crew efficiency can swing
/// housing every step. So the step is first run at [crewEfficiency] (the
/// last step's housing); if its own habitats then house a different share
/// of the crew, it is run again at efficiencies between the two until
/// they agree, within [_crewTolerance], and that run is kept: a fixed-point
/// step while the two move the same way, false position (Illinois) once
/// they bracket the answer.
void _stepFaction(
  GameState s,
  Content c,
  FactionState f,
  List<BodyState> bodies,
  double dt,
) {
  final bonuses = bonusesFor(s, c, f.id);
  var assigned = 0;
  for (final body in bodies) {
    for (final b in body.buildings) {
      assigned += b.crew;
    }
  }
  List<_BodyRun> run(double crewEff) => [
    for (final body in bodies) _runBody(c, body, dt, crewEff, bonuses),
  ];
  // How far the share of crew a run's habitats house is off [crewEff].
  double gap(List<_BodyRun> runs, double crewEff) {
    var housing = 0.0;
    for (final r in runs) {
      housing += r.housing(c.rules);
    }
    return crewShare(
          f.baseCrew + housing * bonuses.housingMultiplier,
          assigned,
        ) -
        crewEff;
  }

  var e = crewEfficiency(s, c, f.id);
  var runs = run(e);
  var fe = gap(runs, e);
  // The other end of a bracket, once there is one.
  double? a;
  double? fa;
  for (var i = 0; i < _maxCrewPasses && fe.abs() > _crewTolerance; i++) {
    final next = a == null || fa == null || fa == fe
        ? e + fe
        : e - fe * (e - a) / (fe - fa);
    final nextRuns = run(next);
    final fn = gap(nextRuns, next);
    if (a != null && fa != null && fn.sign == fe.sign) {
      fa /= 2;
    } else if (fn.sign != fe.sign) {
      (a, fa) = (e, fe);
    }
    (e, fe, runs) = (next, fn, nextRuns);
  }
  for (final r in runs) {
    r.commit(f.lifetimeProduced);
  }
}

/// Stock already above its body's [storageCap], by body id then resource
/// id; [clampStorage] keeps it.
///
/// Taken at the start of a tick, before anything is made, so stock left
/// above a lowered cap (a demolished warehouse) is not cut, only new
/// additions to it.
Map<String, Map<String, BigNum>> stockOverCap(GameState s, Content c) {
  final over = <String, Map<String, BigNum>>{};
  for (final body in s.bodies) {
    final cap = storageCap(s, c, body);
    for (final MapEntry(key: id, value: v) in body.stock.entries) {
      if (v > cap) (over[body.id] ??= {})[id] = v;
    }
  }
  return over;
}

/// Cuts every body's stock down to its [storageCap], adding what is cut to
/// [BodyState.wastedThisStep]; stock listed in [kept] (see [stockOverCap])
/// is cut no lower than its listed amount.
///
/// The engine calls this at the end of each tick, after production,
/// logistics and auto-sell, so it is the one place stock meets the cap.
void clampStorage(
  GameState s,
  Content c,
  Map<String, Map<String, BigNum>> kept,
) {
  for (final body in s.bodies) {
    final cap = storageCap(s, c, body);
    final keep = kept[body.id];
    for (final MapEntry(key: id, value: v) in body.stock.entries) {
      final limit = keep?[id]?.max(cap) ?? cap;
      if (v <= limit) continue;
      body.stock[id] = limit;
      body.wastedThisStep[id] =
          (body.wastedThisStep[id] ?? _zero) + (v - limit);
    }
  }
}

/// Inputs and outputs of one building over a step at full input supply.
typedef BuildingFlow = ({
  Map<String, BigNum> inputs,
  Map<String, BigNum> outputs,
});

/// What building [b] on [body] would take and make in [dt] game seconds if
/// every input were fully supplied, with its faction working at [crewEff]
/// and its outputs scaled by [bonuses]' [EmpireBonuses.outputMultiplier]
/// (pass the owner's [bonusesFor]; none by default).
///
/// [stepProduction] scales both maps by the run fraction it settles on, so
/// `amount × lastRunFraction` is what the building actually moved. Inputs
/// are listed for every recipe input (zero when unstaffed); an extractor's
/// only output is its deposit's resource, scaled by richness, and it makes
/// nothing when that deposit is missing. A habitat's inputs scale with its
/// capacity levels as its housing does ([habitatCapacityScale]). A
/// habitat with no crew slots runs at full rate, ignoring [crewEff]; other
/// buildings that do not [runsRecipe] (warehouses) take and make nothing.
BuildingFlow fullRateFlow(
  Content c,
  BodyState body,
  BuildingState b,
  double dt,
  double crewEff, {
  EmpireBonuses bonuses = EmpireBonuses.none,
}) {
  final r = c.rules;
  final def = c.buildings[b.defId]!;
  if (!runsRecipe(def)) return (inputs: const {}, outputs: const {});
  // Crew fraction uses base slots, so crew in capacity-upgrade slots pushes
  // output above 100%. A crewless habitat must not wait on the crew it
  // houses, or a crew shortage would starve it further.
  final crewFrac = runsWithoutCrew(def)
      ? 1.0
      : b.crew / def.crewSlots * crewEff;
  final cycles =
      dt /
      def.cycleSeconds *
      speedMultiplier(r, b.levels[UpgradeTrack.speed]!) *
      crewFrac;
  // A habitat's capacity levels raise its life support with its housing.
  final inputMult =
      efficiencyMultiplier(r, b.levels[UpgradeTrack.efficiency]!) *
      (def.kind == BuildingKind.habitat ? habitatCapacityScale(r, b) : 1);
  final inputs = {
    for (final MapEntry(key: id, value: perCycle) in def.inputs.entries)
      id: BigNum.from(perCycle).mulDouble(inputMult * cycles),
  };
  final outputs = <String, BigNum>{};
  final made = cycles * bonuses.outputMultiplier;
  if (def.kind == BuildingKind.extractor) {
    final id = b.depositResourceId;
    final perCycle = def.outputs[id];
    final deposit = body.deposits.where((d) => d.resourceId == id).firstOrNull;
    if (id != null && perCycle != null && deposit != null) {
      outputs[id] = BigNum.from(perCycle).mulDouble(deposit.richness * made);
    }
  } else {
    for (final MapEntry(key: id, value: perCycle) in def.outputs.entries) {
      outputs[id] = BigNum.from(perCycle).mulDouble(made);
    }
  }
  return (inputs: inputs, outputs: outputs);
}

/// Units of [resourceId] the buildings of [factionId] make a second less
/// what they use, at the run fractions their last tick settled on: the
/// steady rate [FlowReport.netProducedPerSec] reports, read without a
/// trial step. Before the storage cap, cargo and sales. Throws if the
/// faction does not exist.
BigNum netProductionRate(
  GameState s,
  Content c,
  String factionId,
  String resourceId,
) {
  final crewEff = crewEfficiency(s, c, factionId);
  final bonuses = bonusesFor(s, c, factionId);
  var net = const BigNum.zero();
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    for (final b in body.buildings) {
      if (b.lastRunFraction == 0) continue;
      final flow = fullRateFlow(c, body, b, 1, crewEff, bonuses: bonuses);
      net =
          net +
          (flow.outputs[resourceId] ?? const BigNum.zero()).mulDouble(
            b.lastRunFraction,
          ) -
          (flow.inputs[resourceId] ?? const BigNum.zero()).mulDouble(
            b.lastRunFraction,
          );
    }
  }
  return net;
}

/// One building's planned run this step.
final class _Run {
  _Run(this.b, this.flow);

  final BuildingState b;

  /// Inputs and outputs at full input supply.
  final BuildingFlow flow;

  /// Fraction of [flow] actually run in the latest pass.
  double fraction = 0;

  /// Its limit in the latest pass, as [BuildingState.lastLimitReason].
  String? limit;
}

/// One pass of a body's buildings, run on a copy of its stock with the
/// habitats' claim scaled by [share].
final class _Pass {
  _Pass(this.share, this.stock, this.produced, this.runs, this.habitats);

  /// Share of their full-rate inputs the habitats claimed.
  final double share;

  /// The body's stock after the pass.
  final Map<String, BigNum> stock;

  /// Resource id to units made.
  final Map<String, BigNum> produced;

  /// Each building's run fraction and limit, in the body's run order.
  final List<(double, String?)> runs;

  /// The lowest run fraction of a habitat; 1 with no habitats.
  final double habitats;
}

/// Claim shares [_settleShare] tells apart: it stops once the share the
/// habitats can use is known this closely.
const double _shareTolerance = 1e-4;

/// Passes [_settleShare] tries at most after the first.
const int _maxSettlePasses = 12;

/// Runs the buildings on [body] on a copy of its stock, with its owner's
/// crew working at [crewEff], for [_BodyRun.commit] to keep.
///
/// Habitats claim their inputs first, but only as much as they can use:
/// a claim they cannot use (a habitat short of food holding back water
/// the farm needed to make it) would stay in stock to feed the other
/// buildings a step late, and housing would swing every step. So when a
/// habitat runs below full, the step is run again with the claim scaled
/// down to the share the habitats run at ([_settleShare]), and that run
/// is kept.
_BodyRun _runBody(
  Content c,
  BodyState body,
  double dt,
  double crewEff,
  EmpireBonuses bonuses,
) {
  final depth = recipeDepth(c);
  final habitats = <_Run>[];
  final others = <_Run>[];
  for (final b in body.buildings) {
    final def = c.buildings[b.defId]!;
    if (!runsRecipe(def)) continue;
    final run = _Run(
      b,
      fullRateFlow(c, body, b, dt, crewEff, bonuses: bonuses),
    );
    (def.kind == BuildingKind.habitat ? habitats : others).add(run);
  }
  // A stable sort: ties keep list order.
  final order = [for (var i = 0; i < others.length; i++) i]
    ..sort((x, y) {
      final byDepth = depth[others[x].b.defId]!.compareTo(
        depth[others[y].b.defId]!,
      );
      return byDepth != 0 ? byDepth : x.compareTo(y);
    });
  final groups = <List<_Run>>[];
  for (final i in order) {
    final run = others[i];
    if (groups.isEmpty ||
        depth[groups.last.first.b.defId]! != depth[run.b.defId]!) {
      groups.add([]);
    }
    groups.last.add(run);
  }
  final all = [...others, ...habitats];

  _Pass pass(double share) {
    final stock = Map.of(body.stock);
    final made = <String, BigNum>{};
    final low = _runPass(c, stock, habitats, groups, share, made);
    return _Pass(share, stock, made, [
      for (final r in all) (r.fraction, r.limit),
    ], low);
  }

  var kept = pass(1);
  if (kept.habitats < 1) kept = _settleShare(kept, pass);
  return _BodyRun(c, body, [for (final r in all) r.b], kept);
}

/// A run of one body's buildings, not yet kept.
final class _BodyRun {
  _BodyRun(this._c, this.body, this.buildings, this.pass);

  final Content _c;

  /// The body run.
  final BodyState body;

  /// The buildings that ran, in [_Pass.runs] order.
  final List<BuildingState> buildings;

  /// The run itself.
  final _Pass pass;

  /// Crew the body's habitats house at the run fractions of [pass],
  /// before the housing bonus, unrounded.
  double housing(RulesDef r) {
    var total = 0.0;
    for (final (i, b) in buildings.indexed) {
      final def = _c.buildings[b.defId]!;
      if (def.kind != BuildingKind.habitat) continue;
      total += habitatHousing(r, def, b) * pass.runs[i].$1;
    }
    return total;
  }

  /// Keeps the run: the body's stock, each building's run fraction and
  /// limit, and what was made added to [produced].
  void commit(Map<String, BigNum> produced) {
    body.stock
      ..clear()
      ..addAll(pass.stock);
    for (final MapEntry(key: id, value: v) in pass.produced.entries) {
      produced[id] = (produced[id] ?? _zero) + v;
    }
    for (final (i, b) in buildings.indexed) {
      final (fraction, limit) = pass.runs[i];
      b
        ..lastRunFraction = fraction
        ..lastLimitReason = limit;
    }
  }
}

/// The pass at the largest claim share the habitats run at in full, found
/// from [full], the pass at share 1, by trying shares with [pass]: within
/// [_shareTolerance], from below.
///
/// A habitat claiming share `r` runs at `g(r)`; claiming less leaves more
/// for the buildings that make its inputs, so `g` never rises with `r`,
/// and the habitats use all they claim while `g(r) ≥ r`. Shares where
/// they do not tell how far off they are: `g(r) − r` falls with `r`
/// there, in a straight line while one input holds them back and its
/// claim is below its stock. So the search steps to where the secant
/// through the last two of those meets zero, and checks a share just
/// above it; when that check runs in full too, the line was not straight
/// (a claim reached its stock in between), and it halves the bracket
/// until the next pair.
_Pass _settleShare(_Pass full, _Pass Function(double share) pass) {
  // Every share up to what the habitats ran at is usable in full.
  var lo = full.habitats;
  _Pass? atLo;
  var hi = 1.0;
  var (r1, f1) = (1.0, full.habitats - 1);
  double? r2;
  double? f2;
  for (var i = 0; i < _maxSettlePasses && hi - lo > _shareTolerance; i++) {
    var r = (lo + hi) / 2;
    var check = false;
    if (r2 != null && f2 != null && f2 != f1) {
      final secant = r2 - f2 * (r2 - r1) / (f2 - f1);
      if (secant > lo && secant < hi) {
        r = secant;
      } else if (secant <= lo) {
        r = math.min(hi, lo + _shareTolerance / 2);
        check = true;
      }
    }
    final p = pass(r);
    // Float residue aside, it ran at the share it claimed.
    if (p.habitats >= r - 1e-9) {
      lo = r;
      atLo = p;
      if (check) {
        // The older point lies past a bend: wait for a fresh pair.
        (r1, f1) = (r2!, f2!);
        r2 = f2 = null;
      }
    } else {
      hi = r;
      if (r2 != null && f2 != null) (r1, f1) = (r2, f2);
      (r2, f2) = (r, p.habitats - r);
    }
  }
  return atLo ?? pass(lo);
}

/// Runs one pass of a body's buildings on [stock], changing it: the
/// [groups] in order, each after the [habitats] claim [share] of their
/// full-rate inputs from the stock as it comes in, then the habitats on
/// everything left. Adds what is made to [produced] and returns the
/// lowest habitat run fraction, 1 with no habitats.
double _runPass(
  Content c,
  Map<String, BigNum> stock,
  List<_Run> habitats,
  List<List<_Run>> groups,
  double share,
  Map<String, BigNum> produced,
) {
  // What the habitats need, claimed first from the stock as it comes in.
  final need = <String, BigNum>{};
  for (final run in habitats) {
    for (final MapEntry(key: id, value: d) in run.flow.inputs.entries) {
      need[id] = (need[id] ?? _zero) + d.mulDouble(share);
    }
  }
  final reserved = <String, BigNum>{};
  for (final group in groups) {
    for (final MapEntry(key: id, value: d) in need.entries) {
      reserved[id] = (stock[id] ?? _zero).min(d);
    }
    _runGroup(c, stock, group, reserved, produced);
  }
  if (habitats.isEmpty) return 1;
  _runGroup(c, stock, habitats, const {}, produced);
  var low = 1.0;
  for (final run in habitats) {
    low = math.min(low, run.fraction);
  }
  return low;
}

/// Runs [runs] on [stock] less [reserved] (resource id to units held
/// back for habitats): shares each input in proportion to demand, takes
/// the inputs, then adds the outputs to the stock and to [produced]. Sets
/// each run's fraction and limit.
void _runGroup(
  Content c,
  Map<String, BigNum> stock,
  List<_Run> runs,
  Map<String, BigNum> reserved,
  Map<String, BigNum> produced,
) {
  final demand = <String, BigNum>{};
  for (final run in runs) {
    for (final MapEntry(key: id, value: d) in run.flow.inputs.entries) {
      demand[id] = (demand[id] ?? _zero) + d;
    }
  }
  final satisfaction = <String, double>{};
  for (final MapEntry(key: id, value: d) in demand.entries) {
    final free = (stock[id] ?? _zero) - (reserved[id] ?? _zero);
    satisfaction[id] = d.isZero
        ? 1.0
        : free.isNegative || free.isZero
        ? 0.0
        : math.min(1.0, (free / d).toDouble());
  }

  for (final run in runs) {
    var f = 1.0;
    String? limit;
    for (final id in run.flow.inputs.keys) {
      final sat = satisfaction[id]!;
      if (sat < f) {
        f = sat;
        limit = id;
      }
    }
    final b = run.b;
    final def = c.buildings[b.defId]!;
    if (b.crew == 0 && !runsWithoutCrew(def)) {
      run
        ..fraction = 0
        ..limit = 'noCrew';
    } else {
      run
        ..fraction = f
        ..limit = limit != null
            ? 'input:$limit'
            : !runsWithoutCrew(def) && b.crew < def.crewSlots
            ? 'understaffed'
            : null;
    }
  }

  final consumed = <String, BigNum>{};
  for (final run in runs) {
    if (run.fraction == 0) continue;
    for (final MapEntry(key: id, value: d) in run.flow.inputs.entries) {
      consumed[id] = (consumed[id] ?? _zero) + d.mulDouble(run.fraction);
    }
  }
  for (final MapEntry(key: id, value: used) in consumed.entries) {
    final have = stock[id] ?? _zero;
    final left = have - used;
    // Shares sum to at most the stock, so `left` is off zero only by float
    // residue; snap that to exactly zero without hiding a real overdraw.
    final residue = have.mulDouble(1e-12);
    stock[id] = left <= residue && left >= -residue ? _zero : left;
  }

  for (final run in runs) {
    if (run.fraction == 0) continue;
    for (final MapEntry(key: id, value: made) in run.flow.outputs.entries) {
      final amount = made.mulDouble(run.fraction);
      if (amount.isZero) continue;
      stock[id] = (stock[id] ?? _zero) + amount;
      produced[id] = (produced[id] ?? _zero) + amount;
    }
  }
}

/// Building id to its recipe depth in [c]: the order in which
/// [stepProduction] runs buildings on a body.
///
/// Extractors and warehouses are 0; any other building is one more than
/// the deepest of its inputs, where an input is as deep as the deepest
/// building that makes it (0 if none does). So every building runs after
/// everything that can make its inputs. Habitats have a depth too, but
/// [stepProduction] plans them before every group and runs them after. A cycle in the recipe graph is
/// broken by list order: buildings are visited in content order, inputs
/// and their makers too, and an edge back to a building still being
/// visited is left out. In the shipped content the hydrogen furnace
/// (water from hydrogen) and the electrolyzer (hydrogen from water) form
/// such a cycle: the furnace is visited first, so the electrolyzer's edge
/// back to the furnace's water is the one left out, and the electrolyzer
/// runs first, using the furnace's water a step later. Computed once per
/// [Content] and cached.
Map<String, int> recipeDepth(Content c) => _depthCache[c] ??= _depths(c);

final _depthCache = Expando<Map<String, int>>('recipeDepth');

Map<String, int> _depths(Content c) {
  final makers = <String, List<BuildingDef>>{};
  for (final d in c.buildings.values) {
    if (d.kind == BuildingKind.extractor) {
      for (final r in d.extracts) {
        (makers[r] ??= []).add(d);
      }
    } else {
      for (final r in d.outputs.keys) {
        (makers[r] ??= []).add(d);
      }
    }
  }
  final depth = <String, int>{};
  final visiting = <String>{};
  int visit(BuildingDef d) {
    if (depth[d.id] case final known?) return known;
    if (d.kind == BuildingKind.extractor || d.kind == BuildingKind.warehouse) {
      return depth[d.id] = 0;
    }
    visiting.add(d.id);
    var deepest = 0;
    for (final input in d.inputs.keys) {
      for (final m in makers[input] ?? const <BuildingDef>[]) {
        if (visiting.contains(m.id)) continue;
        deepest = math.max(deepest, visit(m));
      }
    }
    visiting.remove(d.id);
    return depth[d.id] = deepest + 1;
  }

  for (final d in c.buildings.values) {
    visit(d);
  }
  return {for (final id in c.buildings.keys) id: depth[id]!};
}
