import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'megaprojects.dart';
import 'production.dart';
import 'step_cache.dart';

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
/// supply ([fullRateFlow], its owner's crew efficiency, read from
/// [cache]) times the route's [travelSeconds].
BigNum _useInTransit(GameState s, Content c, RouteState r, StepCache cache) {
  final to = s.body(r.toBodyId);
  final perSecond = cache.use(to, 1)[r.resourceId] ?? const BigNum.zero();
  if (perSecond.isZero) return perSecond;
  return perSecond.mulDouble(travelSeconds(s, c, s.body(r.fromBodyId), to));
}

/// Key of the cargo in flight to [bodyId] of [resourceId], every route's
/// and ship move's together.
String _toKey(String bodyId, String resourceId) => '$bodyId/$resourceId';

/// Cargo in flight by destination and resource ([_toKey]).
Map<String, BigNum> _inFlightTo(GameState s) {
  final total = <String, BigNum>{};
  for (final sh in s.shipments) {
    final key = _toKey(sh.toBodyId, sh.resourceId);
    total[key] = (total[key] ?? const BigNum.zero()) + sh.amount;
  }
  return total;
}

/// Units route [r] may still send before its destination would hold its
/// [RouteState.stopAtDestination] once what is on its way lands; null for
/// a route with no stop level.
///
/// That is the destination's target less what it holds and all the cargo
/// in flight to it of the resource, on any route. Every route with a stop
/// level bringing the resource to that body shares one target: the
/// largest of their stop levels plus what the destination's buildings use
/// at full supply while a lot of the farthest of them needed to meet that
/// use travels ([sendCargo] runs them nearest first), but never more than
/// the destination's storage cap. So the stop level is the stock the
/// destination keeps, not a cap on the destination plus the cargo on its
/// way: a route whose rate times its travel time passes its stop level
/// keeps enough in flight to cover the trip and the destination supplied,
/// instead of sending one stop level's worth per trip and leaving it dry
/// between lots. The store plus the cargo on its way never pass the cap,
/// however little of it the buildings there can use, and however many
/// routes bring it: each counts what the others have on the way, so their
/// trips' use is not counted twice; and one route's longer trip never
/// keeps the store above a nearer one's own target, pausing it for good
/// ([sendCargo] lets the nearest send first).
BigNum? routeRoomBeforeStop(GameState s, Content c, RouteState r) =>
    _roomBeforeStop(
      s,
      r,
      _stopTargets(s, c, StepCache(s, c)),
      _inFlightTo(s)[_toKey(r.toBodyId, r.resourceId)] ?? const BigNum.zero(),
    );

/// Destination and resource ([_toKey]) to the target every route with a
/// stop level bringing the resource there shares ([routeRoomBeforeStop]):
/// the largest of their stop levels plus what the destination uses while
/// a lot of the farthest of them it needs travels, at most the
/// destination's cap. Taking the routes whose source holds some of the
/// resource nearest first, as [sendCargo] does, that is the one whose
/// rate brings what they carry together up to what the destination uses
/// a second, each counted at what it can keep sending ([_sustained]);
/// the farthest of them when they never get there, and the nearest of
/// all when no source holds any. So a near route too slow for the demand,
/// or fed by less than it is set to carry, leaves room for the farther
/// ones' longer trips.
Map<String, BigNum> _stopTargets(GameState s, Content c, StepCache cache) {
  final stops = <String, BigNum>{};
  final groups = <String, List<(RouteState, double)>>{};
  for (final r in s.routes) {
    final stop = r.stopAtDestination;
    if (stop == null) continue;
    final key = _toKey(r.toBodyId, r.resourceId);
    final most = stops[key];
    if (most == null || stop > most) stops[key] = stop;
    final trip = travelSeconds(s, c, s.body(r.fromBodyId), s.body(r.toBodyId));
    (groups[key] ??= []).add((r, trip));
  }
  final targets = <String, BigNum>{};
  for (final MapEntry(key: key, value: group) in groups.entries) {
    // A stable sort, nearest first.
    final byTrip = [for (final (i, g) in group.indexed) (i, g)]
      ..sort((x, y) {
        final t = x.$2.$2.compareTo(y.$2.$2);
        return t != 0 ? t : x.$1.compareTo(y.$1);
      });
    final first = byTrip.first.$2.$1;
    final to = s.body(first.toBodyId);
    final use = cache.use(to, 1)[first.resourceId] ?? const BigNum.zero();
    RouteState timedBy = first;
    var carried = const BigNum.zero();
    for (final (_, (r, trip)) in byTrip) {
      final from = s.body(r.fromBodyId);
      final held = from.stock[r.resourceId] ?? const BigNum.zero();
      if (held <= const BigNum.zero()) continue;
      timedBy = r;
      carried = carried + _sustained(s, c, r, held, trip, cache);
      if (carried >= use) break;
    }
    targets[key] = (stops[key]! + _useInTransit(s, c, timedBy, cache)).min(
      cache.cap(to),
    );
  }
  return targets;
}

