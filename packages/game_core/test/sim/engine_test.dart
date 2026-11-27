import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

String encode(GameState s) => jsonEncode(s.toJson());

/// 50 commands for the player, drawn from a fixed seed so every run issues
/// the same script. Many fail validation (unaffordable, no slot); that is
/// part of what must stay deterministic.
List<Command> scriptedCommands() {
  final rng = Rng(7);
  const ores = ['iron_ore', 'copper_ore', 'silicon'];
  const factories = ['smelter', 'wire_mill', 'wafer_fab', 'plate_press'];
  const sellable = ['iron_ore', 'copper_ore', 'steel'];
  String pick(List<String> xs) => xs[rng.nextInt(xs.length)];
  String building() => 'b${1 + rng.nextInt(10)}';
  return [
    SetAutoSellCommand('player', 'kora', 'steel', n(0)),
    SetAutoSellCommand('player', 'kora', 'copper_ore', n(100)),
    for (var i = 0; i < 48; i++)
      switch (rng.nextInt(7)) {
        0 => BuildCommand(
          'player',
          'kora',
          'mine',
          depositResourceId: pick(ores),
        ),
        1 => BuildCommand('player', 'kora', pick(factories)),
        2 => AssignCrewCommand('player', building(), rng.nextInt(3)),
        3 => UpgradeCommand(
          'player',
          building(),
          UpgradeTrack.values[rng.nextInt(3)],
        ),
        4 => SellCommand('player', 'kora', pick(sellable), n(50)),
        5 => SetAutoSellCommand(
          'player',
          'kora',
          pick(sellable),
          n(rng.nextInt(200)),
        ),
        _ => ClaimBodyCommand('player', 'hollow_reach', 'kora'),
      },
  ];
}

/// Every stock of every body, keyed `body/resource`.
Map<String, double> stocks(GameState s) => {
  for (final b in s.bodies)
    for (final e in b.stock.entries) '${b.id}/${e.key}': e.value.toDouble(),
};

/// The extractor that mines [resourceId] in [c].
String extractorFor(Content c, String resourceId) => c.buildings.values
    .firstWhere(
      (d) =>
          d.kind == BuildingKind.extractor && d.extracts.contains(resourceId),
    )
    .id;

/// Shipped content with every body owned by the player and every build slot
/// filled: an extractor per deposit, then factories in content order. All
/// buildings are fully crewed from a large base crew, and every body
/// auto-sells its surplus.
(GameEngine, GameState) fullEmpire() {
  final c = shippedContent();
  final e = GameEngine(c);
  final s = e.newGame(1);
  s.faction('player')
    ..credits = n(1e12)
    ..baseCrew = 10000;
  final factories = [
    for (final d in c.buildings.values)
      if (d.kind == BuildingKind.factory) d.id,
  ];
  for (final body in s.bodies) {
    body.ownerId = 'player';
    final slots = c.bodyTypes[body.typeId]!.buildSlots;
    for (final d in body.deposits) {
      if (body.buildings.length >= slots) break;
      e.apply(
        s,
        BuildCommand(
          'player',
          body.id,
          extractorFor(c, d.resourceId),
          depositResourceId: d.resourceId,
        ),
      );
    }
    var i = 0;
    while (body.buildings.length < slots) {
      final r = e.apply(
        s,
        BuildCommand('player', body.id, factories[i++ % factories.length]),
      );
      expect(r, isA<CommandOk>());
    }
    for (final b in body.buildings) {
      final r = e.apply(
        s,
        AssignCrewCommand('player', b.id, c.buildings[b.defId]!.crewSlots),
      );
      expect(r, isA<CommandOk>());
    }
    for (final id in c.resources.keys) {
      e.apply(s, SetAutoSellCommand('player', body.id, id, n(500)));
    }
  }
  return (e, s);
}

/// [fullEmpire] at speed level 50, with Kora's smelters and Hollow Reach's
/// iron mine idle so that Hollow Reach's smelters run on iron ore shipped
/// from Kora, and 50 cargo ships on Kora for the route.
(GameEngine, GameState) routeFedEmpire() {
  final (e, s) = fullEmpire();
  for (final b in s.bodies.expand((b) => b.buildings)) {
    b.levels[UpgradeTrack.speed] = 50;
  }
  for (final b in s.body('kora').buildings) {
    if (b.defId == 'smelter') b.crew = 0;
  }
  for (final b in s.body('hollow_reach').buildings) {
    if (b.depositResourceId == 'iron_ore') b.crew = 0;
  }
  s.body('kora').stock['cargo_ship'] = n(50);
  return (e, s);
}

