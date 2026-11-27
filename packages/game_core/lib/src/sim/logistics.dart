import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'crew.dart';
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

/// Lands, as a tick ends at `s.time`, what is due by then and fits: each
/// shipment with `arriveAt <= time` whose shipper still owns its
/// destination, in creation order, up to the room left below the
/// destination's [storageCap]. A shipment that fits lands whole and
/// leaves [GameState.shipments]; one that does not keeps the rest, which
/// lands at the start of the next tick ([deliverShipments]), before its
/// buildings run.
///
/// So goods are usable at the arrival time a command reported, even
/// when a tick ends exactly then, while cargo that would pass the cap
/// still reaches the next tick's buildings before the cap cuts it, as it
/// always did: what lands here is below the cap and is never wasted or
/// kept above it ([stockOverCap]).
void landArrivals(GameState s, Content c) {
  final caps = <String, BigNum>{};
  for (final sh in s.shipments) {
    if (sh.arriveAt > s.time) continue;
    final dest = s.body(sh.toBodyId);
    if (dest.ownerId != sh.ownerId) continue;
    final held = dest.stock[sh.resourceId] ?? const BigNum.zero();
    final room = (caps[dest.id] ??= storageCap(s, c, dest)) - held;
    if (room <= const BigNum.zero()) continue;
    final amount = sh.amount.min(room);
    dest.stock[sh.resourceId] = held + amount;
    sh.amount = sh.amount - amount;
  }
  s.shipments.removeWhere(
    (sh) => sh.arriveAt <= s.time && sh.amount <= const BigNum.zero(),
  );
}

/// Units of route [r]'s resource still in flight on its shipments.
BigNum routeInFlight(GameState s, RouteState r) {
  var total = const BigNum.zero();
  for (final sh in s.shipments) {
    if (sh.routeId == r.id) total = total + sh.amount;
  }
  return total;
}

/// Units of its resource route [r]'s destination uses while a lot is on
/// its way: what the destination's buildings use of it a second at full
/// supply ([fullRateFlow], its owner's crew efficiency) times the route's
/// [travelSeconds].
BigNum routeUseInTransit(GameState s, Content c, RouteState r) {
  final to = s.body(r.toBodyId);
  final owner = to.ownerId;
  if (owner == null) return const BigNum.zero();
  final use = _fullRateUse(c, to, 1, crewEfficiency(s, c, owner));
  final perSecond = use[r.resourceId] ?? const BigNum.zero();
  return perSecond.mulDouble(travelSeconds(s, c, s.body(r.fromBodyId), to));
}

/// Units route [r] may still send before its destination would hold its
/// [RouteState.stopAtDestination] once what is on its way lands: that
/// level less what the destination holds, less the route's cargo in
/// flight ([routeInFlight]) beyond what the destination uses while it
/// travels ([routeUseInTransit]); null for a route with no stop level.
///
/// So the stop level is the stock the destination keeps, not a cap on the
/// destination plus the cargo on its way: a route whose rate times its
/// travel time passes its stop level keeps enough in flight to cover the
/// trip and the destination supplied, instead of sending one stop
/// level's worth per trip and leaving it dry between lots. Cargo in
/// flight still counts once it is more than the trip uses, so the
/// destination does not end up holding a trip's worth above its level.
BigNum? routeRoomBeforeStop(GameState s, Content c, RouteState r) {
  final stop = r.stopAtDestination;
  if (stop == null) return null;
  final held = s.body(r.toBodyId).stock[r.resourceId] ?? const BigNum.zero();
  return stop + routeUseInTransit(s, c, r) - held - routeInFlight(s, r);
}

/// Whether route [r] is paused: its destination, with what is on its way
/// less what it uses before that lands, holds its stop level
/// ([routeRoomBeforeStop]); never for a route with no stop level.
bool routePaused(GameState s, Content c, RouteState r) {
  final room = routeRoomBeforeStop(s, c, r);
  return room != null && room <= const BigNum.zero();
}

/// Sends cargo along every route for [dt] game seconds.
///
/// Each route whose source and destination are both still owned by the
/// route owner moves `min(rate, capacity) × dt`, limited by source stock
/// and, for a route with a stop level, by [routeRoomBeforeStop]; a paused
/// route ([routePaused]) sends nothing until the destination uses some
/// up. So the route restocks its destination as a shop reorders: what is
/// on its way counts, less what will be used before it lands. That runs
/// the same in long steps as in short ones, where a rule on the
/// destination's stock alone pauses and resumes a trip late, by up to a
/// step, and leaves the destination dry between lots.
///
/// The cargo joins the route's newest shipment if that one departed less
/// than [mergeSeconds] (default the rules'
/// [RulesDef.shipmentMergeSeconds]) ago and is still in flight; otherwise
/// it leaves in a new [Shipment] arriving at `time + travelSeconds`.
/// Other routes are skipped this step. Nothing lands here; see
/// [deliverShipments].
///
/// The engine runs this before the market, so what a route sends is off
/// its source's stock before auto-sell works out what it may sell there.
///
/// Returns route id to the units it sent, for the routes that sent any.
Map<String, BigNum> sendCargo(
  GameState s,
  Content c,
  double dt, {
  double? mergeSeconds,
}) {
  final merge = mergeSeconds ?? c.rules.shipmentMergeSeconds;
  final sent = <String, BigNum>{};
  for (final r in s.routes) {
    final from = s.body(r.fromBodyId);
    final to = s.body(r.toBodyId);
    if (from.ownerId != r.ownerId || to.ownerId != r.ownerId) continue;
    final held = from.stock[r.resourceId] ?? const BigNum.zero();
    final rate = r.ratePerSecond.min(routeCapacity(c, r));
    var amount = rate.mulDouble(dt).min(held);
    if (routeRoomBeforeStop(s, c, r) case final room?) {
      amount = amount.min(room);
    }
    if (amount <= const BigNum.zero()) continue;
    from.take(r.resourceId, amount);
    sent[r.id] = amount;
    final newest = _newestOf(s, r.id);
    if (newest != null &&
        s.time - newest.departAt < merge &&
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
  return sent;
}

/// Resource id to what [body]'s buildings use in [seconds] at full
/// supply, its owner's crew working at [crewEff].
Map<String, BigNum> _fullRateUse(
  Content c,
  BodyState body,
  double seconds,
  double crewEff,
) {
  final total = <String, BigNum>{};
  for (final b in body.buildings) {
    final inputs = fullRateFlow(c, body, b, seconds, crewEff).inputs;
    for (final MapEntry(key: id, value: v) in inputs.entries) {
      total[id] = (total[id] ?? const BigNum.zero()) + v;
    }
  }
  return total;
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
