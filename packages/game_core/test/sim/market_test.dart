import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'economy_fixture.dart';

void main() {
  late Content c;
  late GameState s;

  setUp(() {
    c = economyContent();
    s = newGameState(c, 1);
    s.body('a').stock['ore'] = n(500);
  });

  BigNum stock() => s.body('a').stock['ore'] ?? const BigNum.zero();

  test('selling lowers price and recovers', () {
    final r = sell(s, c, 'p', 'a', 'ore', n(50));
    expect(r.sold, n(50));
    // The price falls from 10 to 5 over the sale: 50 units at 7.5 on average.
    expect(r.revenue, n(375));
    expect(s.market.saturation['ore'], closeTo(0.5, 1e-12));
    expect(s.faction('p').credits, n(375));
    expect(price(s, c, 'ore').toDouble(), closeTo(5, 1e-9));
    stepMarket(s, c, 1800);
    expect(s.market.saturation['ore'], 1.0);
  });

  test('recovery is gradual', () {
    sell(s, c, 'p', 'a', 'ore', n(50));
    stepMarket(s, c, 900);
    expect(s.market.saturation['ore'], closeTo(1.0, 1e-12));
    sell(s, c, 'p', 'a', 'ore', n(80)); // 1.0 -> 0.2
    stepMarket(s, c, 900);
    expect(s.market.saturation['ore'], closeTo(0.7, 1e-12));
  });

  test('price floor', () {
    final r = sell(s, c, 'p', 'a', 'ore', n(500));
    // 80 units take the price from 10 down to the floor of 2 (6 on
    // average); the other 420 sell at the floor.
    expect(r.revenue.toDouble(), closeTo(80 * 6 + 420 * 2, 1e-9));
    expect(s.market.saturation['ore'], 0.2);
    expect(price(s, c, 'ore').toDouble(), closeTo(2, 1e-9));
  });

  test('selling more than the body holds sells only what it holds', () {
    s.body('a').stock['ore'] = n(30);
    final r = sell(s, c, 'p', 'a', 'ore', n(100));
    expect(r.sold, n(30));
    expect(r.revenue.toDouble(), closeTo(30 * 8.5, 1e-9));
    expect(stock().isZero, isTrue);
    expect(s.market.saturation['ore'], closeTo(0.7, 1e-12));
  });

  test('repeated sales clamp saturation at the floor', () {
    for (var i = 0; i < 5; i++) {
      sell(s, c, 'p', 'a', 'ore', n(100));
    }
    expect(s.market.saturation['ore'], 0.2);
    final before = s.faction('p').credits;
    s.body('a').stock['ore'] = n(10);
    sell(s, c, 'p', 'a', 'ore', n(10));
    expect(s.faction('p').credits - before, n(20));
    expect(s.market.saturation['ore'], 0.2);
  });

  group('one lot earns what many small lots do', () {
    for (final (total, lots) in [(50, 50), (500, 50), (500, 7)]) {
      test('$total units in $lots lots', () {
        final one = sell(s, c, 'p', 'a', 'ore', n(total)).revenue.toDouble();
        final t = newGameState(c, 1);
        t.body('a').stock['ore'] = n(500);
        var many = 0.0;
        for (var i = 0; i < lots; i++) {
          many += sell(
            t,
            c,
            'p',
            'a',
            'ore',
            n(total / lots),
          ).revenue.toDouble();
        }
        expect(many, closeTo(one, one * 1e-9));
        expect(
          t.market.saturation['ore'],
          closeTo(s.market.saturation['ore']!, 1e-12),
        );
      });
    }
  });

  test('a sale starting at the floor pays the floor price', () {
    s.market.saturation['ore'] = 0.2;
    expect(sell(s, c, 'p', 'a', 'ore', n(10)).revenue, n(20));
  });

  test('auto-sell keeps minimum', () {
    s
        .faction('p')
        .autoSell
        .add(AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(450)));
    stepMarket(s, c, 1);
    expect(stock(), n(450));
    expect(s.faction('p').credits, n(375));
    stepMarket(s, c, 1); // nothing above the minimum
    expect(stock(), n(450));
  });

  test('auto-sell also keeps what buildings on the body use in the step', () {
    // A press using 2 ore a second, crewed: a 10 s step needs 20 ore.
    final base = economyContent();
    c = Content(
      rules: base.rules,
      resources: {
        ...base.resources,
        'plate': ResourceDef(
          id: 'plate',
          name: 'Plate',
          tier: 1,
          basePrice: n(1),
        ),
      },
      buildings: {
        'press': BuildingDef(
          id: 'press',
          name: 'Press',
          kind: BuildingKind.factory,
          cycleSeconds: 1,
          inputs: const {'ore': 2},
          outputs: const {'plate': 1},
          crewSlots: 1,
          buildCost: const {},
        ),
      },
      bodyTypes: base.bodyTypes,
      galaxy: base.galaxy,
      milestones: base.milestones,
    );
    s = newGameState(c, 1);
    s.body('a')
      ..stock['ore'] = n(500)
      ..buildings.add(BuildingState(id: 'b1', defId: 'press', crew: 1));
    s
        .faction('p')
        .autoSell
        .add(AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(100)));
    stepMarket(s, c, 10);
    expect(stock(), n(120));
    // An unstaffed press uses nothing.
    s.body('a').buildings.single.crew = 0;
    stepMarket(s, c, 10);
    expect(stock(), n(100));
  });

  test('auto-sell skips bodies the faction no longer owns', () {
    s
        .faction('p')
        .autoSell
        .add(AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(0)));
    s.body('a').ownerId = null;
    stepMarket(s, c, 1);
    expect(stock(), n(500));
    expect(s.faction('p').credits.isZero, isTrue);
  });
}
