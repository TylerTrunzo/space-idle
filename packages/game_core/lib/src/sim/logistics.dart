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

/// Game seconds within which a route's sends join its newest shipment
/// instead of starting a new one.
///
/// Ticking once a second would otherwise put one shipment per route per
/// second in flight; merged, a route has about one per this many seconds of
/// travel. Merged cargo keeps the shipment's arrival time, so it lands up to
/// this many seconds early.
const double shipmentMergeSeconds = 10;

/// Sends and delivers cargo for [dt] game seconds.
///
/// Sending: each route whose source and destination are both still owned by
/// the route owner moves `min(rate, capacity) × dt`, limited by source
/// stock. The cargo joins the route's newest shipment if that one departed
/// less than [mergeSeconds] ago and is still in flight; otherwise it leaves
/// in a new [Shipment] arriving at `time + travelSeconds`. Other routes are
/// skipped this step.
///
/// Delivery: shipments with `arriveAt <= time` land in creation order, by
/// [Shipment.toBodyId], whether or not the route still exists. If the
/// shipper no longer owns the destination, the goods return to
/// [Shipment.fromBodyId] when the shipper still owns it, else they are lost
/// and counted as waste on the destination. Goods are clamped to the
/// receiving body's [storageCap], the overflow added to its
/// `wastedThisStep`.
///
/// Call after production, which resets `wastedThisStep`, so delivery waste
/// accumulates onto the production waste.
void stepLogistics(
  GameState s,
  Content c,
  double dt, {
  double mergeSeconds = shipmentMergeSeconds,
}) {
  for (final r in s.routes) {
    final from = s.body(r.fromBodyId);
    final to = s.body(r.toBodyId);
    if (from.ownerId != r.ownerId || to.ownerId != r.ownerId) continue;
    final held = from.stock[r.resourceId] ?? const BigNum.zero();
    final rate = r.ratePerSecond.min(routeCapacity(c, r));
    final amount = rate.mulDouble(dt).min(held);
    if (amount <= const BigNum.zero()) continue;
    from.stock[r.resourceId] = held - amount;
    final newest = _newestOf(s, r.id);
    if (newest != null &&
        s.time - newest.departAt < mergeSeconds &&
        newest.arriveAt > s.time) {
      newest.amount = newest.amount + amount;
      continue;
    }
    s.shipments.add(
      Shipment(
        routeId: r.id,
        fromBodyId: from.id,
        toBodyId: to.id,
        ownerId: r.ownerId,
        resourceId: r.resourceId,
        amount: amount,
        departAt: s.time,
        arriveAt: s.time + travelSeconds(s, c, from, to),
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

/// The shipment route [routeId] sent last, or null if none is in flight.
Shipment? _newestOf(GameState s, String routeId) {
  for (var i = s.shipments.length - 1; i >= 0; i--) {
    if (s.shipments[i].routeId == routeId) return s.shipments[i];
  }
  return null;
}

void _deliver(GameState s, Content c, Shipment sh) {
  final dest = s.body(sh.toBodyId);
  if (dest.ownerId == sh.ownerId) {
    _land(s, c, dest, sh);
    return;
  }
  final src = s.body(sh.fromBodyId);
  if (src.ownerId == sh.ownerId) {
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
