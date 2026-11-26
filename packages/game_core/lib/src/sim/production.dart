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
/// Bodies and their buildings run in list order. On each body, input demand
/// is summed per resource and shared out in proportion, so no stock goes
/// negative; inputs are taken before any output is added, so this step's
/// outputs are not consumed until the next step. Outputs are clamped to the
/// body's [storageCap] and the excess recorded in
/// [BodyState.wastedThisStep]. Each building's
/// [BuildingState.lastRunFraction] and [BuildingState.lastLimitReason] are
/// updated; habitat run fractions set next step's [crewEfficiency].
///
/// Crew efficiency is read once per faction before any body runs, so the
/// result does not depend on body order. Buildings with no crew slots
/// (warehouses) and unowned bodies run nothing.
void stepProduction(GameState s, Content c, double dt) {
  final crewEff = {
    for (final f in s.factions) f.id: crewEfficiency(s, c, f.id),
  };
  for (final body in s.bodies) {
    body.wastedThisStep.clear();
    final owner = body.ownerId;
    if (owner == null) continue;
    _stepBody(c, body, dt, crewEff[owner]!, storageCap(s, c, body));
  }
}

/// One building's planned run this step.
final class _Run {
  _Run(this.b, this.def, this.cycles, this.inputMult);

  final BuildingState b;
  final BuildingDef def;

  /// Potential recipe cycles this step at full input.
  final double cycles;

  /// Efficiency multiplier on inputs.
  final double inputMult;

  /// Fraction of [cycles] actually run; set once satisfaction is known.
  double fraction = 0;

  BigNum demand(String resourceId) =>
      BigNum.from(def.inputs[resourceId]!).mulDouble(inputMult * cycles);
}

void _stepBody(
  Content c,
  BodyState body,
  double dt,
  double crewEff,
  BigNum cap,
) {
  final r = c.rules;
  final runs = <_Run>[];
  for (final b in body.buildings) {
    final def = c.buildings[b.defId]!;
    // Only warehouses have no slots in loaded content; a slot-less building
    // of any other kind (inline content only) runs nothing either.
    if (def.crewSlots == 0) continue;
    // Crew fraction uses base slots, so crew in capacity-upgrade slots pushes
    // output above 100%.
    final crewFrac = b.crew / def.crewSlots * crewEff;
    final cycles =
        dt /
        def.cycleSeconds *
        speedMultiplier(r, b.levels[UpgradeTrack.speed]!) *
        crewFrac;
    runs.add(
      _Run(
        b,
        def,
        cycles,
        efficiencyMultiplier(r, b.levels[UpgradeTrack.efficiency]!),
      ),
    );
  }

  final demand = <String, BigNum>{};
  for (final run in runs) {
    for (final id in run.def.inputs.keys) {
      demand[id] = (demand[id] ?? _zero) + run.demand(id);
    }
  }
  final satisfaction = {
    for (final MapEntry(key: id, value: d) in demand.entries)
      id: d.isZero
          ? 1.0
          : math.min(1.0, ((body.stock[id] ?? _zero) / d).toDouble()),
  };

  for (final run in runs) {
    var f = 1.0;
    String? limit;
    for (final id in run.def.inputs.keys) {
      final sat = satisfaction[id]!;
      if (sat < f) {
        f = sat;
        limit = id;
      }
    }
    final b = run.b;
    if (b.crew == 0) {
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
    for (final id in run.def.inputs.keys) {
      consumed[id] =
          (consumed[id] ?? _zero) + run.demand(id).mulDouble(run.fraction);
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
    final def = run.def;
    if (def.kind == BuildingKind.extractor) {
      final id = run.b.depositResourceId;
      final perCycle = def.outputs[id];
      final deposit = body.deposits
          .where((d) => d.resourceId == id)
          .firstOrNull;
      if (id == null || perCycle == null || deposit == null) continue;
      _store(
        body,
        id,
        BigNum.from(
          perCycle,
        ).mulDouble(deposit.richness * run.cycles * run.fraction),
        cap,
      );
    } else {
      for (final MapEntry(key: id, value: perCycle) in def.outputs.entries) {
        _store(
          body,
          id,
          BigNum.from(perCycle).mulDouble(run.cycles * run.fraction),
          cap,
        );
      }
    }
  }
}

/// Adds [amount] of [id] to [body]'s stock up to [cap], recording the excess
/// as waste. Stock already above the cap is kept, not cut.
void _store(BodyState body, String id, BigNum amount, BigNum cap) {
  if (amount <= _zero) return;
  final have = body.stock[id] ?? _zero;
  final total = have + amount;
  if (total <= cap) {
    body.stock[id] = total;
    return;
  }
  final kept = have.max(cap);
  body.stock[id] = kept;
  body.wastedThisStep[id] = (body.wastedThisStep[id] ?? _zero) + (total - kept);
}
