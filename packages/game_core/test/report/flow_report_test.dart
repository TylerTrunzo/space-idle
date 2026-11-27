import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../sim/economy_fixture.dart' as fx;
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

/// [r]'s bottlenecks but [BottleneckKind.noSales]: most tests here start
/// from a new game, which has no auto-sell rule yet.
List<Bottleneck> held(FlowReport r) => [
  for (final b in r.bottlenecks)
    if (b.kind != BottleneckKind.noSales) b,
];

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
    // Nothing is held back but the sales: no auto-sell rule yet.
    expect(r.bottlenecks.map((b) => b.kind), [BottleneckKind.noSales]);
  });

  test('a noSales bottleneck says when goods are made and nothing sells '
      'them', () {
    // Round-3 new player, t=0: 0 credits a second and no bottleneck.
    final neck = buildFlowReport(s, c, 'player').bottlenecks.single;
    expect(neck.kind, BottleneckKind.noSales);
    expect(
      (neck.bodyId, neck.buildingId, neck.resourceId, neck.runFraction),
      (null, null, null, 0.0),
    );
    expect(
      neck.message,
      'Nothing is being sold: turn on auto-sell or sell goods',
    );
    // What selling the steady net production would earn, at today's prices.
    final perHour =
        (0.32 * price(s, c, 'copper_ore').toDouble() +
            0.2 * price(s, c, 'steel').toDouble()) *
        3600;
    expect(neck.lostCreditsPerHour!.toDouble(), closeTo(perHour, 1e-6));
    engine.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
    expect(buildFlowReport(s, c, 'player').bottlenecks, isEmpty);
    // Nothing made, nothing to sell: no bottleneck either.
    final idle = engine.newGame(1);
    for (final b in idle.body('kora').buildings) {
      b.crew = 0;
    }
    expect(
      buildFlowReport(
        idle,
        c,
        'player',
      ).bottlenecks.where((b) => b.kind == BottleneckKind.noSales),
      isEmpty,
    );
  });

  test('a noSales bottleneck is noted with the others', () {
    engine.tick(s, 60);
    expect(
      s.faction('player').seenBottlenecks.map((b) => b.kind),
      contains(BottleneckKind.noSales.name),
    );
  });

  test('noSales is noted over time exactly when the report shows it', () {
    // A press makes plates from a stock of ore and a stamper uses every
    // plate for widgets, which have no price: buildings run and make a
    // good with a price, but nothing is left over to sell.
    final base = fx.pressContent();
    final content = Content(
      rules: base.rules,
      resources: {
        ...base.resources,
        'widget': ResourceDef(
          id: 'widget',
          name: 'Widget',
          tier: 2,
          basePrice: const BigNum.zero(),
        ),
      },
      buildings: {
        ...base.buildings,
        'stamper': BuildingDef(
          id: 'stamper',
          name: 'Stamper',
          kind: BuildingKind.factory,
          cycleSeconds: 2,
          inputs: const {'plate': 1},
          outputs: const {'widget': 1},
          crewSlots: 1,
          buildCost: const {},
        ),
      },
      bodyTypes: base.bodyTypes,
      galaxy: base.galaxy,
      milestones: base.milestones,
    );
    final e = GameEngine(content);
    final t = e.newGame(1);
    t.body('a')
      ..stock['ore'] = n(1e3)
      ..buildings.addAll([
        BuildingState(id: 'press', defId: 'press', crew: 1),
        BuildingState(id: 'stamper', defId: 'stamper', crew: 1),
      ]);
    e.tick(t, 1);
    expect(t.body('a').buildings.first.lastRunFraction, 1);
    bool noted() => t
        .faction('p')
        .seenBottlenecks
        .any((b) => b.kind == BottleneckKind.noSales.name);
    bool shown() => buildFlowReport(
      t,
      content,
      'p',
    ).bottlenecks.any((b) => b.kind == BottleneckKind.noSales);
    expect((noted(), shown()), (false, false));
    // Without the stamper the plates pile up unsold: both see it.
    t.body('a').buildings.removeLast();
    e.tick(t, 1);
    expect((noted(), shown()), (true, true));
  });

  test('building statuses report run, crew and slots', () {
    s.faction('player').credits = n(1e6);
    engine.apply(
      s,
      const UpgradeCommand('player', 'b3', UpgradeTrack.capacity),
    );
    // The capacity level crewed its new slot from free crew. With the iron
    // mine idle, the smelter has only the stock to use: 0.2 of the 0.8
    // ore its 2 crew want.
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0.2);
    final st = koraFlow(buildFlowReport(s, c, 'player')).buildings;
    expect(st.map((b) => b.buildingId), ['b1', 'b2', 'b3']);
    expect(st.map((b) => b.defId), ['mine', 'mine', 'smelter']);
    expect(st[0].runFraction, 0);
    expect(st[0].limitReason, 'noCrew');
    expect(st[1].runFraction, 1);
    expect(st[1].limitReason, isNull);
    expect(st[2].runFraction, closeTo(0.25, 1e-12));
    expect(st[2].limitReason, 'input:iron_ore');
    expect(st[2].crew, 2);
    expect(st[2].slots, 2);
  });

  test('building statuses give actual rates and effective fraction', () {
    s.faction('player')
      ..baseCrew = 30
      ..credits = n(1e6);
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
      // No board: what a contract holds back is not sold during the
      // advance, and credits per second leave contracts out.
      s.faction('player').contractRefillAt.clear();
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
      // No board: a contract would hold goods back, so stock would move.
      s.faction('player').contractRefillAt.clear();
      autoSellAll();
      engine.advance(s, 4 * 3600);
      final f = koraFlow(buildFlowReport(s, c, 'player'));
      // The smelter uses all the iron ore the mine makes and the rest is
      // sold as it is made, so no stock moves.
      expect(f.netPerSec, isEmpty);
    });
  });

  group('credits per second is steady sale revenue from net production', () {
    test('goods held back for open contracts still count: the hold fills '
        'once and is not lost income', () {
      final f = s.faction('player')..contractRefillAt.clear();
      for (final id in ['iron_ore', 'copper_ore', 'steel']) {
        engine.apply(s, SetAutoSellCommand('player', 'kora', id, n(0)));
      }
      engine.advance(s, 3600);
      final without = buildFlowReport(s, c, 'player').creditsPerSec;
      expect(without > const BigNum.zero(), isTrue);
      f.contracts.add(
        ContractState(
          id: s.newId('c'),
          templateId: c.contractTemplates.keys.first,
          resourceId: 'steel',
          quantity: n(900),
          rewardCredits: n(1),
          postedAt: s.time,
        ),
      );
      f.contractRefillAt.addAll([1e9, 1e9]);
      expect(buildFlowReport(s, c, 'player').creditsPerSec, without);
      expect(f.contracts, hasLength(1), reason: 'the state is untouched');
    });

    test('goods made from a stock nothing refills do not count', () {
      // Round-3 optimizer bug 3: presses draining a stock earn in the
      // sample but stop once it runs out. Kora's iron mine is idle; the
      // smelter runs on a stock of ore and its steel is auto-sold.
      engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
      kora.stock['iron_ore'] = n(5000);
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
      final r = buildFlowReport(s, c, 'player');
      expect(koraFlow(r).buildings[2].runFraction, 1, reason: 'runs today');
      expect(r.creditsPerSec.isZero, isTrue);
    });

    test('a stock refilled at part of the use counts that part', () {
      // Hollow Reach ships 0.2 iron ore a second to Kora's smelter, which
      // wants 0.4 and has a stock to draw down: steady, it makes 0.1 steel
      // a second, not 0.2.
      s.body('hollow_reach')
        ..ownerId = 'player'
        ..stock['iron_ore'] = n(1e5)
        ..stock['cargo_ship'] = n(1);
      kora.stock['iron_ore'] = n(5000);
      engine
        ..apply(s, const AssignCrewCommand('player', 'b1', 0))
        ..apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)))
        ..apply(
          s,
          CreateRouteCommand(
            'player',
            'hollow_reach',
            'kora',
            'iron_ore',
            n(0.2),
            1,
          ),
        );
      final r = buildFlowReport(s, c, 'player');
      final steel = c.resources['steel']!.basePrice.toDouble();
      // Hollow Reach's ore stock is not refilled either: only what is
      // made counts, and nothing there makes iron ore.
      expect(r.creditsPerSec.isZero, isTrue);
      s
          .body('hollow_reach')
          .buildings
          .add(
            BuildingState(
              id: s.newId('b'),
              defId: 'mine',
              depositResourceId: 'iron_ore',
              crew: 1,
            ),
          );
      final fed = buildFlowReport(s, c, 'player');
      expect(fed.creditsPerSec.toDouble(), closeTo(0.1 * steel, 1e-2));
    });

    test('stock above an auto-sell rule\'s keep does not count', () {
      kora.stock['steel'] = n(5000);
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
      final r = buildFlowReport(s, c, 'player');
      final full = 0.2 * c.resources['steel']!.basePrice.toDouble();
      expect(r.creditsPerSec.toDouble(), closeTo(full, 1e-2));
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

  test('a building fed by a route shows the route\'s supply between '
      'landings', () {
    // Playtest P6: a Hollow Reach to Cinder nickel route "delivered
    // nothing" because shipments land once a minute and the report's
    // one-second sample fell between landings, showing the magnet works at
    // 0%. Here Hollow Reach sends 0.2 iron ore a second to Kora's smelter,
    // which wants 0.4, with Kora's own iron mine idle.
    s.body('hollow_reach')
      ..ownerId = 'player'
      ..stock['iron_ore'] = n(1000)
      ..stock['cargo_ship'] = n(1);
    kora.stock.remove('iron_ore');
    engine
      ..apply(s, const AssignCrewCommand('player', 'b1', 0))
      ..apply(
        s,
        CreateRouteCommand(
          'player',
          'hollow_reach',
          'kora',
          'iron_ore',
          n(0.2),
          1,
        ),
      )
      // The last step is 30 s, so the report samples between landings.
      ..advance(s, 630);
    expect(s.shipments, isNotEmpty);
    expect(s.shipments.every((sh) => sh.arriveAt > s.time + 1), isTrue);
    final f = koraFlow(buildFlowReport(s, c, 'player'));
    final smelter = f.buildings.singleWhere((b) => b.buildingId == 'b3');
    expect(smelter.runFraction, closeTo(0.5, 1e-9));
    expect(plain(smelter.inputsPerSec), rates({'iron_ore': 0.2}));
  });

  test('output lost to the storage cap is reported as waste', () {
    kora.stock['copper_ore'] = n(1000);
    final r = buildFlowReport(s, c, 'player');
    final f = koraFlow(r);
    expect(plain(f.producedPerSec)['copper_ore'], closeTo(0.32, 1e-9));
    expect(plain(f.wastedPerSec), rates({'copper_ore': 0.32}));
    expect(f.netPerSec.containsKey('copper_ore'), isFalse);

    final b = held(r).single;
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
    final b = held(buildFlowReport(s, c, 'player')).single;
    expect(b.kind, BottleneckKind.storageFull);
    expect(b.runFraction, closeTo(0.5, 1e-9));
  });

  test('a store that wastes all it makes keeps exactly 0', () {
    // Eight hours of the starting setup fill copper ore and steel; the
    // waste then matches production up to float residue.
    engine.advance(s, 8 * 3600);
    final necks = held(buildFlowReport(s, c, 'player'));
    expect(necks.map((b) => (b.kind, b.resourceId, b.runFraction)), [
      (BottleneckKind.storageFull, 'copper_ore', 0),
      (BottleneckKind.storageFull, 'steel', 0),
    ]);
  });

  test('a full store that wastes nothing is not a bottleneck', () {
    kora.stock['steel'] = n(1000); // full, but nothing makes more... yet
    engine.apply(s, const AssignCrewCommand('player', 'b3', 0));
    expect(held(buildFlowReport(s, c, 'player')).map((b) => b.kind), [
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
    // Credits per second plays copies forward when read: still not [s].
    expect(buildFlowReport(s, c, 'player').creditsPerSec.isNegative, isFalse);
    expect(jsonEncode(s.toJson()), before);
    expect(kora.wastedThisStep, wasted);
  });

  test('bottleneck message names the building, body, and resource', () {
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0.2);
    final b = held(
      buildFlowReport(s, c, 'player'),
    ).singleWhere((b) => b.kind == BottleneckKind.input);
    expect(b.message, 'Smelter on Kora is running at 50%: not enough Iron Ore');
    expect(b.kind, BottleneckKind.input);
    expect(b.bodyId, 'kora');
    expect(b.buildingId, 'b3');
    expect(b.resourceId, 'iron_ore');
    expect(b.runFraction, closeTo(0.5, 1e-12));
  });

  test('a building with crew below its base slots is understaffed', () {
    s.faction('player')
      ..baseCrew = 30
      ..credits = n(1e9);
    kora.stock
      ..['copper_wire'] = n(100)
      ..['silicon_wafer'] = n(100);
    final id = engine.apply(
      s,
      const BuildCommand('player', 'kora', 'circuit_fab'),
    );
    final fab = (id as CommandOk).createdId!;
    engine.apply(s, AssignCrewCommand('player', fab, 1));
    final r = buildFlowReport(s, c, 'player');
    final status = koraFlow(
      r,
    ).buildings.singleWhere((b) => b.buildingId == fab);
    expect(status.runFraction, 1);
    expect(status.limitReason, 'understaffed');
    final neck = held(r).singleWhere((b) => b.buildingId == fab);
    expect(neck.kind, BottleneckKind.understaffed);
    expect(neck.message, 'Circuit Fab on Kora is understaffed: 1 of 2 crew');
    expect(neck.resourceId, isNull);
    expect(neck.runFraction, closeTo(0.5, 1e-12));
  });

  test('bottlenecks sort by run fraction, then body and building order', () {
    kora.stock['iron_ore'] = n(0.2);
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    final hollow = s.body('hollow_reach')..ownerId = 'player';
    hollow.buildings.add(BuildingState(id: 'x1', defId: 'smelter', crew: 0));
    final list = held(buildFlowReport(s, c, 'player'));
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
    final b = held(buildFlowReport(s, c, 'player')).single;
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

  test('crew shortage counts nothing for a building more crew would not '
      'help', () {
    // One crew housed for two: the copper mine and a plate press with a
    // little steel and nothing making more. At half crew the press wants
    // 0.1875 steel a second and runs at 0.53; fully crewed it would want
    // twice that and make the same plates from the same steel. Only the
    // mine's lost copper ore counts.
    s.faction('player').baseCrew = 1;
    kora.buildings
      ..removeWhere((b) => b.id != 'b2')
      ..add(BuildingState(id: 'p1', defId: 'plate_press', crew: 1));
    kora.stock
      ..clear()
      ..['steel'] = n(0.1);
    final b = held(
      buildFlowReport(s, c, 'player'),
    ).singleWhere((b) => b.kind == BottleneckKind.crewShortage);
    expect(b.runFraction, closeTo(0.5, 1e-12));
    expect(
      b.lostCreditsPerHour!.toDouble(),
      closeTo(0.32 * 0.5 * price(s, c, 'copper_ore').toDouble() * 3600, 1e-6),
    );
  });

  test('crew shortage counts what full staffing adds, not every link of a '
      'chain', () {
    // Two of three crew housed. Fully crewed, the mines make half as much
    // ore again and the smelter turns the extra iron ore into steel: the
    // iron ore is used up, so only the copper ore and the steel count, a
    // third of each at full rate.
    s.faction('player').baseCrew = 2;
    final b = held(
      buildFlowReport(s, c, 'player'),
    ).singleWhere((b) => b.kind == BottleneckKind.crewShortage);
    final perSec =
        0.32 * price(s, c, 'copper_ore').toDouble() +
        0.2 * price(s, c, 'steel').toDouble();
    expect(b.lostCreditsPerHour!.toDouble(), closeTo(perSec / 3 * 3600, 1e-6));
  });

  test('crew shortage loses nothing when no crewed building runs', () {
    // One crew housed for the smelter's two; it has no ore anyway.
    s.faction('player').baseCrew = 1;
    kora.stock['iron_ore'] = n(0);
    for (final b in kora.buildings) {
      b.crew = 0;
      if (b.defId == 'smelter') {
        b
          ..levels[UpgradeTrack.capacity] = 1
          ..crew = 2;
      }
    }
    final b = held(
      buildFlowReport(s, c, 'player'),
    ).singleWhere((b) => b.kind == BottleneckKind.crewShortage);
    expect(b.runFraction, closeTo(0.5, 1e-12));
    expect(b.lostCreditsPerHour, const BigNum.zero());
  });

  test('crew shortage sorts with the other bottlenecks by run fraction', () {
    // Two crew assigned, one supported. At crew efficiency 0.5 the smelter
    // wants 0.2 ore and gets 0.15; the iron mine is idle.
    s.faction('player').baseCrew = 1;
    engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0.15);
    final hollow = s.body('hollow_reach')..ownerId = 'player';
    hollow.buildings.add(BuildingState(id: 'x1', defId: 'smelter', crew: 0));
    final list = held(buildFlowReport(s, c, 'player'));
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
    expect(held(buildFlowReport(s, c, 'player')), isEmpty);
  });

  test('crew shortage counts crew as the sample tick started', () {
    // The habitat ran at 0 last step, so it houses no one yet; fed now, it
    // runs fully during the sample tick, which must not change the counts.
    s.faction('player').baseCrew = 2;
    kora.buildings.add(BuildingState(id: 'h1', defId: 'habitat', crew: 0));
    for (final id in ['food', 'water', 'oxygen']) {
      kora.stock[id] = n(10);
    }
    final b = held(
      buildFlowReport(s, c, 'player'),
    ).singleWhere((b) => b.kind == BottleneckKind.crewShortage);
    expect(
      b.message,
      'Your empire is short on crew: '
      'habitats and base crew support 2 of 3 assigned',
    );
    expect(b.runFraction, closeTo(2 / 3, 1e-12));
  });

  test('state and report agree on housing in the same tick', () {
    // Round-3 new-player bug 1: `state` showed one housing figure while
    // `report` showed the habitats running as they would the tick after,
    // and the two swapped every tick. Here the habitat's food comes from a
    // farm that shares the melter's water with an electrolyzer.
    s.faction('player').baseCrew = 2;
    kora.buildings
      ..clear()
      ..addAll([
        BuildingState(id: 'h1', defId: 'habitat', crew: 0)
          ..levels[UpgradeTrack.capacity] = 2,
        BuildingState(id: 'm1', defId: 'ice_melter', crew: 1)
          ..levels[UpgradeTrack.speed] = 5,
        BuildingState(id: 'e1', defId: 'electrolyzer', crew: 1)
          ..levels[UpgradeTrack.speed] = 5,
        BuildingState(id: 'f1', defId: 'farm', crew: 1),
      ]);
    kora.stock
      ..clear()
      ..['water_ice'] = n(1e5)
      ..['fertilizer'] = n(1e5)
      ..['food'] = n(2);
    engine.advance(s, 1800);
    final hab = kora.buildings.first;
    for (var i = 0; i < 4; i++) {
      final r = buildFlowReport(s, c, 'player');
      final shown = koraFlow(
        r,
      ).buildings.singleWhere((b) => b.buildingId == 'h1');
      expect(shown.runFraction, lessThan(1));
      expect(shown.runFraction, closeTo(hab.lastRunFraction, 1e-3));
      engine.advance(s, 60);
    }
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
      held(r).single.message,
      'Habitat on Kora is running at 50%: not enough Oxygen',
    );
  });

  group('steady rates come only from production', () {
    /// Kora presses plates; Brine and Hollow Reach are owned too, and steel
    /// moves between them on [legs] (from, to) with [ships] ships each.
    /// Kora's mines and smelter work only when [smelting]; every body
    /// starts with 2,000 steel.
    FlowReport loop(
      List<(String, String)> legs, {
      required int ships,
      bool smelting = false,
    }) {
      if (!smelting) {
        for (final b in kora.buildings) {
          b.crew = 0;
        }
      }
      kora.buildings.add(
        BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
      );
      for (final id in ['brine', 'hollow_reach']) {
        s.body(id).ownerId = 'player';
      }
      for (final id in ['kora', 'brine', 'hollow_reach']) {
        s.body(id).stock
          ..['steel'] = n(2000)
          ..['cargo_ship'] = n(ships);
      }
      for (final (from, to) in legs) {
        final r = engine.apply(
          s,
          CreateRouteCommand('player', from, to, 'steel', n(1000), ships),
        );
        expect(r, isA<CommandOk>(), reason: '$r');
      }
      return buildFlowReport(s, c, 'player');
    }

    for (final ships in [1, 5, 20]) {
      test('a route pair over a stock nothing makes gives nothing, with '
          '$ships ships each way', () {
        final r = loop([('kora', 'brine'), ('brine', 'kora')], ships: ships);
        expect(r.producedPerSec('hull_plate') > const BigNum.zero(), isTrue);
        expect(r.steadyProducedPerSec('hull_plate'), const BigNum.zero());
        expect(r.steadySurplusPerSec('steel'), const BigNum.zero());
      });

      test('a route pair where one side makes the input gives what that '
          'makes, with $ships ships each way', () {
        // The smelter makes 0.2 steel a second, so the press runs at
        // 0.2 / 0.375 of full: 0.2 / 3 plates a second.
        final r = loop(
          [('kora', 'brine'), ('brine', 'kora')],
          ships: ships,
          smelting: true,
        );
        expect(
          r.steadyProducedPerSec('hull_plate').toDouble(),
          closeTo(0.2 / 3, 0.2 / 3 * 0.01),
        );
        expect(r.steadySurplusPerSec('steel').toDouble(), closeTo(0, 1e-9));
      });
    }

    test('a three-body cycle over a stock nothing makes gives nothing', () {
      final r = loop([
        ('kora', 'brine'),
        ('brine', 'hollow_reach'),
        ('hollow_reach', 'kora'),
      ], ships: 5);
      expect(r.steadyProducedPerSec('hull_plate'), const BigNum.zero());
      expect(r.steadySurplusPerSec('steel'), const BigNum.zero());
    });

    test('a three-body cycle carries what one body makes', () {
      final r = loop(
        [
          ('kora', 'brine'),
          ('brine', 'hollow_reach'),
          ('hollow_reach', 'kora'),
        ],
        ships: 5,
        smelting: true,
      );
      expect(
        r.steadyProducedPerSec('hull_plate').toDouble(),
        closeTo(0.2 / 3, 0.2 / 3 * 0.01),
      );
    });
  });
}