void main() {
  late Content c;
  late GameEngine engine;

  setUp(() {
    c = shippedContent();
    engine = GameEngine(c);
  });

  test('newGame and apply delegate to state setup and commands', () {
    final s = engine.newGame(3);
    expect(encode(s), encode(newGameState(c, 3)));
    final r = engine.apply(
      s,
      const BuildCommand(
        'player',
        'kora',
        'mine',
        depositResourceId: 'silicon',
      ),
    );
    expect(r, isA<CommandOk>());
    expect(s.body('kora').buildings, hasLength(4));
  });

  test('determinism: same seed and script give identical saves', () {
    final script = scriptedCommands();
    String run() {
      final e = GameEngine(shippedContent());
      final s = e.newGame(42);
      var ok = 0;
      for (final cmd in script) {
        if (e.apply(s, cmd) is CommandOk) ok++;
        e.advance(s, 3600);
      }
      expect(ok, greaterThan(10), reason: 'script must change the game');
      expect(s.time, 50 * 3600);
      return encode(s);
    }

    expect(run(), run());
  });

  group('tick', () {
    test('runs production, logistics, market, then advances time', () {
      final s = engine.newGame(1);
      final kora = s.body('kora');
      s.body('hollow_reach').ownerId = 'player';
      kora.stock['cargo_ship'] = n(1);
      s
          .faction('player')
          .autoSell
          .add(
            AutoSellRule(
              bodyId: 'kora',
              resourceId: 'steel',
              keepAtLeast: n(0),
            ),
          );
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
      engine.tick(s, 10);
      expect(s.time, 10);
      // Production made 3.2 copper ore before logistics shipped 10 s of it.
      final sh = s.shipments.single;
      expect(sh.amount.toDouble(), closeTo(3.2, 1e-9));
      // Sent at time 0; Kora (orbit 2) to Hollow Reach (orbit 3): base
      // travel × 2.
      expect(sh.arriveAt, c.rules.baseTravelSeconds * 2);
      // Production made 2 steel before the market sold all of it at a hair
      // under its base price.
      expect(kora.stock['steel']!.isZero, isTrue);
      final steel = c.resources['steel']!.basePrice.toDouble();
      final credits = s.faction('player').credits.toDouble();
      expect(credits, closeTo(250 + 2 * steel, 1e-2));
      expect(credits, lessThan(250 + 2 * steel));
    });

    test('sends cargo before the market sells what is left', () {
      final s = engine.newGame(1);
      final kora = s.body('kora');
      s.body('hollow_reach').ownerId = 'player';
      kora.stock['cargo_ship'] = n(1);
      kora.stock['silicon'] = n(100);
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'silicon', n(0)));
      engine.apply(
        s,
        CreateRouteCommand(
          'player',
          'kora',
          'hollow_reach',
          'silicon',
          n(1),
          1,
        ),
      );
      engine.tick(s, 10);
      // Logistics took 10 s of cargo first; the market sold the other 90.
      expect(s.shipments.single.amount, n(10));
      expect(kora.stock['silicon'] ?? const BigNum.zero(), const BigNum.zero());
    });

    test('auto-sell keeping 0 never starves a route out of the same body', () {
      for (final step in [1.0, 60.0]) {
        final s = engine.newGame(1);
        final kora = s.body('kora');
        s.body('hollow_reach').ownerId = 'player';
        kora.stock['cargo_ship'] = n(1);
        // Kora's smelter idle: the iron mine's 0.4 a second is all surplus.
        engine.apply(s, const AssignCrewCommand('player', 'b3', 0));
        engine.apply(s, SetAutoSellCommand('player', 'kora', 'iron_ore', n(0)));
        engine.apply(
          s,
          CreateRouteCommand(
            'player',
            'kora',
            'hollow_reach',
            'iron_ore',
            n(0.3),
            1,
          ),
        );
        engine.advance(s, 600, maxStep: step);
        // The route sent its full 0.3 a second; auto-sell got the rest.
        final moved =
            (s.body('hollow_reach').stock['iron_ore'] ?? const BigNum.zero()) +
            s.shipments.fold(const BigNum.zero(), (t, sh) => t + sh.amount);
        expect(moved.toDouble(), closeTo(0.3 * 600, 1e-6), reason: '$step');
        expect(s.faction('player').salesRevenue['iron_ore'], isNotNull);
      }
    });

    test('at 1 s ticks, auto-selling a route-fed input keeps it for the '
        'factory until the next lot lands', () {
      final s = engine.newGame(1);
      s.faction('player').baseCrew = 100;
      final kora = s.body('kora');
      final reach = s.body('hollow_reach')..ownerId = 'player';
      kora.stock
        ..['cargo_ship'] = n(1)
        ..['iron_ore'] = n(0);
      engine.apply(s, const AssignCrewCommand('player', 'b3', 0));
      final smelter = engine.apply(
        s,
        const BuildCommand('player', 'hollow_reach', 'smelter'),
      );
      engine.apply(
        s,
        AssignCrewCommand('player', (smelter as CommandOk).createdId!, 1),
      );
      engine.apply(
        s,
        SetAutoSellCommand('player', 'hollow_reach', 'iron_ore', n(0)),
      );
      // The smelter's whole need, 0.4 iron ore a second, landing in lots
      // [RulesDef.shipmentMergeSeconds] apart.
      engine.apply(
        s,
        CreateRouteCommand(
          'player',
          'kora',
          'hollow_reach',
          'iron_ore',
          n(0.4),
          1,
        ),
      );
      engine.advance(s, 600, maxStep: 1);
      final before = reach.stock['steel'] ?? const BigNum.zero();
      engine.advance(s, 600, maxStep: 1);
      // At full rate it makes 0.2 steel a second.
      final made = (reach.stock['steel']! - before).toDouble();
      expect(made, greaterThan(0.95 * 0.2 * 600));
      expect(s.faction('player').salesRevenue['iron_ore'], isNull);
    });

    test('output past the storage cap is auto-sold, not wasted', () {
      final s = engine.newGame(1);
      final kora = s.body('kora');
      final cap = storageCap(s, c, kora);
      kora.stock['copper_ore'] = cap;
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', cap));
      final before = s.faction('player').credits;
      engine.tick(s, 60);
      expect(kora.wastedThisStep, isEmpty);
      expect(kora.stock['copper_ore'], cap);
      expect(s.faction('player').credits, greaterThan(before));
    });

    test('output past the storage cap with no buyer is wasted at the end', () {
      final s = engine.newGame(1);
      final kora = s.body('kora');
      final cap = storageCap(s, c, kora);
      kora.stock['copper_ore'] = cap;
      engine.tick(s, 60);
      expect(kora.stock['copper_ore'], cap);
      expect(kora.wastedThisStep['copper_ore']!.toDouble(), greaterThan(0));
    });

    test('rejects a step that is not finite and above zero', () {
      final s = engine.newGame(1);
      final before = encode(s);
      for (final dt in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => engine.tick(s, dt), throwsArgumentError, reason: '$dt');
      }
      expect(encode(s), before);
    });

    test('a shipment due at time + dt lands as the tick ends, usable at '
        'its arrival time', () {
      final s = engine.newGame(1);
      s.body('hollow_reach').ownerId = 'player';
      s.shipments.add(
        Shipment(
          routeId: 'gone',
          toBodyId: 'hollow_reach',
          resourceId: 'steel',
          amount: n(5),
          departAt: 0,
          arriveAt: 10,
          fromBodyId: 'kora',
          ownerId: 'player',
        ),
      );
      engine.tick(s, 5);
      expect(s.shipments, hasLength(1));
      engine.tick(s, 5);
      expect(s.time, 10);
      expect(s.shipments, isEmpty);
      expect(s.body('hollow_reach').stock['steel'], n(5));
    });

    test('ships moved are usable at the arrival time the reply gave', () {
      final s = engine.newGame(1);
      s.body('hollow_reach').ownerId = 'player';
      s.body('kora').stock['cargo_ship'] = n(2);
      final sent = engine.apply(
        s,
        const MoveShipsCommand('player', 'kora', 'hollow_reach', 2),
      );
      final arrive = ((sent as CommandOk).outcome! as ShipsSent).arriveAt;
      engine.advance(s, arrive - s.time);
      final r = engine.apply(
        s,
        CreateRouteCommand(
          'player',
          'hollow_reach',
          'kora',
          'iron_ore',
          n(1),
          2,
        ),
      );
      expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    });

    test('cargo that would pass the cap as a tick ends waits for the next '
        'tick, whose buildings can use it first', () {
      final s = engine.newGame(1);
      final reach = s.body('hollow_reach')..ownerId = 'player';
      final cap = storageCap(s, c, reach);
      reach.stock['iron_ore'] = cap - n(3);
      s.shipments.add(
        Shipment(
          routeId: 'gone',
          toBodyId: 'hollow_reach',
          resourceId: 'iron_ore',
          amount: n(10),
          departAt: 0,
          arriveAt: 10,
          fromBodyId: 'kora',
          ownerId: 'player',
        ),
      );
      engine.tick(s, 10);
      // What fits lands now; the rest lands at the start of the next tick.
      expect(reach.stock['iron_ore'], cap);
      expect(s.shipments.single.amount, n(7));
      expect(reach.wastedThisStep, isEmpty);
      engine.tick(s, 10);
      expect(s.shipments, isEmpty);
      expect(reach.stock['iron_ore'], cap);
      expect(reach.wastedThisStep['iron_ore'], n(7));
    });

    test('adds newly reached milestones for every condition kind', () {
      final s = engine.newGame(1);
      final player = s.faction('player');
      engine.tick(s, 1);
      expect(player.reachedMilestones, isEmpty);

      s.body('hollow_reach').ownerId = 'player';
      player
        ..lifetimeProduced['steel'] = n(30)
        ..lifetimeCredits = n(1e4);
      engine.tick(s, 1);
      expect(player.reachedMilestones, {
        'first_steel',
        'credits_10k',
        'own_2_bodies',
      });

      // Reached milestones stay reached when the condition lapses.
      s.body('hollow_reach').ownerId = null;
      engine.tick(s, 1);
      expect(player.reachedMilestones, contains('own_2_bodies'));
    });

    test('credits-earned and produced milestones survive spending and '
        'selling', () {
      final s = engine.newGame(1);
      final player = s.faction('player');
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
      // Every bit of steel is sold as it is made, so the stock never holds
      // 30, and the credits are spent as they come in.
      for (var i = 0; i < 200 && player.lifetimeCredits < n(1e4); i++) {
        engine.advance(s, 600);
        player.credits = n(0);
      }
      expect(s.body('kora').stock['steel'] ?? const BigNum.zero(), n(0));
      expect(
        player.reachedMilestones,
        containsAll(['first_steel', 'credits_10k']),
      );
    });

    test('stock and credits milestones read what is held now', () {
      final inline = Content(
        rules: c.rules,
        resources: c.resources,
        buildings: c.buildings,
        bodyTypes: c.bodyTypes,
        galaxy: c.galaxy,
        milestones: [
          MilestoneDef(
            id: 'hold_steel',
            name: 'Hold Steel',
            condition: StockCondition(resourceId: 'steel', amount: n(100)),
          ),
          MilestoneDef(
            id: 'hold_credits',
            name: 'Hold Credits',
            condition: CreditsCondition(amount: n(1e4)),
          ),
        ],
      );
      final e = GameEngine(inline);
      final s = e.newGame(1);
      final player = s.faction('player')..lifetimeCredits = n(1e9);
      s.body('kora').stock['steel'] = n(60);
      s.body('hollow_reach')
        ..ownerId = 'player'
        ..stock['steel'] = n(50);
      e.tick(s, 1);
      expect(player.reachedMilestones, {'hold_steel'});
      player.credits = n(1e4);
      e.tick(s, 1);
      expect(player.reachedMilestones, {'hold_steel', 'hold_credits'});
    });

    test('building-count milestones count the faction\'s buildings', () {
      final inline = Content(
        rules: c.rules,
        resources: c.resources,
        buildings: c.buildings,
        bodyTypes: c.bodyTypes,
        galaxy: c.galaxy,
        milestones: const [
          MilestoneDef(
            id: 'two_mines',
            name: 'Two Mines',
            condition: BuildingCountCondition(defId: 'mine', count: 2),
          ),
          MilestoneDef(
            id: 'three_mines',
            name: 'Three Mines',
            condition: BuildingCountCondition(defId: 'mine', count: 3),
          ),
        ],
      );
      final e = GameEngine(inline);
      final s = e.newGame(1);
      e.tick(s, 1);
      expect(s.faction('player').reachedMilestones, {'two_mines'});
    });
  });

  group('bottleneck history', () {
    SeenBottleneck? seen(GameState s, String buildingId) => s
        .faction('player')
        .seenBottlenecks
        .where((b) => b.buildingId == buildingId)
        .firstOrNull;

    test('a bottleneck keeps the time it was first seen while it lasts', () {
      final s = engine.newGame(1);
      engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
      engine.advance(s, 600);
      final mine = seen(s, 'b1')!;
      expect(mine.kind, 'noCrew');
      expect(mine.bodyId, 'kora');
      expect(mine.resourceId, isNull);
      expect(mine.firstSeenAt, 0);
      engine.advance(s, 3600);
      expect(seen(s, 'b1')!.firstSeenAt, 0);
      final neck = buildFlowReport(
        s,
        c,
        'player',
      ).bottlenecks.singleWhere((b) => b.buildingId == 'b1');
      expect(neck.firstSeenAt, 0);
    });

    test(
      'a bottleneck that clears is forgotten; when it returns it is new',
      () {
        final s = engine.newGame(1);
        engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
        engine.advance(s, 600);
        engine.apply(s, const AssignCrewCommand('player', 'b1', 1));
        engine.advance(s, 60);
        expect(seen(s, 'b1'), isNull);
        engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
        engine.advance(s, 60);
        expect(seen(s, 'b1')!.firstSeenAt, 660);
      },
    );

    test('a bottleneck the report finds first is new as of now', () {
      final s = engine.newGame(1);
      engine.advance(s, 120);
      engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
      final neck = buildFlowReport(
        s,
        c,
        'player',
      ).bottlenecks.singleWhere((b) => b.buildingId == 'b1');
      expect(neck.firstSeenAt, 120);
    });
  });

  group('advance', () {
    test('splits into maxStep steps with the remainder last', () {
      final s = engine.newGame(1);
      engine.advance(s, 150, maxStep: 60);
      expect(s.time, 150);
      // Same result as ticking 60, 60, 30 by hand.
      final byHand = engine.newGame(1);
      for (final dt in [60.0, 60.0, 30.0]) {
        engine.tick(byHand, dt);
      }
      expect(encode(s), encode(byHand));
    });

    test('an exact multiple of maxStep has no remainder step', () {
      final s = engine.newGame(1);
      engine.advance(s, 120, maxStep: 60);
      final byHand = engine.newGame(1);
      engine
        ..tick(byHand, 60)
        ..tick(byHand, 60);
      expect(encode(s), encode(byHand));
    });

    test('zero seconds does nothing; bad arguments throw', () {
      final s = engine.newGame(1);
      final before = encode(s);
      engine.advance(s, 0);
      expect(encode(s), before);
      expect(() => engine.advance(s, -1), throwsArgumentError);
      expect(() => engine.advance(s, 10, maxStep: 0), throwsArgumentError);
      expect(encode(s), before);
    });

    test('step invariance: maxStep 1 and 60 agree within 2%', () {
      for (final autoSell in [false, true]) {
        GameState run(double maxStep) {
          final s = engine.newGame(1);
          if (autoSell) {
            engine.apply(
              s,
              SetAutoSellCommand('player', 'kora', 'steel', n(0)),
            );
          }
          engine.advance(s, 3600, maxStep: maxStep);
          return s;
        }

        final fine = run(1);
        final coarse = run(60);
        final reason = autoSell ? 'with auto-sell' : 'starting setup';
        final cf = fine.faction('player').credits.toDouble();
        final cc = coarse.faction('player').credits.toDouble();
        expect(
          (cf - cc).abs(),
          lessThanOrEqualTo(0.02 * cf.abs()),
          reason: '$reason: credits $cf vs $cc',
        );
        final sf = stocks(fine);
        final sc = stocks(coarse);
        expect(sc.keys.toSet(), sf.keys.toSet(), reason: reason);
        for (final k in sf.keys) {
          final a = sf[k]!;
          final b = sc[k]!;
          final scale = a.abs() > b.abs() ? a.abs() : b.abs();
          expect(
            (a - b).abs(),
            lessThanOrEqualTo(0.02 * scale),
            reason: '$reason: $k $a vs $b',
          );
        }
      }
    });

    test('step invariance with a cycle\'s input auto-sold', () {
      // Auto-sell on water must leave the electrolyzer its input for the
      // next step, however long the step. The hydrogen furnace makes the
      // water and runs after the electrolyzer (the furnace-to-electrolyzer
      // edge of their cycle is the one recipe depth drops), so what it
      // makes is used only in the next step: only the step's kept demand
      // stops the market selling it first.
      GameState run(double maxStep) {
        final s = engine.newGame(1);
        final kora = s.body('kora');
        kora.buildings.removeWhere((b) => b.id != 'b1');
        kora.buildings.addAll([
          BuildingState(id: 'b90', defId: 'hydrogen_furnace', crew: 1),
          BuildingState(id: 'b91', defId: 'electrolyzer', crew: 1),
        ]);
        s.nextId = 100;
        kora.stock
          ..clear()
          ..['hydrogen'] = n(1000)
          ..['iron_ore'] = n(100);
        for (final id in ['water', 'steel', 'oxygen']) {
          engine.apply(s, SetAutoSellCommand('player', 'kora', id, n(0)));
        }
        engine.advance(s, 1800, maxStep: maxStep);
        return s;
      }

      final fine = run(1);
      final coarse = run(60);
      final oxygen = <double>[];
      for (final s in [fine, coarse]) {
        final electrolyzer = s.body('kora').buildings.last;
        // The furnace makes 1 water per 8 s; the electrolyzer wants 2 per
        // 6 s.
        expect(electrolyzer.lastRunFraction, closeTo(0.375, 1e-9));
        oxygen.add(s.faction('player').lifetimeProduced['oxygen']!.toDouble());
      }
      // The water lands one step late, so the runs differ by at most one
      // coarse step of oxygen: 60 s at 0.375 of 1 per 6 s.
      expect((oxygen[0] - oxygen[1]).abs(), lessThanOrEqualTo(5 + 1e-6));
      final cf = fine.faction('player').credits.toDouble();
      final cc = coarse.faction('player').credits.toDouble();
      expect(
        (cf - cc).abs(),
        lessThanOrEqualTo(0.02 * cf),
        reason: '$cf vs $cc',
      );
    });

    test('30-day jump finishes with finite, non-negative stocks', () {
      final (e, s) = fullEmpire();
      e.advance(s, 30 * 86400);
      expect(s.time, 30 * 86400);
      for (final f in s.factions) {
        expect(f.credits.toDouble().isFinite, isTrue);
        expect(f.credits.isNegative, isFalse);
      }
      for (final b in s.bodies) {
        for (final MapEntry(key: id, value: v) in b.stock.entries) {
          expect(v.toDouble().isFinite, isTrue, reason: '${b.id}/$id');
          expect(v.isNegative, isFalse, reason: '${b.id}/$id');
        }
      }
    });
  });

  group('catchUpOffline', () {
    test('caps at offlineCapSeconds by default', () {
      final s = engine.newGame(1);
      final sum = engine.catchUpOffline(s, 100000);
      expect(sum.secondsAway, 100000);
      expect(sum.secondsSimulated, 43200);
      expect(s.time, 43200);
    });

    test('a capped return says so in its headline', () {
      final s = engine.newGame(1);
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      // Away 4 days 2 hours; the base cap counts 12 h of it.
      final sum = engine.catchUpOffline(s, 4 * 86400 + 2 * 3600);
      expect(sum.capped, isTrue);
      expect(sum.capSeconds, 43200);
      expect(sum.secondsSimulated, 43200);
      expect(sum.creditsGained > const BigNum.zero(), isTrue);
      expect(
        sum.headline,
        'Away 4d 2h; 12h counted (cap); '
        '+${formatNumber(sum.creditsGained)} credits',
      );
    });

    test('an uncapped return has a shorter headline', () {
      final s = engine.newGame(1);
      final sum = engine.catchUpOffline(s, 3 * 3600);
      expect(sum.capped, isFalse);
      expect(sum.capSeconds, 43200);
      expect(
        sum.headline,
        'Away 3h; +${formatNumber(sum.creditsGained)} credits',
      );
      // Exactly the cap loses nothing, so it is not capped; a fall in
      // credits shows with a minus sign.
      final t = engine.newGame(1);
      t.faction('player').credits = n(1000);
      t.body('kora').stock['iron_ore'] = n(0);
      t.body('kora').buildings.clear();
      t.routes.clear();
      final flat = engine.catchUpOffline(t, 43200);
      expect(flat.capped, isFalse);
      expect(flat.headline, 'Away 12h; +0 credits');
      final down = OfflineSummary(
        awayFrom: 0,
        secondsSimulated: 60,
        secondsAway: 60,
        capSeconds: 43200,
        stockGained: const {},
        creditsGained: n(-1500),
        totalWasted: const BigNum.zero(),
        milestonesReached: const [],
        topBottlenecks: const [],
        projectsCompleted: const [],
      );
      expect(down.headline, 'Away 1m; -1.5K credits');
    });

    test('a short absence is simulated in full; capSeconds overrides', () {
      final s = engine.newGame(1);
      expect(engine.catchUpOffline(s, 500).secondsSimulated, 500);
      expect(s.time, 500);
      final t = engine.newGame(1);
      expect(
        engine.catchUpOffline(t, 100000, capSeconds: 86400).secondsSimulated,
        86400,
      );
      expect(t.time, 86400);
    });

    test('negative time away simulates nothing', () {
      final s = engine.newGame(1);
      final before = encode(s);
      final sum = engine.catchUpOffline(s, -30);
      expect(sum.secondsSimulated, 0);
      expect(encode(s), before);
    });

    test('summarizes stock, credits, milestones and bottlenecks', () {
      final s = engine.newGame(1);
      engine.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      // Leave the iron mine unstaffed so the smelter runs dry.
      engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
      final sum = engine.catchUpOffline(s, 3600);

      // The smelter burns the 40 starting iron ore into 20 steel; copper ore
      // is sold as it is mined, so its stock does not change.
      expect(sum.stockGained['iron_ore']!.toDouble(), closeTo(-40, 1e-6));
      expect(sum.stockGained['steel']!.toDouble(), closeTo(20, 1e-6));
      expect(sum.stockGained.containsKey('copper_ore'), isFalse);
      expect(sum.creditsGained.toDouble(), greaterThan(1000));
      expect(
        sum.creditsGained.toDouble(),
        closeTo(s.faction('player').credits.toDouble() - 250, 1e-6),
      );
      expect(sum.milestonesReached, isEmpty);
      // The starved smelter's lost steel has a price; the idle mine's loss
      // is not estimated, so it comes after.
      expect(sum.topBottlenecks.map((b) => b.message), [
        'Smelter on Kora is running at 0%: not enough Iron Ore',
        'Mine on Kora has no crew',
      ]);
    });

    test('totals the units wasted while away', () {
      final s = engine.newGame(1);
      expect(engine.catchUpOffline(s, 600).totalWasted.isZero, isTrue);
      // Copper ore is full; an hour of 0.32 a second is lost to the cap.
      s.body('kora').stock['copper_ore'] = storageCap(s, c, s.body('kora'));
      final sum = engine.catchUpOffline(s, 3600);
      expect(sum.totalWasted.toDouble(), closeTo(0.32 * 3600, 1e-6));
    });

    test('stock moved between owned bodies leaves no float residue', () {
      final s = engine.newGame(1);
      final kora = s.body('kora');
      for (final b in kora.buildings) {
        b.crew = 0;
      }
      kora.stock
        ..clear()
        ..['iron_ore'] = n(3 * 0.37)
        ..['cargo_ship'] = n(1);
      s.body('hollow_reach')
        ..ownerId = 'player'
        ..stock['iron_ore'] = n(3 * 0.11);
      engine.apply(
        s,
        CreateRouteCommand(
          'player',
          'kora',
          'hollow_reach',
          'iron_ore',
          n(0.0021),
          1,
        ),
      );
      final sum = engine.catchUpOffline(s, 3600);
      // Every unit landed; the totals before and after differ only in the
      // last bits of a double.
      expect(s.shipments, isEmpty);
      expect(sum.stockGained, isEmpty);
    });

    test('lists milestones reached while away, in content order', () {
      final s = engine.newGame(1);
      s.faction('player')
        ..reachedMilestones.add('own_2_bodies')
        ..lifetimeCredits = n(1e4);
      final sum = engine.catchUpOffline(s, 3600);
      expect(sum.milestonesReached, ['first_steel', 'credits_10k']);
    });

    test('top bottlenecks rank by the credits they lose an hour', () {
      final s = engine.newGame(1);
      // An idle iron mine starves the smelter of ore, and Kora's copper ore
      // store fills and wastes all the mine makes.
      engine.apply(s, const AssignCrewCommand('player', 'b1', 0));
      final sum = engine.catchUpOffline(s, 3 * 3600);
      expect(sum.awayFrom, 0);
      expect(sum.topBottlenecks.map((b) => b.kind), [
        BottleneckKind.input,
        BottleneckKind.storageFull,
        BottleneckKind.noCrew,
      ]);
      // The smelter's lost 0.2 steel a second, then 0.32 copper ore a
      // second wasted, each at its current price; no estimate for the idle
      // mine.
      final steel = price(s, c, 'steel').toDouble();
      final ore = price(s, c, 'copper_ore').toDouble();
      final lost = [
        for (final b in sum.topBottlenecks) b.lostCreditsPerHour?.toDouble(),
      ];
      expect(lost[0], closeTo(0.2 * steel * 3600, 1e-6));
      expect(lost[1], closeTo(0.32 * ore * 3600, 1e-6));
      expect(lost[2], isNull);
      // The report itself still sorts by run fraction, then report order.
      final necks = buildFlowReport(s, c, 'player').bottlenecks;
      expect(necks.first.kind, BottleneckKind.noCrew);
    });

    test('top bottlenecks are at most three', () {
      final (e, s) = fullEmpire();
      for (final b in s.bodies.expand((b) => b.buildings)) {
        b.crew = 0;
      }
      final sum = e.catchUpOffline(s, 60);
      expect(sum.topBottlenecks, hasLength(3));
    });

    test('one-minute steps earn what one-second steps do', () {
      // A running empire whose auto-sell keeps stock just under the cap, so
      // a 60 s step makes far more than the room left before selling.
      final (e, s) = fullEmpire();
      for (final b in s.bodies.expand((b) => b.buildings)) {
        b.levels[UpgradeTrack.speed] = 25; // 1.1^25 × 2: about 22× output
      }
      e.advance(s, 3600);
      for (final rule in s.faction('player').autoSell) {
        rule.keepAtLeast = storageCap(s, c, s.body(rule.bodyId)).mulDouble(0.9);
      }
      BigNum earned(double step) {
        final t = s.copy();
        e.advance(t, 6 * 3600, maxStep: step);
        return t.faction('player').credits - s.faction('player').credits;
      }

      final live = earned(1).toDouble();
      final offline = earned(60).toDouble();
      expect(live, greaterThan(0));
      expect(offline, closeTo(live, live * 0.02));
    });

    test('a fast chain fed by a route earns the same at 60 s steps', () {
      // Kora ships iron ore to Hollow Reach's smelters at 100 a second:
      // 6000 a minute, far more than Hollow Reach stores. Cargo that lands
      // is used in the tick it lands, so long steps lose nothing to it.
      final (e, s) = routeFedEmpire();
      e.apply(
        s,
        CreateRouteCommand(
          'player',
          'kora',
          'hollow_reach',
          'iron_ore',
          n(100),
          50,
        ),
      );
      e.advance(s, 600, maxStep: 1);
      BigNum earned(double step) {
        final t = s.copy();
        e.advance(t, 6 * 3600, maxStep: step);
        return t.faction('player').credits - s.faction('player').credits;
      }

      final live = earned(1).toDouble();
      final coarse = earned(60).toDouble();
      expect(live, greaterThan(0));
      expect(coarse, closeTo(live, live * 0.02));
    });

    test('catch-up ticks like advance', () {
      final (e, s) = fullEmpire();
      final away = s.copy();
      e.catchUpOffline(away, 3600);
      final live = s.copy();
      e.advance(live, 3600);
      expect(encode(away), encode(live));
    });

    // Wall-clock tests, tagged `perf` (`dart test -x perf` leaves them
    // out). CI runs them with the rest; the 1 s bounds leave room for a
    // slow shared runner.
    test(
      'performance: 12 h of a fast 40-building empire under 1 s',
      tags: ['perf'],
      () {
        // A late-game worst case: every slot filled, speed level 50, and a
        // route moving 100 units a second.
        final (e, s) = routeFedEmpire();
        e
          ..apply(
            s,
            CreateRouteCommand(
              'player',
              'kora',
              'hollow_reach',
              'iron_ore',
              n(100),
              50,
            ),
          )
          ..advance(s, 600);
        // Warm up the VM before timing.
        e.catchUpOffline(s.copy(), 3600);
        final watch = Stopwatch()..start();
        final sum = e.catchUpOffline(s, 43200);
        watch.stop();
        expect(sum.secondsSimulated, 43200);
        expect(watch.elapsedMilliseconds, lessThan(1000));
      },
    );

    test(
      'performance: 24 h of a 40-building empire in under 1 s',
      tags: ['perf'],
      () {
        final (e, s) = fullEmpire();
        final count = s.bodies.fold(0, (sum, b) => sum + b.buildings.length);
        // Every build slot in the shipped galaxy is filled.
        expect(count, greaterThanOrEqualTo(40));
        final watch = Stopwatch()..start();
        final sum = e.catchUpOffline(s, 86400, capSeconds: 86400);
        watch.stop();
        expect(sum.secondsSimulated, 86400);
        expect(watch.elapsedMilliseconds, lessThan(1000));
      },
    );
  });
}
