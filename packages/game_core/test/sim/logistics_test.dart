import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'economy_fixture.dart';

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

    final (mergedPeak, merged) = play(mergeSeconds: shipmentMergeSeconds);
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
}
