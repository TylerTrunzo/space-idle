import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';

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

/// Lands every shipment due by now (`arriveAt <= time`), in creation
/// order, by [Shipment.toBodyId], whether or not its route still exists.
///
/// The engine calls this at the start of a tick, before production, so
/// goods that land are used in the same tick and a long tick needs no more
/// storage for them than a short one. If the shipper no longer owns the
/// destination, the goods return to [Shipment.fromBodyId] when the shipper
/// still owns it, else they are lost and counted in the destination's
/// `wastedThisStep`. Landed goods may push stock past the storage cap; the
/// engine clamps it at the end of the tick (see `clampStorage`).
void deliverShipments(GameState s) {
  final arrived = [
    for (final sh in s.shipments)
      if (sh.arriveAt <= s.time) sh,
  ];
  s.shipments.removeWhere((sh) => sh.arriveAt <= s.time);
  for (final sh in arrived) {
    _deliver(s, sh);
  }
}

/// Sends cargo along every route for [dt] game seconds.
///
/// Each route whose source and destination are both still owned by the
/// route owner moves `min(rate, capacity) × dt`, limited by source stock.
/// The cargo joins the route's newest shipment if that one departed less
/// than [mergeSeconds] ago and is still in flight; otherwise it leaves in
/// a new [Shipment] arriving at `time + travelSeconds`. Other routes are
/// skipped this step. Nothing lands here; see [deliverShipments].
void sendCargo(
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
}

/// The shipment route [routeId] sent last, or null if none is in flight.
Shipment? _newestOf(GameState s, String routeId) {
  for (var i = s.shipments.length - 1; i >= 0; i--) {
    if (s.shipments[i].routeId == routeId) return s.shipments[i];
  }
  return null;
}

void _deliver(GameState s, Shipment sh) {
  final dest = s.body(sh.toBodyId);
  if (dest.ownerId == sh.ownerId) {
    _land(dest, sh);
    return;
  }
  final src = s.body(sh.fromBodyId);
  if (src.ownerId == sh.ownerId) {
    _land(src, sh);
  } else {
    _waste(dest, sh.resourceId, sh.amount);
  }
}

void _land(BodyState body, Shipment sh) {
  body.stock[sh.resourceId] =
      (body.stock[sh.resourceId] ?? const BigNum.zero()) + sh.amount;
}

void _waste(BodyState body, String resourceId, BigNum amount) {
  if (amount <= const BigNum.zero()) return;
  body.wastedThisStep[resourceId] =
      (body.wastedThisStep[resourceId] ?? const BigNum.zero()) + amount;
}
