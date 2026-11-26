import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

Map<String, double> plain(Map<String, BigNum> m) => {
  for (final e in m.entries) e.key: e.value.toDouble(),
};

Matcher rates(Map<String, double> expected) => allOf(
  hasLength(expected.length),
  predicate<Map<String, double>>(
    (m) => expected.entries.every(
      (e) => m.containsKey(e.key) && (m[e.key]! - e.value).abs() < 1e-9,
    ),
    'rates $expected',
  ),
);

void main() {
  late Content c;
  late GameEngine engine;
  late GameState s;
  late BodyState kora;

  setUp(() {
    c = shippedContent();
    engine = GameEngine(c);
    s = engine.newGame(1);
    kora = s.body('kora');
  });

  BodyFlow koraFlow(FlowReport r) =>
      r.bodies.singleWhere((b) => b.bodyId == 'kora');

  test('per-second rates of the starting setup', () {
    final r = buildFlowReport(s, c, 'player');
    expect(r.bodies.map((b) => b.bodyId), ['kora']);
    final f = koraFlow(r);
    // Mines: 2 per 5 s × richness 1.0 / 0.8; smelter: 2 ore → 1 steel per 5 s.
    expect(
      plain(f.producedPerSec),
      rates({'iron_ore': 0.4, 'copper_ore': 0.32, 'steel': 0.2}),
    );
    expect(plain(f.consumedPerSec), rates({'iron_ore': 0.4}));
    expect(plain(f.netPerSec), rates({'copper_ore': 0.32, 'steel': 0.2}));
    expect(f.wastedPerSec, isEmpty);
    expect(plain(r.empireNet), rates({'copper_ore': 0.32, 'steel': 0.2}));
    expect(r.bottlenecks, isEmpty);
  });

  test('building statuses report run, crew and slots', () {
    engine.apply(
      s,
      const UpgradeCommand('player', 'b3', UpgradeTrack.capacity),
    );
    // With the iron mine idle, the smelter has only the stock to use.
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0.2);
    final st = koraFlow(buildFlowReport(s, c, 'player')).buildings;
    expect(st.map((b) => b.buildingId), ['b1', 'b2', 'b3']);
    expect(st.map((b) => b.defId), ['mine', 'mine', 'smelter']);
    expect(st[0].runFraction, 0);
    expect(st[0].limitReason, 'noCrew');
    expect(st[1].runFraction, 1);
    expect(st[1].limitReason, isNull);
    expect(st[2].runFraction, closeTo(0.5, 1e-12));
    expect(st[2].limitReason, 'input:iron_ore');
    expect(st[2].crew, 1);
    expect(st[2].slots, 2);
  });

  test('building statuses give actual rates and effective fraction', () {
    s.faction('player').baseCrew = 30;
    engine
      ..apply(s, const UpgradeCommand('player', 'b3', UpgradeTrack.capacity))
      ..apply(s, const AssignCrewCommand('player', 'b3', 2))
      ..apply(s, const AssignCrewCommand('player', 'b2', 0));
    // Two crew on one base slot want 0.8 ore a second: 0.2 in stock plus
    // the 0.4 the iron mine makes in the same tick.
    kora.stock['iron_ore'] = n(0.2);
    final st = koraFlow(buildFlowReport(s, c, 'player')).buildings;
    final (mine, idle, smelter) = (st[0], st[1], st[2]);
    expect(plain(mine.outputsPerSec), rates({'iron_ore': 0.4}));
    expect(mine.inputsPerSec, isEmpty);
    expect(mine.effectiveFraction, 1);
    expect(idle.outputsPerSec, isEmpty);
    expect(idle.effectiveFraction, 0);
    expect(smelter.runFraction, closeTo(0.75, 1e-12));
    // Run fraction 0.75 × crew fraction 2 × crew efficiency 1.
    expect(smelter.effectiveFraction, closeTo(1.5, 1e-12));
    expect(plain(smelter.inputsPerSec), rates({'iron_ore': 0.6}));
    expect(plain(smelter.outputsPerSec), rates({'steel': 0.3}));
  });

  test('effective fraction includes crew efficiency', () {
    s.faction('player').baseCrew = 2; // 2 of 3 assigned crew supported
    final st = koraFlow(buildFlowReport(s, c, 'player')).buildings;
    expect(st[0].runFraction, 1);
    expect(st[0].effectiveFraction, closeTo(2 / 3, 1e-12));
    expect(plain(st[0].outputsPerSec), rates({'iron_ore': 0.4 * 2 / 3}));
  });

  test('credits per second is the change over the sample tick', () {
    expect(buildFlowReport(s, c, 'player').creditsPerSec.isZero, isTrue);
    engine.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
    final r = buildFlowReport(s, c, 'player');
    // 0.2 steel a second at its base price: so far below what the market
    // absorbs that the price barely moves.
    final full = 0.2 * c.resources['steel']!.basePrice.toDouble();
    expect(r.creditsPerSec.toDouble(), closeTo(full, 1e-3));
    expect(r.creditsPerSec.toDouble(), lessThan(full));
  });

  group('rates are steady per-second rates, not one tick\'s drain', () {
    // Auto-selling every input keeps back only one step's demand, so after
    // a 60 s tick a 1 s sample would sell 59 s of kept ore at once.
    void autoSellAll() {
      for (final id in ['iron_ore', 'copper_ore', 'steel']) {
        engine.apply(s, SetAutoSellCommand('player', 'kora', id, n(0)));
      }
    }

    test('credits per second match what a 10 minute advance earns', () {
      autoSellAll();
      engine.advance(s, 4 * 3600);
      final r = buildFlowReport(s, c, 'player');
      final before = s.faction('player').credits;
      engine.advance(s, 600);
      final earned = (s.faction('player').credits - before).toDouble() / 600;
      expect(earned, greaterThan(0));
      expect(r.creditsPerSec.toDouble(), closeTo(earned, earned * 0.1));
    });

    test('net per second is the steady flow', () {
      autoSellAll();
      engine.advance(s, 4 * 3600);
      final f = koraFlow(buildFlowReport(s, c, 'player'));
      // The smelter uses all the iron ore the mine makes and the rest is
      // sold as it is made, so no stock moves.
      expect(f.netPerSec, isEmpty);
    });
  });

  test('net includes route outflow; empire net counts cargo in flight', () {
    s.body('hollow_reach').ownerId = 'player';
    kora.stock['cargo_ship'] = n(1);
    engine.apply(
      s,
      CreateRouteCommand(
        'player',
        'kora',
        'hollow_reach',
        'copper_ore',
        n(1),
        1,
      ),
    );
    final r = buildFlowReport(s, c, 'player');
    expect(r.bodies.map((b) => b.bodyId), ['kora', 'hollow_reach']);
    final f = koraFlow(r);
    expect(plain(f.producedPerSec)['copper_ore'], closeTo(0.32, 1e-9));
    // All of this second's copper ore left on the route, and in steady
    // flow as much lands at the other end each second.
    expect(f.netPerSec.containsKey('copper_ore'), isFalse);
    final hollow = r.bodies.singleWhere((b) => b.bodyId == 'hollow_reach');
    expect(plain(hollow.netPerSec), rates({'copper_ore': 0.32}));
    expect(plain(r.empireNet), rates({'copper_ore': 0.32, 'steel': 0.2}));
  });

  test('output lost to the storage cap is reported as waste', () {
    kora.stock['copper_ore'] = n(1000);
    final r = buildFlowReport(s, c, 'player');
    final f = koraFlow(r);
    expect(plain(f.producedPerSec)['copper_ore'], closeTo(0.32, 1e-9));
    expect(plain(f.wastedPerSec), rates({'copper_ore': 0.32}));
    expect(f.netPerSec.containsKey('copper_ore'), isFalse);

    final b = r.bottlenecks.single;
    expect(b.kind, BottleneckKind.storageFull);
    expect(
      b.message,
      'Kora storage is full of Copper Ore: output is being wasted',
    );
    expect(b.bodyId, 'kora');
    expect(b.buildingId, isNull);
    expect(b.resourceId, 'copper_ore');
    expect(b.runFraction, 0);
  });

  test('storage full reports the share of output kept', () {
    // 1000 - 0.16 leaves room for half of a second's 0.32 copper ore.
    kora.stock['copper_ore'] = n(1000 - 0.16);
    final b = buildFlowReport(s, c, 'player').bottlenecks.single;
    expect(b.kind, BottleneckKind.storageFull);
    expect(b.runFraction, closeTo(0.5, 1e-9));
  });

  test('a store that wastes all it makes keeps exactly 0', () {
    // Eight hours of the starting setup fill copper ore and steel; the
    // waste then matches production up to float residue.
    engine.advance(s, 8 * 3600);
    final necks = buildFlowReport(s, c, 'player').bottlenecks;
    expect(necks.map((b) => (b.kind, b.resourceId, b.runFraction)), [
      (BottleneckKind.storageFull, 'copper_ore', 0),
      (BottleneckKind.storageFull, 'steel', 0),
    ]);
  });

  test('a full store that wastes nothing is not a bottleneck', () {
    kora.stock['steel'] = n(1000); // full, but nothing makes more... yet
    engine.apply(s, const AssignCrewCommand('player', 'b3', 0));
    expect(buildFlowReport(s, c, 'player').bottlenecks.map((b) => b.kind), [
      BottleneckKind.noCrew,
    ]);
  });

  test('flow report does not mutate state', () {
    s.body('hollow_reach').ownerId = 'player';
    kora.stock['cargo_ship'] = n(1);
    engine
      ..apply(
        s,
        CreateRouteCommand(
          'player',
          'kora',
          'hollow_reach',
          'copper_ore',
          n(1),
          1,
        ),
      )
      ..apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(10)))
      ..advance(s, 125);
    final before = jsonEncode(s.toJson());
    final wasted = Map.of(kora.wastedThisStep);
    buildFlowReport(s, c, 'player');
    expect(jsonEncode(s.toJson()), before);
    expect(kora.wastedThisStep, wasted);
  });

  test('bottleneck message names the building, body, and resource', () {
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0.2);
    final b = buildFlowReport(
      s,
      c,
      'player',
    ).bottlenecks.singleWhere((b) => b.kind == BottleneckKind.input);
    expect(b.message, 'Smelter on Kora is running at 50%: not enough Iron Ore');
    expect(b.kind, BottleneckKind.input);
    expect(b.bodyId, 'kora');
    expect(b.buildingId, 'b3');
    expect(b.resourceId, 'iron_ore');
    expect(b.runFraction, closeTo(0.5, 1e-12));
  });

  test('bottlenecks sort by run fraction, then body and building order', () {
    kora.stock['iron_ore'] = n(0.2);
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    final hollow = s.body('hollow_reach')..ownerId = 'player';
    hollow.buildings.add(BuildingState(id: 'x1', defId: 'smelter', crew: 0));
    final list = buildFlowReport(s, c, 'player').bottlenecks;
    expect(list.map((b) => b.message), [
      'Mine on Kora has no crew',
      'Smelter on Hollow Reach has no crew',
      'Smelter on Kora is running at 50%: not enough Iron Ore',
    ]);
    expect(list.first.resourceId, isNull);
    expect(list.first.kind, BottleneckKind.noCrew);
  });

  test('crew shortage is reported as a bottleneck', () {
    // Three crew assigned at start; base crew of 2 supports only two.
    s.faction('player').baseCrew = 2;
    final b = buildFlowReport(s, c, 'player').bottlenecks.single;
    expect(b.kind, BottleneckKind.crewShortage);
    expect(
      b.message,
      'Your empire is short on crew: '
      'habitats and base crew support 2 of 3 assigned',
    );
    // A faction-wide shortage names no body or building.
    expect(b.bodyId, isNull);
    expect(b.buildingId, isNull);
    expect(b.resourceId, isNull);
    expect(b.runFraction, closeTo(2 / 3, 1e-12));
  });

  test('crew shortage sorts with the other bottlenecks by run fraction', () {
    // Two crew assigned, one supported. At crew efficiency 0.5 the smelter
    // wants 0.2 ore and gets 0.15; the iron mine is idle.
    s.faction('player').baseCrew = 1;
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0.15);
    final hollow = s.body('hollow_reach')..ownerId = 'player';
    hollow.buildings.add(BuildingState(id: 'x1', defId: 'smelter', crew: 0));
    final list = buildFlowReport(s, c, 'player').bottlenecks;
    expect(list.map((b) => b.kind), [
      BottleneckKind.noCrew,
      BottleneckKind.noCrew,
      BottleneckKind.crewShortage,
      BottleneckKind.input,
    ]);
    expect(list.map((b) => b.runFraction), [
      0,
      0,
      closeTo(0.5, 1e-12),
      closeTo(0.75, 1e-12),
    ]);
  });

  test('no crew bottleneck when habitats and base crew cover everyone', () {
    s.faction('player').baseCrew = 3;
    expect(buildFlowReport(s, c, 'player').bottlenecks, isEmpty);
  });

  test('crew shortage counts crew as the sample tick started', () {
    // The habitat ran at 0 last step, so it houses no one yet; fed now, it
    // runs fully during the sample tick, which must not change the counts.
    s.faction('player').baseCrew = 2;
    kora.buildings.add(BuildingState(id: 'h1', defId: 'habitat', crew: 0));
    for (final id in ['food', 'water', 'oxygen']) {
      kora.stock[id] = n(10);
    }
    final b = buildFlowReport(
      s,
      c,
      'player',
    ).bottlenecks.singleWhere((b) => b.kind == BottleneckKind.crewShortage);
    expect(
      b.message,
      'Your empire is short on crew: '
      'habitats and base crew support 2 of 3 assigned',
    );
    expect(b.runFraction, closeTo(2 / 3, 1e-12));
  });

  test('a crewless habitat reports its supply, not a missing crew', () {
    s.faction('player').baseCrew = 3;
    kora.buildings.add(BuildingState(id: 'h1', defId: 'habitat', crew: 0));
    kora.stock['food'] = n(10);
    kora.stock['water'] = n(10);
    kora.stock['oxygen'] = n(0.05); // half of what a second needs
    final r = buildFlowReport(s, c, 'player');
    final h = koraFlow(r).buildings.singleWhere((b) => b.buildingId == 'h1');
    expect(h.runFraction, closeTo(0.5, 1e-12));
    expect(h.effectiveFraction, closeTo(0.5, 1e-12));
    expect(h.slots, 0);
    expect(
      r.bottlenecks.single.message,
      'Habitat on Kora is running at 50%: not enough Oxygen',
    );
  });
}
