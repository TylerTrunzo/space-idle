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
    expect(r.revenue, n(500));
    expect(s.market.saturation['ore'], closeTo(0.5, 1e-12));
    expect(s.faction('p').credits, n(500));
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
    sell(s, c, 'p', 'a', 'ore', n(500));
    expect(s.market.saturation['ore'], 0.2);
    expect(price(s, c, 'ore').toDouble(), closeTo(2, 1e-9));
  });

  test('selling more than the body holds sells only what it holds', () {
    s.body('a').stock['ore'] = n(30);
    final r = sell(s, c, 'p', 'a', 'ore', n(100));
    expect(r.sold, n(30));
    expect(r.revenue, n(300));
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

  test('auto-sell keeps minimum', () {
    s
        .faction('p')
        .autoSell
        .add(AutoSellRule(bodyId: 'a', resourceId: 'ore', keepAtLeast: n(450)));
    stepMarket(s, c, 1);
    expect(stock(), n(450));
    expect(s.faction('p').credits, n(500));
    stepMarket(s, c, 1); // nothing above the minimum
    expect(stock(), n(450));
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
