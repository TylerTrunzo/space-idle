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

    test('a shipment due at time + dt lands on the next tick', () {
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
      engine.tick(s, 10);
      expect(s.shipments, hasLength(1));
      engine.tick(s, 10);
      expect(s.shipments, isEmpty);
      expect(s.body('hollow_reach').stock['steel'], n(5));
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

    test('step invariance with the smelter fed from auto-sold ore', () {
      // Auto-sell on iron ore must leave the smelter its input for the
      // next step, however long the step.
      GameState run(double maxStep) {
        final s = engine.newGame(1);
        engine
          ..apply(s, SetAutoSellCommand('player', 'kora', 'iron_ore', n(0)))
          ..apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)))
          ..advance(s, 3600, maxStep: maxStep);
        return s;
      }

      final fine = run(1);
      final coarse = run(60);
      final cf = fine.faction('player').credits.toDouble();
      final cc = coarse.faction('player').credits.toDouble();
      expect(
        (cf - cc).abs(),
        lessThanOrEqualTo(0.02 * cf),
        reason: '$cf vs $cc',
      );
      for (final s in [fine, coarse]) {
        final smelter = s
            .body('kora')
            .buildings
            .firstWhere((b) => b.defId == 'smelter');
        expect(smelter.lastRunFraction, 1);
      }
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
      expect(sum.topBottlenecks.map((b) => b.message), [
        'Mine on Kora has no crew',
        'Smelter on Kora is running at 0%: not enough Iron Ore',
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

    test('performance: 12 h of a fast 40-building empire under 300 ms', () {
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
      expect(watch.elapsedMilliseconds, lessThan(300));
    });

    test('performance: 24 h of a 40-building empire in under 1 s', () {
      final (e, s) = fullEmpire();
      final count = s.bodies.fold(0, (sum, b) => sum + b.buildings.length);
      // Every build slot in the shipped galaxy is filled.
      expect(count, greaterThanOrEqualTo(40));
      final watch = Stopwatch()..start();
      final sum = e.catchUpOffline(s, 86400, capSeconds: 86400);
      watch.stop();
      expect(sum.secondsSimulated, 86400);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
