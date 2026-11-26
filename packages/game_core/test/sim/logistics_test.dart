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
      id: 'r1',
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
    run(10);
    expect(inTransit().toDouble(), closeTo(10, 1e-9));
    expect(at(b).isZero, isTrue);
    expect(at(a).toDouble(), closeTo(990, 1e-9));
    s.routes.clear(); // stop sending; the 10 s of cargo is still in flight
    run(111); // stepped at time 120: the first lands, the last (t=9) has not
    expect(at(b).toDouble(), closeTo(1, 1e-9));
    run(10); // time 130: all landed
    expect(at(b).toDouble(), closeTo(10, 1e-9));
    expect(inTransit().isZero, isTrue);
    expect(at(a).toDouble(), closeTo(990, 1e-9));
  });

  test('first shipment lands exactly at its arrival time', () {
    route();
    run(1); // sent at time 0, arrives at 120
    s.time = 119;
    stepLogistics(s, c, 0);
    expect(at(b).isZero, isTrue);
    s.time = 120;
    stepLogistics(s, c, 0);
    expect(at(b).toDouble(), closeTo(1, 1e-9));
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

  test('delivery clamps to storage cap and wastes the overflow', () {
    b.stock['ore'] = n(995);
    route();
    run(10);
    s.time = 1000;
    stepLogistics(s, c, 0);
    expect(at(b), n(1000));
    expect(b.wastedThisStep['ore']!.toDouble(), closeTo(5, 1e-9));
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
    expect(sh.arriveAt, s.shipments.first.arriveAt);
    loaded.time = 500;
    stepLogistics(loaded, c, 1);
    expect(at(loaded.body('b')).toDouble(), closeTo(10, 1e-9));
  });
}
