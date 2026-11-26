import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'production.dart';

/// Seconds a shipment takes between [a] and [b]:
/// `baseTravelSeconds × (1 + |orbit difference|)`.
///
/// Stage 1 routes stay within one system.
double travelSeconds(GameState s, Content c, BodyState a, BodyState b) =>
    c.rules.baseTravelSeconds * (1 + (a.orbit - b.orbit).abs());

/// Units per second [r]'s cargo ships can carry.
BigNum routeCapacity(Content c, RouteState r) =>
    BigNum.from(r.cargoShips * c.rules.shipCapacityPerSecond);

/// Sends and delivers cargo for [dt] game seconds.
///
/// Sending: each route whose source and destination are both still owned by
/// the route owner moves `min(rate, capacity) × dt`, limited by source
/// stock, into a new [Shipment] arriving at `time + travelSeconds`. Other
/// routes are skipped this step.
///
/// Delivery: shipments with `arriveAt <= time` land in creation order, by
/// [Shipment.toBodyId], whether or not the route still exists. Goods are
/// clamped to the destination's [storageCap], the overflow added to its
/// `wastedThisStep`. If the shipper no longer owns the destination, the
/// goods return to [Shipment.fromBodyId] when the shipper still owns it,
/// else they are lost and counted as waste on the destination. A shipment
/// with no recorded owner (old save) uses its route's owner, else delivers
/// to any owned destination.
///
/// Call after production, which resets `wastedThisStep`, so delivery waste
/// accumulates onto the production waste.
void stepLogistics(GameState s, Content c, double dt) {
  for (final r in s.routes) {
    final from = s.body(r.fromBodyId);
    final to = s.body(r.toBodyId);
    if (from.ownerId != r.ownerId || to.ownerId != r.ownerId) continue;
    final held = from.stock[r.resourceId] ?? const BigNum.zero();
    final rate = r.ratePerSecond.min(routeCapacity(c, r));
    final amount = rate.mulDouble(dt).min(held);
    if (amount <= const BigNum.zero()) continue;
    from.stock[r.resourceId] = held - amount;
    s.shipments.add(
      Shipment(
        routeId: r.id,
        toBodyId: to.id,
        resourceId: r.resourceId,
        amount: amount,
        arriveAt: s.time + travelSeconds(s, c, from, to),
        fromBodyId: from.id,
        ownerId: r.ownerId,
      ),
    );
  }

  final arrived = [
    for (final sh in s.shipments)
      if (sh.arriveAt <= s.time) sh,
  ];
  s.shipments.removeWhere((sh) => sh.arriveAt <= s.time);
  for (final sh in arrived) {
    _deliver(s, c, sh);
  }
}

void _deliver(GameState s, Content c, Shipment sh) {
  final dest = s.body(sh.toBodyId);
  var owner = sh.ownerId;
  if (owner == null) {
    for (final r in s.routes) {
      if (r.id == sh.routeId) owner = r.ownerId;
    }
  }
  final destOk = owner == null ? dest.ownerId != null : dest.ownerId == owner;
  if (destOk) {
    _land(s, c, dest, sh);
    return;
  }
  final src = sh.fromBodyId == null ? null : s.body(sh.fromBodyId!);
  if (src != null && owner != null && src.ownerId == owner) {
    _land(s, c, src, sh);
  } else {
    _waste(dest, sh.resourceId, sh.amount);
  }
}

void _land(GameState s, Content c, BodyState body, Shipment sh) {
  final held = body.stock[sh.resourceId] ?? const BigNum.zero();
  final room = (storageCap(s, c, body) - held).max(const BigNum.zero());
  final taken = sh.amount.min(room);
  body.stock[sh.resourceId] = held + taken;
  _waste(body, sh.resourceId, sh.amount - taken);
}

void _waste(BodyState body, String resourceId, BigNum amount) {
  if (amount <= const BigNum.zero()) return;
  body.wastedThisStep[resourceId] =
      (body.wastedThisStep[resourceId] ?? const BigNum.zero()) + amount;
}
