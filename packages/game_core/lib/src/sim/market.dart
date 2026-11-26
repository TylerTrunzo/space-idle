import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'crew.dart';
import 'production.dart';

/// What a sale moved and earned.
final class SaleResult {
  /// Creates a sale result.
  const SaleResult({required this.sold, required this.revenue});

  /// Units taken from stock.
  final BigNum sold;

  /// Credits paid to the seller.
  final BigNum revenue;
}

/// Lowest saturation [resourceId]'s market falls to: its own
/// [ResourceDef.marketFloor], else the rules' [RulesDef.marketFloor].
double marketFloorOf(Content c, String resourceId) =>
    c.resources[resourceId]!.marketFloor ?? c.rules.marketFloor;

/// Current price per unit of [resourceId]: base price × saturation.
BigNum price(GameState s, Content c, String resourceId) => c
    .resources[resourceId]!
    .basePrice
    .mulDouble(s.market.saturation[resourceId] ?? 1);

/// Sells up to [amount] of [resourceId] from [bodyId]'s stock for
/// [factionId], all at once.
///
/// Each unit sold cuts the saturation by `1 / marketDepth` of itself, down
/// to the floor ([marketFloorOf]), and earns the price at the saturation it sold at.
/// So `n` units take the saturation from `s0` to `s0 × e^(−n / depth)` and
/// earn `basePrice × marketDepth × (s0 − s1)`; every unit past the floor
/// earns `basePrice × marketFloor`. One large sale earns what the same
/// units sold in many small lots would.
///
/// Sells only what the body holds. Does no ownership checks; callers
/// validate first (see `SellCommand`). The ids must exist.
SaleResult sell(
  GameState s,
  Content c,
  String factionId,
  String bodyId,
  String resourceId,
  BigNum amount,
) {
  final body = s.body(bodyId);
  final held = body.stock[resourceId] ?? const BigNum.zero();
  final sold = amount.min(held).max(const BigNum.zero());
  if (sold.isZero) {
    return const SaleResult(sold: BigNum.zero(), revenue: BigNum.zero());
  }
  final res = c.resources[resourceId]!;
  final floor = marketFloorOf(c, resourceId);
  final s0 = s.market.saturation[resourceId] ?? 1;
  final depth = res.marketDepth;
  // Units that take the saturation from s0 down to the floor.
  final toFloor = s0 <= floor ? 0.0 : depth * math.log(s0 / floor);
  final BigNum revenue;
  final double s1;
  if (sold.toDouble() <= toFloor) {
    s1 = s0 * math.exp(-sold.toDouble() / depth);
    revenue = res.basePrice.mulDouble(depth * (s0 - s1));
  } else {
    s1 = math.min(s0, floor);
    revenue =
        res.basePrice.mulDouble(depth * (s0 - s1)) +
        (sold - BigNum.from(toFloor)) * res.basePrice.mulDouble(floor);
  }
  _earn(s.faction(factionId), resourceId, revenue);
  body.take(resourceId, sold);
  s.market.saturation[resourceId] = math.max(floor, s1);
  return SaleResult(sold: sold, revenue: revenue);
}

