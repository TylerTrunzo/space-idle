import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';

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
/// [factionId], at the price before the sale, then lowers the saturation by
/// `sold / marketDepth`, down to the market floor.
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
  final revenue = sold * price(s, c, resourceId);
  final faction = s.faction(factionId);
  faction.credits = faction.credits + revenue;
  body.stock[resourceId] = held - sold;
  final saturation = s.market.saturation[resourceId] ?? 1;
  final depth = c.resources[resourceId]!.marketDepth;
  s.market.saturation[resourceId] = math.max(
    c.rules.marketFloor,
    saturation - sold.toDouble() / depth,
  );
  return SaleResult(sold: sold, revenue: revenue);
}

/// Recovers every depressed saturation toward 1 by `dt /
/// marketRecoverySeconds`, then runs each faction's auto-sell rules.
///
/// A rule sells `stock - keepAtLeast` when positive, only while its
/// faction owns the body; revenue goes to that faction. Factions and their
/// rules run in list order. Resources are visited in sorted-id order so
/// recovery does not depend on map insertion order.
void stepMarket(GameState s, Content c, double dt) {
  final sat = s.market.saturation;
  for (final id in sat.keys.toList()..sort()) {
    sat[id] = math.min(1, sat[id]! + dt / c.rules.marketRecoverySeconds);
  }
  for (final f in s.factions) {
    for (final rule in f.autoSell) {
      final body = s.body(rule.bodyId);
      if (body.ownerId != f.id) continue;
      final held = body.stock[rule.resourceId] ?? const BigNum.zero();
      final excess = held - rule.keepAtLeast;
      if (excess > const BigNum.zero()) {
        sell(s, c, f.id, body.id, rule.resourceId, excess);
      }
    }
  }
}
