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

/// Current price per unit of [resourceId]: base price × saturation.
BigNum price(GameState s, Content c, String resourceId) => c
    .resources[resourceId]!
    .basePrice
    .mulDouble(s.market.saturation[resourceId] ?? 1);

/// Sells up to [amount] of [resourceId] from [bodyId]'s stock for
/// [factionId].
///
/// Each unit sold lowers the saturation by `1 / marketDepth`, down to the
/// market floor, and earns the price at the saturation it sold at. Revenue
/// is that price integrated over the sale: while the saturation falls from
/// `s0` to `s1` above the floor, `basePrice × marketDepth × (s0² − s1²) / 2`
/// (the units sold times the average of the two prices), and every unit
/// past the floor earns `basePrice × marketFloor`. So one large sale earns
/// what the same units sold in many small lots would.
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
  final floor = c.rules.marketFloor;
  final s0 = s.market.saturation[resourceId] ?? 1;
  final depth = res.marketDepth;
  // Units that take the saturation from s0 down to the floor.
  final toFloor = depth * math.max(0.0, s0 - floor);
  final BigNum revenue;
  final double s1;
  if (sold.toDouble() <= toFloor) {
    s1 = s0 - sold.toDouble() / depth;
    revenue = (sold * res.basePrice).mulDouble((s0 + s1) / 2);
  } else {
    s1 = math.min(s0, floor);
    final above = BigNum.from(toFloor);
    revenue =
        (above * res.basePrice).mulDouble((s0 + s1) / 2) +
        ((sold - above) * res.basePrice).mulDouble(floor);
  }
  final faction = s.faction(factionId);
  faction.credits = faction.credits + revenue;
  body.stock[resourceId] = held - sold;
  s.market.saturation[resourceId] = math.max(floor, s1);
  return SaleResult(sold: sold, revenue: revenue);
}

/// Recovers every depressed saturation toward 1 by `dt /
/// marketRecoverySeconds`, then runs each faction's auto-sell rules.
///
/// A rule sells what the body holds beyond `keepAtLeast` plus what the
/// body's own buildings would use of the resource in a step of [dt] at
/// full supply ([fullRateFlow]), the two together kept no higher than
/// the body's [storageCap] unless `keepAtLeast` alone is; only while its
/// faction owns the body;
/// revenue goes to that faction. Keeping that step's demand back means
/// auto-selling an input never starves the factories that use it, however
/// long the step. Factions and their rules run in list order. Resources
/// are visited in sorted-id order so recovery does not depend on map
/// insertion order.
void stepMarket(GameState s, Content c, double dt) {
  final sat = s.market.saturation;
  for (final id in sat.keys.toList()..sort()) {
    sat[id] = math.min(1, sat[id]! + dt / c.rules.marketRecoverySeconds);
  }
  final demand = <String, Map<String, BigNum>>{};
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
      final held = body.stock[rule.resourceId] ?? const BigNum.zero();
      // The demand kept never pushes stock past the cap, where the end of
      // the tick would waste it instead.
      final keep = (rule.keepAtLeast + (used[rule.resourceId] ?? _zero)).min(
        rule.keepAtLeast.max(storageCap(s, c, body)),
      );
      final excess = held - keep;
      if (excess > _zero) {
        sell(s, c, f.id, body.id, rule.resourceId, excess);
      }
    }
  }
}

const _zero = BigNum.zero();

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
