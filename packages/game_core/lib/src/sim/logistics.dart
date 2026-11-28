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
/// That is the destination's target ([routeStopTarget]) less what it holds
/// and all the cargo in flight to it of the resource, on any route. Every
/// route with a stop level bringing the resource to that body shares the
/// target: the largest of their stop levels plus what the destination's
/// buildings use at full supply while a lot of the farthest of them
/// travels, but never more than the destination's storage cap. So the
/// stop level is the stock the destination keeps, not a cap on the
/// destination plus the cargo on its way: a route whose rate times its
/// travel time passes its stop level keeps enough in flight to cover the
/// trip and the destination supplied, instead of sending one stop level's
/// worth per trip and leaving it dry between lots. Timed by the farthest
/// trip, the target covers whichever of the routes ends up sending, so
/// the store is never starved; the price is that while a nearer route
/// does the sending, the store can hold up to the destination's use over
/// the difference between the longest and shortest trips above the stop
/// level. The store plus the cargo on its way never pass the cap, however
/// little of it the buildings there can use, and however many routes bring
/// it: each counts what the others have on the way, so their trips' use is
/// not counted twice. [sendCargo] runs them nearest first, so a farther
/// route only tops up what the nearer ones leave.
BigNum? routeRoomBeforeStop(GameState s, Content c, RouteState r) =>
    _roomBeforeStop(
      s,
      r,
      _stopTargets(s, c, StepCache(s, c)),
      _inFlightTo(s)[_toKey(r.toBodyId, r.resourceId)] ?? const BigNum.zero(),
    );

/// The stock route [r]'s destination keeps of its resource, cargo on its
/// way included, before the routes with a stop level into it pause
/// ([routeRoomBeforeStop]): shared by all of them; null for a route with no
/// stop level.
BigNum? routeStopTarget(GameState s, Content c, RouteState r) {
  if (r.stopAtDestination == null) return null;
  return _stopTargets(s, c, StepCache(s, c))[_toKey(r.toBodyId, r.resourceId)];
}