/// Runs [dt] game seconds of the market: saturation recovery and every
/// faction's auto-sell rules.
///
/// A rule sells what the body holds beyond `keepAtLeast` plus what the
/// body's own buildings would use of the resource in a step of [dt] at
/// full supply ([fullRateFlow]), the two together kept no higher than the
/// body's [storageCap] unless `keepAtLeast` alone is; only while its
/// faction owns the body. A rule sees the stock less what earlier rules on
/// the same body and resource queued, so duplicate rules (which saves
/// reject) never sell more than is held. Keeping that step's demand back means
/// auto-selling an input never starves the factories that use it, however
/// long the step.
///
/// Saturation recovers toward 1: its gap to full price shrinks by a
/// factor e every `marketRecoverySeconds`. What is auto-sold of a resource
/// counts as sold at a steady rate over the step while it recovers, each
/// unit cutting the saturation by `1 / marketDepth` of itself as in
/// [sell]; the units earn the base price times the saturation's average
/// over the step ([_sellOverStep]). So a long step earns what many short
/// ones do, and steady selling settles at `1 / (1 + rate ×
/// marketRecoverySeconds / marketDepth)` (or the floor): selling more
/// always earns more, ever less per unit. Every seller of a resource gets
/// the same price per unit. Factions and their rules
/// run in list order; resources are settled in sorted-id order so the
/// result does not depend on map insertion order.
///
/// [limits], when given, caps what auto-sell may sell this step: body id
/// to resource id to units, a missing entry meaning nothing. The flow
/// report uses it to sell only what a step makes (see `buildFlowReport`).
void stepMarket(
  GameState s,
  Content c,
  double dt, {
  Map<String, Map<String, BigNum>>? limits,
}) {
  final sales = <String, List<(FactionState, BodyState, BigNum)>>{};
  final demand = <String, Map<String, BigNum>>{};
  // Body id to resource id to what earlier rules already queued for sale,
  // so a second rule on the same stock never sells it twice.
  final queued = <String, Map<String, BigNum>>{};
  for (final f in s.factions) {
    double? crewEff;
    for (final rule in f.autoSell) {
      final body = s.body(rule.bodyId);
      if (body.ownerId != f.id) continue;
      final used = demand[body.id] ??= _stepDemand(
        c,
        body,
        dt,
        crewEff ??= crewEfficiency(s, c, f.id),
      );
      final taken = queued[body.id] ??= {};
      final held =
          (body.stock[rule.resourceId] ?? _zero) -
          (taken[rule.resourceId] ?? _zero);
      // The demand kept never pushes stock past the cap, where the end of
      // the tick would waste it instead.
      final keep = (rule.keepAtLeast + (used[rule.resourceId] ?? _zero)).min(
        rule.keepAtLeast.max(storageCap(s, c, body)),
      );
      var excess = held - keep;
      if (limits != null) {
        excess = excess.min(
          (limits[body.id]?[rule.resourceId] ?? _zero) -
              (taken[rule.resourceId] ?? _zero),
        );
      }
      if (excess > _zero) {
        (sales[rule.resourceId] ??= []).add((f, body, excess));
        taken[rule.resourceId] = (taken[rule.resourceId] ?? _zero) + excess;
      }
    }
  }
  final sat = s.market.saturation;
  for (final id in {...sat.keys, ...sales.keys}.toList()..sort()) {
    final lots = sales[id];
    if (lots == null) {
      sat[id] =
          1 - (1 - sat[id]!) * math.exp(-dt / c.rules.marketRecoverySeconds);
      continue;
    }
    final total = lots.fold(_zero, (t, lot) => t + lot.$3);
    final (:priceShare, :end) = _sellOverStep(
      c,
      c.resources[id]!,
      sat[id] ?? 1,
      total.toDouble(),
      dt,
    );
    final unitPrice = c.resources[id]!.basePrice.mulDouble(priceShare);
    for (final (f, body, amount) in lots) {
      _earn(f, id, amount * unitPrice);
      body.take(id, amount);
    }
    sat[id] = end;
  }
}

/// Selling [units] of [res] at a steady rate over [dt] seconds from
/// saturation [s0] while the market recovers: the average saturation the
/// units sell at ([priceShare]) and the saturation at the end.
///
/// With recovery rate `r = 1 / marketRecoverySeconds` and sales cutting
/// `b = rate / marketDepth` of the saturation a second, `ds/dt = r(1 − s)
/// − b s`: the saturation moves exponentially, at rate `r + b`, toward
/// `r / (r + b)`, and stops at the floor if that lies below it.
({double priceShare, double end}) _sellOverStep(
  Content c,
  ResourceDef res,
  double s0,
  double units,
  double dt,
) {
  final floor = marketFloorOf(c, res.id);
  final r = 1 / c.rules.marketRecoverySeconds;
  final k = r + units / dt / res.marketDepth;
  final eq = r / k;
  // Average saturation over the first t seconds, and the value at t.
  double average(double t) => eq + (s0 - eq) * (1 - math.exp(-k * t)) / (k * t);
  double at(double t) => eq + (s0 - eq) * math.exp(-k * t);
  if (eq >= floor) return (priceShare: average(dt), end: at(dt));
  if (s0 <= floor) return (priceShare: floor, end: floor);
  // Heading below the floor: it gets there at tf and stays.
  final tf = math.log((s0 - eq) / (floor - eq)) / k;
  if (tf >= dt) return (priceShare: average(dt), end: at(dt));
  final area = (tf > 0 ? average(tf) * tf : 0) + floor * (dt - tf);
  return (priceShare: area / dt, end: floor);
}

const _zero = BigNum.zero();

/// Pays [f] [revenue] for a sale of [resourceId], adding it to the
/// faction's [FactionState.salesRevenue] and
/// [FactionState.lifetimeCredits].
void _earn(FactionState f, String resourceId, BigNum revenue) {
  f.credits = f.credits + revenue;
  f.lifetimeCredits = f.lifetimeCredits + revenue;
  f.salesRevenue[resourceId] = (f.salesRevenue[resourceId] ?? _zero) + revenue;
}

/// Resource id to what [body]'s buildings use in [dt] at full supply.
Map<String, BigNum> _stepDemand(
  Content c,
  BodyState body,
  double dt,
  double crewEff,
) {
  final total = <String, BigNum>{};
  for (final b in body.buildings) {
    final inputs = fullRateFlow(c, body, b, dt, crewEff).inputs;
    for (final MapEntry(key: id, value: v) in inputs.entries) {
      total[id] = (total[id] ?? _zero) + v;
    }
  }
  return total;
}
