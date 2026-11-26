import 'dart:math' as math;

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

  // The fixture market: ore at 10, depth 100, recovery 1800 s, floor 0.2.
  // Each unit sold cuts the price by 1/depth of itself, so selling n units
  // at once takes the saturation from s0 to s0 × e^(−n/100); unsold, the
  // gap to full price shrinks by a factor e every 1800 s.

  test('selling lowers price and recovers', () {
    final r = sell(s, c, 'p', 'a', 'ore', n(50));
    expect(r.sold, n(50));
    final s1 = math.exp(-0.5);
    // Revenue is base × depth × (s0 − s1).
    expect(r.revenue.toDouble(), closeTo(10 * 100 * (1 - s1), 1e-9));
    expect(s.market.saturation['ore'], closeTo(s1, 1e-12));
    expect(s.faction('p').credits, r.revenue);
    expect(price(s, c, 'ore').toDouble(), closeTo(10 * s1, 1e-9));
    stepMarket(s, c, 1800);
    expect(
      s.market.saturation['ore'],
      closeTo(1 - (1 - s1) * math.exp(-1), 1e-12),
    );
  });

  test('recovery is gradual and never quite reaches full price', () {
    s.market.saturation['ore'] = 0.5;
    stepMarket(s, c, 900);
    expect(
      s.market.saturation['ore'],
      closeTo(1 - 0.5 * math.exp(-0.5), 1e-12),
    );
    stepMarket(s, c, 18000);
    expect(s.market.saturation['ore'], lessThan(1));
    expect(s.market.saturation['ore'], closeTo(1, 1e-4));
  });

  test('price floor', () {
    final r = sell(s, c, 'p', 'a', 'ore', n(500));
    // 100 × ln(1 / 0.2) units take the price from 10 down to the floor of
    // 2; the rest sell at the floor.
    final toFloor = 100 * math.log(5);
    expect(
      r.revenue.toDouble(),
      closeTo(10 * 100 * 0.8 + (500 - toFloor) * 2, 1e-6),
    );
    expect(s.market.saturation['ore'], 0.2);
    expect(price(s, c, 'ore').toDouble(), closeTo(2, 1e-9));
  });

  test('selling more than the body holds sells only what it holds', () {
    s.body('a').stock['ore'] = n(30);
    final r = sell(s, c, 'p', 'a', 'ore', n(100));
    expect(r.sold, n(30));
    expect(r.revenue.toDouble(), closeTo(1000 * (1 - math.exp(-0.3)), 1e-9));
    expect(stock().isZero, isTrue);
    expect(s.market.saturation['ore'], closeTo(math.exp(-0.3), 1e-12));
  });

  test('selling all the body holds leaves it at exactly zero', () {
    // 30 − 1e-13 equals 30 at BigNum precision, so the sale is the full 30.
    s.body('a').stock['ore'] = BigNum.from(30 - 1e-13);
    sell(s, c, 'p', 'a', 'ore', n(30));
    expect(stock().isNegative, isFalse);
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

  /// Credits a second, and the saturation, after [rate] units a second
  /// have been auto-sold for long enough to settle.
  (double, double) steady(double rate) {
    final t = newGameState(c, 1);
    final f = t.faction('p')
      ..autoSell.add(
        AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(0)),
      );
    for (var i = 0; i < 400; i++) {
      t.body('a').stock['ore'] = n(rate * 60);
      stepMarket(t, c, 60);
    }
    final before = f.credits;
    t.body('a').stock['ore'] = n(rate * 60);
    stepMarket(t, c, 60);
    return ((f.credits - before).toDouble() / 60, t.market.saturation['ore']!);
  }

  test('steady selling settles where recovery meets the sales', () {
    // At 0.1 a second: 1 / (1 + 0.1 × 1800 / 100).
    final (income, sat) = steady(0.1);
    expect(sat, closeTo(1 / 2.8, 1e-6));
    expect(income, closeTo(10 * 0.1 / 2.8, 1e-6));
  });

  test('selling more always earns more, with diminishing returns', () {
    final rates = [0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0];
    final incomes = [for (final r in rates) steady(r).$1];
    for (var i = 1; i < rates.length; i++) {
      expect(incomes[i], greaterThan(incomes[i - 1]), reason: '${rates[i]}');
      // Never more per unit than at a lower rate.
      expect(
        incomes[i] / rates[i],
        lessThanOrEqualTo(incomes[i - 1] / rates[i - 1] + 1e-12),
      );
    }
    // Far past what the market absorbs, every unit sells at the floor.
    expect(incomes.last, closeTo(10 * 10 * 0.2, 1e-6));
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

  test("a resource's own floor replaces the rules' floor", () {
    final base = economyContent();
    c = Content(
      rules: base.rules,
      resources: {
        'ore': ResourceDef(
          id: 'ore',
          name: 'Ore',
          tier: 0,
          basePrice: n(10),
          marketDepth: 100,
          marketFloor: 0.05,
        ),
      },
      buildings: base.buildings,
      bodyTypes: base.bodyTypes,
      galaxy: base.galaxy,
      milestones: base.milestones,
    );
    s = newGameState(c, 1)..body('a').stock['ore'] = n(1000);
    sell(s, c, 'p', 'a', 'ore', n(1000));
    expect(s.market.saturation['ore'], 0.05);
    s
        .faction('p')
        .autoSell
        .add(AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(0)));
    s.body('a').stock['ore'] = n(1000);
    stepMarket(s, c, 1);
    expect(s.market.saturation['ore'], 0.05);
  });

  test('a sale starting at the floor pays the floor price', () {
    s.market.saturation['ore'] = 0.2;
    expect(
      sell(s, c, 'p', 'a', 'ore', n(10)).revenue.toDouble(),
      closeTo(20, 1e-9),
    );
  });

  test('auto-sell keeps minimum', () {
    s
        .faction('p')
        .autoSell
        .add(AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(450)));
    stepMarket(s, c, 1);
    expect(stock(), n(450));
    // 50 sold over the second: ds/dt = (1 − s) / 1800 − 0.5 s, so the
    // saturation heads for e = (1/1800) / k at rate k = 1/1800 + 0.5.
    const k = 1 / 1800 + 0.5;
    const eq = (1 / 1800) / k;
    final average = eq + (1 - eq) * (1 - math.exp(-k)) / k;
    expect(s.faction('p').credits.toDouble(), closeTo(500 * average, 1e-9));
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

  group('auto-sell earns the same in long steps as in short ones', () {
    // Ore arrives at a steady rate and is auto-sold; the market (depth 100,
    // recovery 1800 s) absorbs 0.0556 a second before it saturates.
    for (final rate in [0.03, 0.05, 0.08, 0.5]) {
      test('$rate a second', () {
        double earned(double dt) {
          final t = newGameState(c, 1);
          t
              .faction('p')
              .autoSell
              .add(
                AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(0)),
              );
          for (var time = 0.0; time < 7200; time += dt) {
            t.body('a').stock['ore'] = n(rate * dt);
            stepMarket(t, c, dt);
          }
          return t.faction('p').credits.toDouble();
        }

        final fine = earned(1);
        expect(earned(60), closeTo(fine, fine * 0.002));
      });
    }
  });

  test('every sale adds to the faction\'s sales revenue by resource', () {
    final f = s.faction('p');
    expect(f.salesRevenue, isEmpty);
    final r = sell(s, c, 'p', 'a', 'ore', n(10));
    expect(f.salesRevenue, {'ore': r.revenue});
    f.autoSell.add(
      AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(400)),
    );
    final before = f.credits;
    stepMarket(s, c, 1);
    expect(f.salesRevenue['ore'], r.revenue + (f.credits - before));
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