/// Destination and resource ([_toKey]) to the target every route with a
/// stop level bringing the resource there shares ([routeRoomBeforeStop]):
/// the largest of their stop levels plus what the destination uses while
/// a lot of the farthest of them travels, at most the destination's cap.
Map<String, BigNum> _stopTargets(GameState s, Content c, StepCache cache) {
  final stops = <String, BigNum>{};
  final farthest = <String, (RouteState, double)>{};
  for (final r in s.routes) {
    final stop = r.stopAtDestination;
    if (stop == null) continue;
    final key = _toKey(r.toBodyId, r.resourceId);
    final most = stops[key];
    if (most == null || stop > most) stops[key] = stop;
    final trip = travelSeconds(s, c, s.body(r.fromBodyId), s.body(r.toBodyId));
    final far = farthest[key];
    if (far == null || trip > far.$2) farthest[key] = (r, trip);
  }
  return {
    for (final MapEntry(key: key, value: (r, _)) in farthest.entries)
      key: (stops[key]! + _useInTransit(s, c, r, cache)).min(
        cache.cap(s.body(r.toBodyId)),
      ),
  };
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

/// Whether route [r] is paused: its destination, with what is on its way,
/// holds the target it shares with every stop-level route into it
/// ([routeStopTarget], [routeRoomBeforeStop]); never for a route with no
/// stop level. A farther route into a store a nearer one also feeds may
/// send little while not paused: the nearest sends first.
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
/// others top it up. So the route restocks its destination as a shop
/// reorders: what is on its way counts, less what will be used before it
/// lands. That runs
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

/// What holds a route's throughput back most ([routeThroughput]).
enum RouteLimit {
  /// Its set rate, [RouteState.ratePerSecond].
  rate,

  /// What its cargo ships carry: [RouteState.cargoShips] × the rules'
  /// [RulesDef.shipCapacityPerSecond] ([routeCapacity]).
  ships,

  /// Its destination's storage cap: a route with a stop level keeps its
  /// destination's stock and the cargo on its way to it within the stop
  /// target the routes into the store share ([routeStopTarget]), here the
  /// cap, so it carries at most that target, less the other routes' cargo
  /// in flight there, a trip. The destination's own stock does not count.
  /// More storage there (a warehouse, capacity levels) raises it; so does
  /// a shorter trip.
  destinationRoom,

  /// What its source has to send: what the source makes of the resource
  /// beyond its own buildings' use, the cargo arriving there, and its stock
  /// spread over a full step, less what routes sent earlier take.
  sourceStock,

  /// Its stop level: as [destinationRoom], but the target the stop level
  /// sets ([routeStopTarget]) is below the destination's cap, so raising
  /// the stop level raises it.
  stopLevel,
}

/// What a route could carry a second at most, sustained, and what holds it
/// to that ([routeThroughput]): a capacity ceiling, not what it carries
/// now.
typedef RouteThroughput = ({double perSec, RouteLimit binding});

/// Game seconds over which a source's stock counts as what it has to send
/// ([RouteLimit.sourceStock]): a full step, the engine's catch-up step.
const double _sourceStockSeconds = 60;

/// Units a second route [routeId] could carry at most, sustained, and the
/// limit that binds ([RouteLimit]): a capacity ceiling, not its current
/// flow; see [routeThroughputs]. Throws an [ArgumentError] for a route [s]
/// does not have.
RouteThroughput routeThroughput(GameState s, Content c, String routeId) {
  if (!s.routes.any((r) => r.id == routeId)) {
    throw ArgumentError.value(routeId, 'routeId', 'no such route');
  }
  return routeThroughputs(s, c)[routeId]!;
}

/// Route id to the units a second each route of [s] could carry at most,
/// sustained, and the limit that binds, in list order. It is a capacity
/// ceiling, not what the route carries now: a paused route into a full
/// store that nothing draws from can read a nonzero
/// [RouteLimit.destinationRoom] ceiling while it carries nothing. It is the
/// least of
///
/// - its rate ([RouteLimit.rate]);
/// - its ships times what one carries ([RouteLimit.ships]);
/// - for a route with a stop level, the room its destination keeps for
///   the route's lots over the trip ([travelSeconds]): the target it
///   shares with the other stop-level routes into the store
///   ([routeStopTarget]), less the other routes' cargo on its way there.
///   [RouteLimit.stopLevel] when that target is below the destination's
///   storage cap, else [RouteLimit.destinationRoom]. So a route 2 minutes
///   from a store whose stop target is 97.7K (its cap) reads 97.7K over
///   120 s, 814 a second, however high its rate. What the store holds now
///   does not count: it swings with where a step ends, as lots land, and a
///   store that holds much is not short of what the route brings. A route
///   with no stop level is never held to its destination's room: it keeps
///   sending, and what passes the cap is wasted, and the report shows a
///   full store;
/// - what its source has to send ([RouteLimit.sourceStock]): what the
///   source's buildings make of the resource beyond what they use, at the
///   run fractions they last settled on, plus the cargo arriving there by
///   route (each route's cargo in flight over its trip) and the source's
///   stock over a full step (60 s), less what the routes from the same
///   source of the resource ahead of it in send order take (as
///   [sendCargo] runs them).
///
/// On a tie the limit listed first binds. A route whose owner no longer
/// owns its source carries nothing ([RouteLimit.sourceStock]); one whose
/// destination it no longer owns likewise ([RouteLimit.destinationRoom]).
///
/// For a single stop-level route into a store, it does not depend on where
/// a step ends: rates, ships, caps, stop targets and what a source makes
/// are fixed over a step, the destination's stock does not count, a
/// source's stock is spread over a full step, and a route's own cargo in
/// flight never counts against it. With several routes into one store,
/// the others' cargo in flight still varies as their lots land, and so
/// does the room it leaves.
Map<String, RouteThroughput> routeThroughputs(GameState s, Content c) {
  final cache = StepCache(s, c);
  final inFlight = _inFlightTo(s);
  final targets = _stopTargets(s, c, cache);
  final own = <String, BigNum>{};
  for (final sh in s.shipments) {
    own[sh.routeId] = (own[sh.routeId] ?? const BigNum.zero()) + sh.amount;
  }
  // Source and resource ([_toKey]) to what it has left to send a second.
  final left = <String, double>{};
  final out = <String, RouteThroughput>{};
  for (final r in _sendOrder(s, c)) {
    final from = s.body(r.fromBodyId);
    final to = s.body(r.toBodyId);
    if (from.ownerId != r.ownerId) {
      out[r.id] = (perSec: 0, binding: RouteLimit.sourceStock);
      continue;
    }
    if (to.ownerId != r.ownerId) {
      out[r.id] = (perSec: 0, binding: RouteLimit.destinationRoom);
      continue;
    }
    final trip = travelSeconds(s, c, from, to);
    var best = (perSec: r.ratePerSecond.toDouble(), binding: RouteLimit.rate);
    void consider(double perSec, RouteLimit binding) {
      if (perSec < best.perSec) best = (perSec: perSec, binding: binding);
    }

    consider(routeCapacity(c, r).toDouble(), RouteLimit.ships);
    final key = _toKey(to.id, r.resourceId);
    if (r.stopAtDestination != null) {
      final target = targets[key]!;
      final others =
          (inFlight[key] ?? const BigNum.zero()) -
          (own[r.id] ?? const BigNum.zero());
      final room = (target - others).toDouble();
      consider(
        room > 0 ? room / trip : 0,
        target < cache.cap(to)
            ? RouteLimit.stopLevel
            : RouteLimit.destinationRoom,
      );
    }
    final source = _toKey(from.id, r.resourceId);
    final has = left[source] ??= _toSend(s, c, from, r.resourceId, cache);
    consider(has, RouteLimit.sourceStock);
    left[source] = has - best.perSec > 0 ? has - best.perSec : 0;
    out[r.id] = best;
  }
  return {for (final r in s.routes) r.id: out[r.id]!};
}

/// Units a second [body] has to send of [resourceId]
/// ([RouteLimit.sourceStock]): what its buildings make beyond what they
/// use at their last run fractions, the cargo its owner's routes bring it
/// (each route's cargo in flight over its trip), and its stock over
/// [_sourceStockSeconds].
double _toSend(
  GameState s,
  Content c,
  BodyState body,
  String resourceId,
  StepCache cache,
) {
  final owner = body.ownerId!;
  final eff = cache.crewEff(owner);
  final bonuses = bonusesFor(s, c, owner);
  var net = 0.0;
  for (final b in body.buildings) {
    if (b.lastRunFraction == 0) continue;
    final flow = fullRateFlow(c, body, b, 1, eff, bonuses: bonuses);
    net +=
        ((flow.outputs[resourceId] ?? const BigNum.zero()) -
                (flow.inputs[resourceId] ?? const BigNum.zero()))
            .toDouble() *
        b.lastRunFraction;
  }
  var arriving = 0.0;
  for (final r in s.routes) {
    if (r.toBodyId != body.id ||
        r.resourceId != resourceId ||
        r.ownerId != owner ||
        s.body(r.fromBodyId).ownerId != owner) {
      continue;
    }
    arriving +=
        routeInFlight(s, r).toDouble() /
        travelSeconds(s, c, s.body(r.fromBodyId), body);
  }
  final held = (body.stock[resourceId] ?? const BigNum.zero()).toDouble();
  final made = net > 0 ? net : 0.0;
  return made + arriving + held / _sourceStockSeconds;
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
