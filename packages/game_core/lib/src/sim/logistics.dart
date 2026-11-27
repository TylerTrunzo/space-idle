import 'dart:math' as math;

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

/// Whether route [r] is paused: its destination holds at least its
/// [RouteState.stopAtDestination]; never for a route with no stop level.
///
/// Only the destination's stock counts, not cargo in flight
/// ([routeInFlight]): a route whose rate times its travel time passes its
/// stop level would otherwise send one stop level's worth per trip and
/// leave the destination dry between lots. So the destination may end up
/// above the level by what was in flight when it reached it.
bool routePaused(GameState s, RouteState r) {
  final stop = r.stopAtDestination;
  if (stop == null) return false;
  final held = s.body(r.toBodyId).stock[r.resourceId] ?? const BigNum.zero();
  return held >= stop;
}

/// Sends cargo along every route for [dt] game seconds.
///
/// Each route whose source and destination are both still owned by the
/// route owner moves `min(rate, capacity) × dt`, limited by source stock,
/// unless it is paused: its destination holds its stop level
/// ([routePaused]), so it sends nothing until the destination uses some
/// up. The send is not cut to the room left below the stop: a route sends
/// at its rate while the destination is below the level, as it would over
/// many short steps, so a long step moves what they would.
///
/// The cargo joins the route's newest shipment if that one departed less
/// than [mergeSeconds] (default the rules'
/// [RulesDef.shipmentMergeSeconds]) ago and is still in flight; otherwise
/// it leaves in a new [Shipment] arriving at `time + travelSeconds`. So
/// sends land in lots up to [mergeSeconds] apart, and in a step shorter
/// than that the destination's own use of the resource until the next
/// lot could land (at full supply, over `mergeSeconds − dt`) does not
/// count toward the stop: a lot that just landed and is being used up
/// pauses the route no more in 1 s steps than in 60 s ones, whose stock
/// is read after a whole step's use. Other routes are skipped this step.
/// Nothing lands here; see [deliverShipments].
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
  final ahead = math.max(0.0, merge - dt);
  final sent = <String, BigNum>{};
  // Body id to what its buildings use over `ahead`, worked out once.
  final use = <String, Map<String, BigNum>>{};
  for (final r in s.routes) {
    final from = s.body(r.fromBodyId);
    final to = s.body(r.toBodyId);
    if (from.ownerId != r.ownerId || to.ownerId != r.ownerId) continue;
    if (r.stopAtDestination case final stop?) {
      final soon = ahead == 0
          ? const BigNum.zero()
          : (use[to.id] ??= _fullRateUse(
                  c,
                  to,
                  ahead,
                  crewEfficiency(s, c, r.ownerId),
                ))[r.resourceId] ??
                const BigNum.zero();
      final there = to.stock[r.resourceId] ?? const BigNum.zero();
      if (there >= stop + soon) continue;
    }
    final held = from.stock[r.resourceId] ?? const BigNum.zero();
    final rate = r.ratePerSecond.min(routeCapacity(c, r));
    final amount = rate.mulDouble(dt).min(held);
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