/// Units a second route [r] can keep sending: its rate, at most its
/// capacity, while its source holds [held] of the resource, at least a
/// trip ([trip] seconds) of that; with less, no more than its source makes
/// of it a second beyond what its buildings use, at their last run
/// fractions. So a route set faster than what feeds it counts at what it
/// carries over time, however short the step that left a little stock.
BigNum _sustained(
  GameState s,
  Content c,
  RouteState r,
  BigNum held,
  double trip,
  StepCache cache,
) {
  final most = r.ratePerSecond.min(routeCapacity(c, r));
  if (held >= most.mulDouble(trip)) return most;
  final from = s.body(r.fromBodyId);
  final owner = from.ownerId;
  if (owner == null) return const BigNum.zero();
  var net = const BigNum.zero();
  for (final b in from.buildings) {
    if (b.lastRunFraction == 0) continue;
    final flow = fullRateFlow(
      c,
      from,
      b,
      1,
      cache.crewEff(owner),
      bonuses: bonusesFor(s, c, owner),
    );
    net =
        net +
        ((flow.outputs[r.resourceId] ?? const BigNum.zero()) -
                (flow.inputs[r.resourceId] ?? const BigNum.zero()))
            .mulDouble(b.lastRunFraction);
  }
  return most.min(net.max(const BigNum.zero()));
}

/// [routeRoomBeforeStop] given the shared [targets] ([_stopTargets]) and
/// [inFlight], all cargo in flight to the destination of the resource.
BigNum? _roomBeforeStop(
  GameState s,
  RouteState r,
  Map<String, BigNum> targets,
  BigNum inFlight,
) {
  if (r.stopAtDestination == null) return null;
  final to = s.body(r.toBodyId);
  final held = to.stock[r.resourceId] ?? const BigNum.zero();
  return targets[_toKey(to.id, r.resourceId)]! - held - inFlight;
}

/// [s]'s routes in the order [sendCargo] runs them: list order, except
/// that the routes with a stop level into one store take the places they
/// hold in the list nearest first ([travelSeconds]), ties in list order.
List<RouteState> _sendOrder(GameState s, Content c) {
  final groups = <String, List<int>>{};
  for (final (i, r) in s.routes.indexed) {
    if (r.stopAtDestination == null) continue;
    (groups[_toKey(r.toBodyId, r.resourceId)] ??= []).add(i);
  }
  if (groups.values.every((g) => g.length < 2)) return s.routes;
  final order = List.of(s.routes);
  for (final slots in groups.values) {
    if (slots.length < 2) continue;
    double trip(int i) {
      final r = s.routes[i];
      return travelSeconds(s, c, s.body(r.fromBodyId), s.body(r.toBodyId));
    }

    final nearest = List.of(slots)
      ..sort((x, y) {
        final byTrip = trip(x).compareTo(trip(y));
        return byTrip != 0 ? byTrip : x.compareTo(y);
      });
    for (final (k, slot) in slots.indexed) {
      order[slot] = s.routes[nearest[k]];
    }
  }
  return order;
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
/// up. Routes run in list order, but those with a stop level into one
/// store nearest first, so the nearest fills the room they share and the
/// others top it up. So the route restocks its destination as a shop reorders: what is
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
///
/// [cache], when given, is the step's [StepCache]; one is made otherwise.
Map<String, BigNum> sendCargo(
  GameState s,
  Content c,
  double dt, {
  double? mergeSeconds,
  StepCache? cache,
}) {
  final merge = mergeSeconds ?? c.rules.shipmentMergeSeconds;
  final sent = <String, BigNum>{};
  // Use at full supply depends on crew and buildings, not stock, so it
  // holds for the whole call.
  final use = cache ?? StepCache(s, c);
  // Kept up to date as routes send, so a route later in the list counts
  // what one earlier sent this step: routes into one store share its room
  // in route order.
  final inFlight = _inFlightTo(s);
  final targets = _stopTargets(s, c, use);
  for (final r in _sendOrder(s, c)) {
    final from = s.body(r.fromBodyId);
    final to = s.body(r.toBodyId);
    if (from.ownerId != r.ownerId || to.ownerId != r.ownerId) continue;
    final held = from.stock[r.resourceId] ?? const BigNum.zero();
    final rate = r.ratePerSecond.min(routeCapacity(c, r));
    var amount = rate.mulDouble(dt).min(held);
    final key = _toKey(to.id, r.resourceId);
    final onWay = inFlight[key] ?? const BigNum.zero();
    if (_roomBeforeStop(s, r, targets, onWay) case final room?) {
      amount = amount.min(room);
    }
    if (amount <= const BigNum.zero()) continue;
    from.take(r.resourceId, amount);
    sent[r.id] = amount;
    inFlight[key] = onWay + amount;
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
