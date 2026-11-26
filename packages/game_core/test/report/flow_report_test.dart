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
    kora.stock['iron_ore'] = n(0.2);
    final st = koraFlow(buildFlowReport(s, c, 'player')).buildings;
    expect(st.map((b) => b.buildingId), ['b1', 'b2', 'b3']);
    expect(st.map((b) => b.defId), ['mine', 'mine', 'smelter']);
    expect(st[0].runFraction, 1);
    expect(st[0].limitReason, isNull);
    expect(st[2].runFraction, closeTo(0.5, 1e-12));
    expect(st[2].limitReason, 'input:iron_ore');
    expect(st[2].crew, 1);
    expect(st[2].slots, 2);
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
    // All of this second's copper ore left on the route.
    expect(f.netPerSec.containsKey('copper_ore'), isFalse);
    expect(plain(r.empireNet), rates({'copper_ore': 0.32, 'steel': 0.2}));
  });

  test('output lost to the storage cap is reported as waste', () {
    kora.stock['copper_ore'] = n(1000);
    final f = koraFlow(buildFlowReport(s, c, 'player'));
    expect(plain(f.producedPerSec)['copper_ore'], closeTo(0.32, 1e-9));
    expect(plain(f.wastedPerSec), rates({'copper_ore': 0.32}));
    expect(f.netPerSec.containsKey('copper_ore'), isFalse);
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
    kora.stock['iron_ore'] = n(0.2);
    final b = buildFlowReport(s, c, 'player').bottlenecks.single;
    expect(b.message, 'Smelter on Kora is running at 50%: not enough Iron Ore');
    expect(b.kind, BottleneckKind.input);
    expect(b.bodyId, 'kora');
    expect(b.buildingId, 'b3');
    expect(b.resourceId, 'iron_ore');
    expect(b.runFraction, closeTo(0.5, 1e-12));
  });

  test('bottlenecks sort by run fraction, then body and building order', () {
    kora.stock['iron_ore'] = n(0.2);
    engine.apply(s, const AssignCrewCommand('player', 'b2', 0));
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
    expect(b.bodyId, 'kora');
    expect(b.buildingId, 'b1');
    expect(b.resourceId, isNull);
    expect(b.runFraction, closeTo(2 / 3, 1e-12));
  });

  test('crew shortage sorts with the other bottlenecks by run fraction', () {
    s.faction('player').baseCrew = 2;
    // At 2/3 crew efficiency the smelter wants 0.2667 ore and gets 0.2.
    kora.stock['iron_ore'] = n(0.2);
    final hollow = s.body('hollow_reach')..ownerId = 'player';
    hollow.buildings.add(BuildingState(id: 'x1', defId: 'smelter', crew: 0));
    final list = buildFlowReport(s, c, 'player').bottlenecks;
    expect(list.map((b) => b.kind), [
      BottleneckKind.noCrew,
      BottleneckKind.crewShortage,
      BottleneckKind.input,
    ]);
    expect(list.map((b) => b.runFraction), [
      0,
      closeTo(2 / 3, 1e-12),
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
    kora.buildings.add(BuildingState(id: 'h1', defId: 'habitat', crew: 1));
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
      'habitats and base crew support 2 of 4 assigned',
    );
    expect(b.runFraction, closeTo(0.5, 1e-12));
  });
}
