import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'economy_fixture.dart';

/// One logistics step in the engine's order: land what is due, then send.
void stepLogistics(GameState s, Content c, double dt, {double? mergeSeconds}) {
  deliverShipments(s);
  sendCargo(s, c, dt, mergeSeconds: mergeSeconds);
}

void main() {
  late Content c;
  late GameState s;
  late BodyState a;
  late BodyState b;

  setUp(() {
    c = economyContent();
    s = newGameState(c, 1);
    a = s.body('a');
    b = s.body('b')..ownerId = 'p';
    a.stock['ore'] = n(1000);
  });

  RouteState route({double rate = 1, int ships = 2}) {
    final r = RouteState(
      id: s.newId('r'),
      ownerId: 'p',
      fromBodyId: 'a',
      toBodyId: 'b',
      resourceId: 'ore',
      ratePerSecond: n(rate),
      cargoShips: ships,
    );
    s.routes.add(r);
    return r;
  }

  BigNum at(BodyState x) => x.stock['ore'] ?? const BigNum.zero();
  BigNum inTransit() =>
      s.shipments.fold(const BigNum.zero(), (sum, sh) => sum + sh.amount);

  /// Runs [seconds] one-second steps, advancing time after each.
  void run(int seconds) {
    for (var i = 0; i < seconds; i++) {
      stepLogistics(s, c, 1);
      s.time += 1;
    }
  }

  test('travel time and capacity formulas', () {
    final r = route();
    expect(travelSeconds(s, c, a, b), 120);
    expect(travelSeconds(s, c, a, s.body('c')), 60);
    expect(routeCapacity(c, r), n(4));
  });

  test('route moves goods after travel time', () {
    route();
    run(20);
    expect(inTransit().toDouble(), closeTo(20, 1e-9));
    expect(at(b).isZero, isTrue);
    expect(at(a).toDouble(), closeTo(980, 1e-9));
    s.routes.clear(); // stop sending; the 20 s of cargo is still in flight
    run(101); // stepped at time 120: the shipment sent at 0 to 9 lands
    expect(at(b).toDouble(), closeTo(10, 1e-9));
    run(10); // time 130: the one sent at 10 to 19 lands too
    expect(at(b).toDouble(), closeTo(20, 1e-9));
    expect(inTransit().isZero, isTrue);
    expect(at(a).toDouble(), closeTo(980, 1e-9));
  });

  test('sends within the merge window join the newest shipment', () {
    route();
    run(25);
    expect([for (final sh in s.shipments) sh.departAt], [0, 10, 20]);
    expect([for (final sh in s.shipments) sh.arriveAt], [120, 130, 140]);
    expect([for (final sh in s.shipments) sh.amount.toDouble()], [10, 10, 5]);
  });

  test('a zero merge window sends one shipment per step', () {
    route();
    for (var i = 0; i < 5; i++) {
      stepLogistics(s, c, 1, mergeSeconds: 0);
      s.time += 1;
    }
    expect(s.shipments, hasLength(5));
  });

  test('merging keeps live ticking small and delivers the same', () {
    // Three routes out of `a`, two of 120 s travel and one of 60 s, ticked
    // once a second for 15 minutes; nothing reaches the storage cap.
    (int, double) play({required double mergeSeconds}) {
      final t = newGameState(c, 1);
      t.body('a').stock['ore'] = n(1e6);
      t.body('b').ownerId = 'p';
      t.body('c').ownerId = 'p';
      for (final (i, to) in ['b', 'c', 'b'].indexed) {
        t.routes.add(
          RouteState(
            id: 'r$i',
            ownerId: 'p',
            fromBodyId: 'a',
            toBodyId: to,
            resourceId: 'ore',
            ratePerSecond: n(0.5),
            cargoShips: 1,
          ),
        );
      }
      var peak = 0;
      for (var i = 0; i < 900; i++) {
        stepLogistics(t, c, 1, mergeSeconds: mergeSeconds);
        t.time += 1;
        if (t.shipments.length > peak) peak = t.shipments.length;
      }
      final landed = t.body('b').stock['ore']! + t.body('c').stock['ore']!;
      return (peak, landed.toDouble());
    }

    final (mergedPeak, merged) = play(
      mergeSeconds: c.rules.shipmentMergeSeconds,
    );
    final (unmergedPeak, unmerged) = play(mergeSeconds: 0);
    // One shipment per route per 10 s of travel: 12 + 6 + 12.
    expect(mergedPeak, lessThanOrEqualTo(30));
    expect(unmergedPeak, greaterThan(200));
    expect(unmerged, greaterThan(1000));
    expect(merged, closeTo(unmerged, unmerged * 0.01));
  });

  test('route limited by capacity', () {
    route(rate: 10, ships: 1);
    run(10);
    expect(inTransit().toDouble(), closeTo(20, 1e-9));
  });

  test('route limited by source stock', () {
    a.stock['ore'] = n(3);
    route(rate: 2);
    run(5);
    expect(inTransit().toDouble(), closeTo(3, 1e-9));
    expect(at(a).isZero, isTrue);
  });

  test('a route sending all the source holds leaves it at exactly zero', () {
    // 10 − 1e-14 equals 10 at BigNum precision, so the send is the full
    // 10 and the source must not go below zero by the difference.
    a.stock['ore'] = BigNum.from(10 - 1e-14);
    s.routes.add(route(rate: 1, ships: 2));
    stepLogistics(s, c, 10);
    expect(a.stock['ore']!.isNegative, isFalse);
  });

  test('route skipped when an end is no longer owned', () {
    route();
    b.ownerId = null;
    run(5);
    expect(s.shipments, isEmpty);
    expect(at(a), n(1000));
  });

  test('delivery may pass the storage cap; the tick clamps it', () {
    b.stock['ore'] = n(995);
    route();
    run(10);
    s.time = 1000;
    stepLogistics(s, c, 0);
    expect(at(b).toDouble(), closeTo(1005, 1e-9));
    expect(b.wastedThisStep, isEmpty);
  });

  test('shipment outlives its route and still delivers', () {
    route();
    run(10);
    s.routes.clear();
    s.time = 500;
    stepLogistics(s, c, 1);
    expect(at(b).toDouble(), closeTo(10, 1e-9));
    expect(s.shipments, isEmpty);
  });

  test('goods return to source when destination is lost', () {
    route();
    run(10);
    b.ownerId = null;
    s.routes.clear();
    s.time = 500;
    stepLogistics(s, c, 1);
    expect(at(b).isZero, isTrue);
    expect(at(a).toDouble(), closeTo(1000, 1e-9));
  });

  test('goods are lost as waste when source is lost too', () {
    route();
    run(10);
    b.ownerId = null;
    a.ownerId = null;
    s.routes.clear();
    s.time = 500;
    stepLogistics(s, c, 1);
    expect(at(b).isZero, isTrue);
    expect(at(a).toDouble(), closeTo(990, 1e-9));
    expect(b.wastedThisStep['ore']!.toDouble(), closeTo(10, 1e-9));
  });

  test('in-transit goods survive save round trip', () {
    route();
    run(10);
    final loaded = (SaveCodec.decode(SaveCodec.encode(s), c) as SaveOk).state;
    expect(loaded.shipments.length, s.shipments.length);
    final sh = loaded.shipments.first;
    expect(sh.fromBodyId, 'a');
    expect(sh.ownerId, 'p');
    expect(sh.departAt, s.shipments.first.departAt);
    expect(sh.arriveAt, s.shipments.first.arriveAt);
    loaded.time = 500;
    stepLogistics(loaded, c, 1);
    expect(at(loaded.body('b')).toDouble(), closeTo(10, 1e-9));
  });

  group('stop at destination', () {
    test('with nothing using it at the destination, cargo in flight counts '
        'in full, so the route never overshoots', () {
      final r = route(rate: 1)..stopAtDestination = n(15);
      expect(routeRoomBeforeStop(s, c, r), n(15));
      run(20);
      // Nothing has landed yet (120 s of travel), and 15 left.
      expect(at(b).isZero, isTrue);
      expect(inTransit().toDouble(), closeTo(15, 1e-9));
      expect(routeInFlight(s, r).toDouble(), closeTo(15, 1e-9));
      expect(routePaused(s, c, r), isTrue);
      run(200);
      expect(at(b).toDouble(), closeTo(15, 1e-9));
      expect(inTransit().isZero, isTrue);
      expect(at(a).toDouble(), closeTo(985, 1e-9));
      expect(routePaused(s, c, r), isTrue);
    });

    test('a paused route resumes when the destination uses some up', () {
      final r = route(rate: 1)..stopAtDestination = n(15);
      b.stock['ore'] = n(20);
      run(5);
      expect(s.shipments, isEmpty);
      b.stock['ore'] = n(12);
      expect(routePaused(s, c, r), isFalse);
      run(10);
      // It sent the 3 short, at its 1 a second, then paused again.
      expect(inTransit().toDouble(), closeTo(3, 1e-9));
      expect(routePaused(s, c, r), isTrue);
    });

    test('cargo in flight counts only beyond what the destination uses '
        'while it travels', () {
      // A press on b using 0.5 ore a second: a 120 s trip uses 60 of what
      // is in flight, so the route keeps 60 more on its way than the stop.
      final r = route(rate: 1)..stopAtDestination = n(15);
      b.buildings.add(BuildingState(id: 'press', defId: 'press', crew: 1));
      final withPress = pressContent();
      expect(routeRoomBeforeStop(s, withPress, r), n(75));
      for (var i = 0; i < 20; i++) {
        sendCargo(s, withPress, 1);
        s.time += 1;
      }
      expect(inTransit().toDouble(), closeTo(20, 1e-9));
      expect(routePaused(s, withPress, r), isFalse);
      expect(
        routeRoomBeforeStop(s, withPress, r)!.toDouble(),
        closeTo(55, 1e-9),
      );
    });

    test('stop-level routes into one store share one target: the highest '
        'stop plus the use over the farther trip, at most the cap', () {
      // Into a, whose press uses 0.5 ore a second: from b (120 s away)
      // stopping at 15, from c (60 s away) stopping at 40.
      final withPress = pressContent();
      final store = s.body('a')
        ..buildings.add(BuildingState(id: 'press', defId: 'press', crew: 1))
        ..stock['ore'] = n(30);
      for (final id in ['b', 'c']) {
        s.body(id)
          ..ownerId = 'p'
          ..stock['ore'] = n(1000);
      }
      RouteState into(String from, double stop) {
        final r = RouteState(
          id: s.newId('r'),
          ownerId: 'p',
          fromBodyId: from,
          toBodyId: 'a',
          resourceId: 'ore',
          ratePerSecond: n(1),
          cargoShips: 2,
          stopAtDestination: n(stop),
        );
        s.routes.add(r);
        return r;
      }

      final far = into('b', 15);
      final near = into('c', 40);
      expect(travelSeconds(s, withPress, s.body('b'), store), 120);
      expect(travelSeconds(s, withPress, s.body('c'), store), 60);
      // 40 + 0.5 × 120, for both.
      for (final r in [far, near]) {
        expect(routeStopTarget(s, withPress, r), n(100));
      }
      // Less what the store holds and all cargo on its way to it.
      s.shipments.add(
        Shipment(
          routeId: far.id,
          fromBodyId: 'b',
          toBodyId: 'a',
          ownerId: 'p',
          resourceId: 'ore',
          amount: n(10),
          departAt: 0,
          arriveAt: 120,
        ),
      );
      for (final r in [far, near]) {
        expect(routeRoomBeforeStop(s, withPress, r), n(60));
      }
      expect(routeStopTarget(s, withPress, route()), isNull);
      // The cap binds: 990 + 60 would pass a's 1000.
      near.stopAtDestination = n(990);
      expect(storageCap(s, withPress, store), n(1000));
      expect(routeStopTarget(s, withPress, far), n(1000));
      expect(routeRoomBeforeStop(s, withPress, near), n(960));
    });

    test('a route without a stop level never pauses', () {
      final r = route(rate: 1);
      b.stock['ore'] = n(900);
      expect(routeRoomBeforeStop(s, c, r), isNull);
      expect(routePaused(s, c, r), isFalse);
      run(5);
      expect(inTransit().toDouble(), closeTo(5, 1e-9));
    });
  });

  group('route throughput', () {
    // a to b is 120 s; a ship carries 2 a second; b stores 1000.
    test('a route with enough ships is held to its rate', () {
      final r = route(rate: 1, ships: 2);
      expect(routeThroughput(s, c, r.id), (
        perSec: 1.0,
        binding: RouteLimit.rate,
      ));
    });

    test('a route with too few ships is held to what they carry', () {
      final r = route(rate: 10, ships: 1);
      expect(routeThroughput(s, c, r.id), (
        perSec: 2.0,
        binding: RouteLimit.ships,
      ));
    });

    test('a source with little stock and nothing made holds it to that '
        'stock over a full step', () {
      a.stock['ore'] = n(30);
      final r = route(rate: 1, ships: 2);
      final t = routeThroughput(s, c, r.id);
      expect(t.binding, RouteLimit.sourceStock);
      expect(t.perSec, closeTo(0.5, 1e-9));
    });

    test('a full destination with a long trip holds a stop-level route to '
        'its room', () {
      final r = route(rate: 10, ships: 10)..stopAtDestination = n(1000);
      // Full or empty, the store takes one cap's worth a trip: 1000 over
      // 120 s.
      b.stock['ore'] = n(1000);
      expect(routeThroughput(s, c, r.id), (
        perSec: 1000 / 120,
        binding: RouteLimit.destinationRoom,
      ));
      b.stock['ore'] = const BigNum.zero();
      final t = routeThroughput(s, c, r.id);
      expect(t.binding, RouteLimit.destinationRoom);
      expect(t.perSec, closeTo(1000 / 120, 1e-9));
      // Its own cargo on the way does not take its room; others' does.
      s.shipments.add(
        Shipment(
          routeId: 'other',
          fromBodyId: 'c',
          toBodyId: 'b',
          ownerId: 'p',
          resourceId: 'ore',
          amount: n(400),
          departAt: 0,
          arriveAt: 60,
        ),
      );
      run(30);
      final u = routeThroughput(s, c, r.id);
      expect(u.binding, RouteLimit.destinationRoom);
      expect(u.perSec, closeTo(600 / 120, 1e-9));
    });

    test('a stop level below the cap binds as the stop level', () {
      final r = route(rate: 10, ships: 10)..stopAtDestination = n(600);
      final t = routeThroughput(s, c, r.id);
      expect(t.binding, RouteLimit.stopLevel);
      expect(t.perSec, closeTo(600 / 120, 1e-9));
    });

    test('a route without a stop level is not held to its room: what '
        'passes the cap is wasted, and shows as a full store', () {
      a.stock['ore'] = n(1e6);
      final r = route(rate: 10, ships: 10);
      b.stock['ore'] = n(1000);
      expect(routeThroughput(s, c, r.id), (
        perSec: 10.0,
        binding: RouteLimit.rate,
      ));
    });

    test("what the destination holds now takes none of a route's room", () {
      // It swings as lots land: a reading by it would hang on where a
      // step ends.
      final withPress = pressContent();
      b.buildings.add(BuildingState(id: 'press', defId: 'press', crew: 1));
      final r = route(rate: 20, ships: 20)..stopAtDestination = n(1000);
      for (final held in [0, 50, 160, 900]) {
        b.stock['ore'] = n(held);
        expect(
          routeThroughput(s, withPress, r.id).perSec,
          closeTo(1000 / 120, 1e-9),
          reason: '$held',
        );
      }
    });

    test('routes from one source share what it has, in send order', () {
      a.stock['ore'] = n(60); // 1 a second over a full step
      final first = route(rate: 0.75, ships: 2);
      final second = route(rate: 0.75, ships: 2);
      expect(routeThroughput(s, c, first.id), (
        perSec: 0.75,
        binding: RouteLimit.rate,
      ));
      final t = routeThroughput(s, c, second.id);
      expect(t.binding, RouteLimit.sourceStock);
      expect(t.perSec, closeTo(0.25, 1e-9));
      expect(routeThroughputs(s, c).keys, [first.id, second.id]);
    });

    test('a route whose end its owner lost carries nothing', () {
      final r = route();
      b.ownerId = null;
      expect(routeThroughput(s, c, r.id), (
        perSec: 0.0,
        binding: RouteLimit.destinationRoom,
      ));
      b.ownerId = 'p';
      a.ownerId = null;
      expect(routeThroughput(s, c, r.id), (
        perSec: 0.0,
        binding: RouteLimit.sourceStock,
      ));
    });

    test('an unknown route is an error', () {
      expect(() => routeThroughput(s, c, 'nope'), throwsArgumentError);
    });

    group('is the same at 1 s and 60 s steps', () {
      // A press on b uses 0.5 ore a second; a holds plenty.
      for (final (name, rate, ships, cap, stop, binding) in [
        ('rate', 0.25, 1, 1000.0, null, RouteLimit.rate),
        ('ships', 5.0, 1, 1000.0, null, RouteLimit.ships),
        // b stores 20: 20 a trip of 120 s for 0.5 a second wanted.
        ('destination room', 5.0, 5, 20.0, 20.0, RouteLimit.destinationRoom),
      ]) {
        test(name, () {
          final withPress = pressContent(baseStorageCap: cap);
          final e = GameEngine(withPress);
          GameState played(double step) {
            final t = e.newGame(1);
            t.body('a').stock['ore'] = n(1e6);
            t.body('b')
              ..ownerId = 'p'
              ..buildings.add(
                BuildingState(id: 'press', defId: 'press', crew: 1),
              );
            t.routes.add(
              RouteState(
                id: 'r1',
                ownerId: 'p',
                fromBodyId: 'a',
                toBodyId: 'b',
                resourceId: 'ore',
                ratePerSecond: n(rate),
                cargoShips: ships,
                stopAtDestination: stop == null ? null : n(stop),
              ),
            );
            e.advance(t, 1200, maxStep: step);
            return t;
          }

          final live = routeThroughput(played(1), withPress, 'r1');
          final away = routeThroughput(played(60), withPress, 'r1');
          expect(live.binding, binding);
          expect(away.binding, binding);
          expect(away.perSec, closeTo(live.perSec, live.perSec * 1e-6));
        });
      }

      test('stop level', () {
        // A stop of 100 below b's 1,000: the target is 100 plus the 60 the
        // press uses over the trip, 160 a trip at most.
        final withPress = pressContent();
        final e = GameEngine(withPress);
        GameState played(double step) {
          final t = e.newGame(1);
          t.body('a').stock['ore'] = n(1e6);
          t.body('b')
            ..ownerId = 'p'
            ..buildings.add(
              BuildingState(id: 'press', defId: 'press', crew: 1),
            );
          t.routes.add(
            RouteState(
              id: 'r1',
              ownerId: 'p',
              fromBodyId: 'a',
              toBodyId: 'b',
              resourceId: 'ore',
              ratePerSecond: n(5),
              cargoShips: 5,
              stopAtDestination: n(100),
            ),
          );
          e.advance(t, 1200, maxStep: step);
          return t;
        }

        final live = routeThroughput(played(1), withPress, 'r1');
        final away = routeThroughput(played(60), withPress, 'r1');
        expect(live.binding, RouteLimit.stopLevel);
        expect(away.binding, RouteLimit.stopLevel);
        expect(live.perSec, lessThanOrEqualTo(160 / 120 + 1e-9));
        expect(away.perSec, closeTo(live.perSec, live.perSec * 1e-6));
      });

      test('source stock', () {
        // A press on a makes 0.5 plate a second, and the route takes all
        // of it for b: what a makes is all it has to send.
        final withPress = pressContent();
        final e = GameEngine(withPress);
        GameState played(double step) {
          final t = e.newGame(1);
          t.body('a')
            ..stock['ore'] = n(1e6)
            ..buildings.add(
              BuildingState(id: 'press', defId: 'press', crew: 1),
            );
          t.body('b').ownerId = 'p';
          t.routes.add(
            RouteState(
              id: 'r1',
              ownerId: 'p',
              fromBodyId: 'a',
              toBodyId: 'b',
              resourceId: 'plate',
              ratePerSecond: n(5),
              cargoShips: 5,
            ),
          );
          e.advance(t, 1200, maxStep: step);
          return t;
        }

        final live = routeThroughput(played(1), withPress, 'r1');
        final away = routeThroughput(played(60), withPress, 'r1');
        expect(live.binding, RouteLimit.sourceStock);
        expect(away.binding, RouteLimit.sourceStock);
        expect(live.perSec, closeTo(0.5, 0.01));
        expect(away.perSec, closeTo(live.perSec, live.perSec * 1e-6));
      });
    });
  });

  test('the merge window comes from the rules', () {
    expect(c.rules.shipmentMergeSeconds, RulesDef.defaultShipmentMergeSeconds);
    route();
    run(25);
    expect(s.shipments, hasLength(3));
  });
}
