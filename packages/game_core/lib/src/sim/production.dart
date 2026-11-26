import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'crew.dart';

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
/// × (1 + capacityStoragePerLevel × Σ capacity levels)`, both sums over the
/// buildings on [b]. Warehouse `storageBonus` is a fraction of the base cap.
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
        (1 + r.capacityStoragePerLevel * capacityLevels),
  );
}

/// Runs every building on every owned body for [dt] game seconds.
///
/// Bodies run in list order. On each body, habitats are planned first:
/// life support has first claim on its inputs. Their full-rate demand is
/// held back from the stock as it comes in, so no other building takes
/// food, water or oxygen a habitat needs. The other buildings then run in
/// groups by [recipeDepth], lowest first, list order within a group: each
/// group's input demand is summed per resource and shared out in
/// proportion from the body's stock less what the habitats claimed, so no
/// stock goes negative, and its outputs are added before the next group
/// plans its inputs. The habitats run last, on everything the body holds,
/// so they use what the body made of their inputs in the same step. So a
/// chain on one body moves its goods from extractor to final product
/// within a step, whatever the step's length. Outputs are added in full,
/// even past the body's
/// [storageCap]: the engine ships and auto-sells first and clamps to the
/// cap at the end of the tick ([clampStorage]), so a long step loses no
/// more to the cap than many short ones. Each building's
/// [BuildingState.lastRunFraction] and [BuildingState.lastLimitReason] are
/// updated; habitat run fractions set next step's [crewEfficiency]. What
/// each body makes is added to its owner's
/// [FactionState.lifetimeProduced].
///
/// Crew efficiency is read once per faction before any body runs, so the
/// result does not depend on body order. Habitats with no crew slots run
/// at full rate whatever the crew ([runsWithoutCrew]); other buildings
/// with no crew slots (warehouses) and unowned bodies run nothing.
void stepProduction(GameState s, Content c, double dt) {
  final crewEff = {
    for (final f in s.factions) f.id: crewEfficiency(s, c, f.id),
  };
  for (final body in s.bodies) {
    final owner = body.ownerId;
    if (owner == null) continue;
    _stepBody(c, body, dt, crewEff[owner]!, s.faction(owner).lifetimeProduced);
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
/// every input were fully supplied, with its faction working at [crewEff].
///
/// [stepProduction] scales both maps by the run fraction it settles on, so
/// `amount × lastRunFraction` is what the building actually moved. Inputs
/// are listed for every recipe input (zero when unstaffed); an extractor's
/// only output is its deposit's resource, scaled by richness, and it makes
/// nothing when that deposit is missing. A habitat with no crew slots runs
/// at full rate, ignoring [crewEff]; other buildings that do not
/// [runsRecipe] (warehouses) take and make nothing.
BuildingFlow fullRateFlow(
  Content c,
  BodyState body,
  BuildingState b,
  double dt,
  double crewEff,
) {
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
  final inputMult = efficiencyMultiplier(r, b.levels[UpgradeTrack.efficiency]!);
  final inputs = {
    for (final MapEntry(key: id, value: perCycle) in def.inputs.entries)
      id: BigNum.from(perCycle).mulDouble(inputMult * cycles),
  };
  final outputs = <String, BigNum>{};
  if (def.kind == BuildingKind.extractor) {
    final id = b.depositResourceId;
    final perCycle = def.outputs[id];
    final deposit = body.deposits.where((d) => d.resourceId == id).firstOrNull;
    if (id != null && perCycle != null && deposit != null) {
      outputs[id] = BigNum.from(perCycle).mulDouble(deposit.richness * cycles);
    }
  } else {
    for (final MapEntry(key: id, value: perCycle) in def.outputs.entries) {
      outputs[id] = BigNum.from(perCycle).mulDouble(cycles);
    }
  }
  return (inputs: inputs, outputs: outputs);
}

/// One building's planned run this step.
final class _Run {
  _Run(this.b, this.flow);

  final BuildingState b;

  /// Inputs and outputs at full input supply.
  final BuildingFlow flow;

  /// Fraction of [flow] actually run; set once satisfaction is known.
  double fraction = 0;
}

/// Runs the buildings on [body], adding what they make to [produced].
void _stepBody(
  Content c,
  BodyState body,
  double dt,
  double crewEff,
  Map<String, BigNum> produced,
) {
  final depth = recipeDepth(c);
  final habitats = <_Run>[];
  final others = <_Run>[];
  for (final b in body.buildings) {
    final def = c.buildings[b.defId]!;
    if (!runsRecipe(def)) continue;
    final run = _Run(b, fullRateFlow(c, body, b, dt, crewEff));
    (def.kind == BuildingKind.habitat ? habitats : others).add(run);
  }
  // What the habitats need, claimed first from the stock as it comes in.
  final need = <String, BigNum>{};
  for (final run in habitats) {
    for (final MapEntry(key: id, value: d) in run.flow.inputs.entries) {
      need[id] = (need[id] ?? _zero) + d;
    }
  }
  final reserved = <String, BigNum>{};
  void claim() {
    for (final MapEntry(key: id, value: d) in need.entries) {
      reserved[id] = (body.stock[id] ?? _zero).min(d);
    }
  }

  // A stable sort: ties keep list order.
  final order = [for (var i = 0; i < others.length; i++) i]
    ..sort((x, y) {
      final byDepth = depth[others[x].b.defId]!.compareTo(
        depth[others[y].b.defId]!,
      );
      return byDepth != 0 ? byDepth : x.compareTo(y);
    });
  var start = 0;
  while (start < order.length) {
    final d = depth[others[order[start]].b.defId]!;
    var end = start;
    while (end < order.length && depth[others[order[end]].b.defId]! == d) {
      end++;
    }
    claim();
    _runGroup(
      c,
      body,
      [for (final i in order.sublist(start, end)) others[i]],
      reserved,
      produced,
    );
    start = end;
  }
  if (habitats.isNotEmpty) _runGroup(c, body, habitats, const {}, produced);
}

/// Runs [runs], buildings on [body], on the stock the body holds now less
/// [reserved] (resource id to units held back for habitats): shares each
/// input in proportion to demand, takes the inputs, then adds the outputs
/// to the stock and to [produced].
void _runGroup(
  Content c,
  BodyState body,
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
    final free = (body.stock[id] ?? _zero) - (reserved[id] ?? _zero);
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
    if (b.crew == 0 && !runsWithoutCrew(c.buildings[b.defId]!)) {
      run.fraction = 0;
      b
        ..lastRunFraction = 0
        ..lastLimitReason = 'noCrew';
    } else {
      run.fraction = f;
      b
        ..lastRunFraction = f
        ..lastLimitReason = limit == null ? null : 'input:$limit';
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
    final have = body.stock[id] ?? _zero;
    final left = have - used;
    // Shares sum to at most the stock, so `left` is off zero only by float
    // residue; snap that to exactly zero without hiding a real overdraw.
    final residue = have.mulDouble(1e-12);
    body.stock[id] = left <= residue && left >= -residue ? _zero : left;
  }

  for (final run in runs) {
    if (run.fraction == 0) continue;
    for (final MapEntry(key: id, value: made) in run.flow.outputs.entries) {
      final amount = made.mulDouble(run.fraction);
      if (amount.isZero) continue;
      body.stock[id] = (body.stock[id] ?? _zero) + amount;
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
/// visited is left out. Computed once per [Content] and cached.
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
