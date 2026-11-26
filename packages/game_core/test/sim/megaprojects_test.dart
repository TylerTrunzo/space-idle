import 'dart:convert';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

String encode(GameState s) => jsonEncode(s.toJson());

/// The shipped Orbital Station entry, as a fresh mutable JSON map.
Map<String, Object?> stationJson() =>
    ((shippedBundle()['megaprojects']! as List).single as Map)
        .cast<String, Object?>();

/// The shipped content with its megaprojects file replaced by [megaprojects].
Content contentWithMegaprojects(List<Map<String, Object?>> megaprojects) {
  final b = shippedBundle()..['megaprojects'] = megaprojects;
  return switch (Content.fromBundle(b)) {
    ContentOk(:final content) => content,
    ContentInvalid(:final errors) => throw StateError('$errors'),
  };
}

/// The shipped content with one megaproject `boost` that gives [bonuses]
/// per level, next to the Orbital Station.
Content contentWithBonuses(List<Map<String, Object?>> bonuses) =>
    contentWithMegaprojects([
      stationJson(),
      {
        ...stationJson(),
        'id': 'boost',
        'name': 'Boost',
        'bonusesPerLevel': bonuses,
      },
    ]);

void main() {
  final content = shippedContent();
  final e = GameEngine(content);
  final station = content.megaprojects['orbital_station']!;
  const start = StartMegaprojectStageCommand(
    'player',
    'orbital_station',
    'kora',
  );

  /// A new game whose player has a billion credits.
  GameState rich() => e.newGame(1)..faction('player').credits = n(1e9);

  /// [rich], with the goods for the next Orbital Station stage on Kora.
  GameState stocked() {
    final s = rich();
    final level = s.faction('player').megaprojectLevels['orbital_station'] ?? 0;
    for (final MapEntry(:key, :value) in megaprojectCost(
      content,
      station,
      level,
    ).entries) {
      if (key != 'credits') s.body('kora').stock[key] = value;
    }
    return s;
  }

  String? ok(GameState s, Command cmd, {GameEngine? using}) {
    final r = (using ?? e).apply(s, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    return (r as CommandOk).createdId;
  }

  String fails(
    GameState s,
    Command cmd,
    CommandError error, {
    GameEngine? using,
  }) {
    final before = encode(s);
    final r = (using ?? e).apply(s, cmd);
    expect(r, isA<CommandFailed>().having((f) => f.error, 'error', error));
    expect(encode(s), before);
    return (r as CommandFailed).message;
  }

  group('the shipped Orbital Station', () {
    test('loads with its bonuses and timings', () {
      expect(content.megaprojects.keys, ['orbital_station']);
      expect(station.name, 'Orbital Station');
      expect(station.hostBodyType, isNull);
      expect(station.costGrowth, 3);
      expect(station.stageSeconds, 7200);
      expect(station.stageSecondsGrowth, 1.15);
      expect(
        [for (final b in station.bonusesPerLevel) (b.kind, b.amount)],
        [
          (BonusKind.storagePercent, 10),
          (BonusKind.housingPercent, 5),
          (BonusKind.offlineCapSeconds, 3600),
          (BonusKind.marketDepthPercent, 25),
        ],
      );
    });

    test('costs tier 2-3 goods from every chain, plus credits', () {
      expect(station.baseCost.keys, [
        'credits',
        'station_segment',
        'survey_drone',
        'reactor_core',
        'hull_plate',
      ]);
      for (final id in station.baseCost.keys) {
        if (id == 'credits') continue;
        expect(content.resources[id]!.tier, inInclusiveRange(2, 3));
      }
    });
  });

  group('costs', () {
    test('grow ×3 a level', () {
      final base = megaprojectCost(content, station, 0);
      expect(base, station.baseCost);
      for (final level in [1, 2, 5]) {
        final cost = megaprojectCost(content, station, level);
        expect(cost.keys, base.keys);
        for (final MapEntry(:key, :value) in cost.entries) {
          final want = base[key]!.toDouble() * math.pow(3, level);
          expect(value.toDouble(), closeTo(want, want * 1e-12), reason: key);
        }
      }
    });

    test('a level-50 cost and its bonuses are finite', () {
      final cost = megaprojectCost(content, station, 50);
      for (final v in cost.values) {
        expect(v.toDouble().isFinite, isTrue);
        expect(v > const BigNum.zero(), isTrue);
      }
      expect(
        cost['hull_plate']! >
            megaprojectCost(content, station, 49)['hull_plate']!,
        isTrue,
      );
      // Past any double, BigNum still holds the cost.
      final huge = megaprojectCost(content, station, 1000)['hull_plate']!;
      expect(huge > cost['hull_plate']!, isTrue);
      expect(huge.toJson(), isNot(contains('Infinity')));

      final s = rich();
      s.faction('player').megaprojectLevels['orbital_station'] = 50;
      final b = bonusesFor(s, content, 'player');
      expect(b.storagePercent, 500);
      expect(b.housingPercent, 250);
      expect(b.offlineCapSeconds, 180000);
      expect(storageCap(s, content, s.body('kora')).toDouble(), 6000);
    });

    test('stage seconds grow ×1.15 a level, capped at 6 h', () {
      expect(megaprojectStageSeconds(station, 0), 7200);
      expect(megaprojectStageSeconds(station, 1), closeTo(8280, 1e-9));
      expect(megaprojectStageSeconds(station, 7), closeTo(7200 * 2.66002, 1));
      expect(megaprojectStageSeconds(station, 8), 21600);
      expect(megaprojectStageSeconds(station, 1000), 21600);
    });
  });

  group('starting a stage', () {
    test('takes the level cost from the body and credits', () {
      final s = stocked();
      final id = ok(s, start);
      expect(id, startsWith('p'));
      final kora = s.body('kora');
      for (final id in station.baseCost.keys) {
        if (id != 'credits') expect(kora.stock[id], const BigNum.zero());
      }
      expect(
        s.faction('player').credits,
        n(1e9) - megaprojectCost(content, station, 0)['credits']!,
      );
      final p = e.projectsFor(s, 'player').single;
      expect(p.kind, ProjectKind.megaprojectStage);
      expect(p.targetId, 'orbital_station');
      expect(p.finishAt, 7200);
      expect(projectTargetName(s, content, p), 'Orbital Station');
    });

    test('fails without the goods, and changes nothing', () {
      final s = stocked()..body('kora').stock['reactor_core'] = n(9);
      final msg = fails(s, start, CommandError.cannotAfford);
      expect(msg, contains('Reactor Core on Kora'));
      final poor = stocked()..faction('player').credits = n(1000);
      fails(poor, start, CommandError.cannotAfford);
    });

    test('a second stage of the same megaproject is in progress', () {
      final s = stocked();
      ok(s, start);
      for (final id in station.baseCost.keys) {
        if (id != 'credits') s.body('kora').stock[id] = n(1e6);
      }
      final msg = fails(s, start, CommandError.projectInProgress);
      expect(msg, contains('Orbital Station'));
    });

    test('other checks', () {
      final s = stocked();
      fails(
        s,
        const StartMegaprojectStageCommand('player', 'dyson', 'kora'),
        CommandError.unknownDef,
      );
      fails(
        s,
        const StartMegaprojectStageCommand('player', 'orbital_station', 'x'),
        CommandError.unknownBody,
      );
      fails(
        s,
        const StartMegaprojectStageCommand(
          'player',
          'orbital_station',
          'brine',
        ),
        CommandError.notOwner,
      );
      s.faction('player').megaprojectLevels['orbital_station'] =
          SaveCodec.maxMegaprojectLevel;
      fails(s, start, CommandError.invalidAmount);
    });

    test('a megaproject with a host body type needs a body of it', () {
      final c = contentWithMegaprojects([
        {...stationJson(), 'hostBodyType': 'gas_giant'},
      ]);
      final hosted = GameEngine(c);
      final s = stocked();
      final msg = fails(s, start, CommandError.wrongBodyType, using: hosted);
      expect(msg, contains('Gas Giant'));
    });

    test('round-trips as JSON', () {
      final back = Command.fromJson(
        jsonDecode(jsonEncode(start.toJson())) as Map<String, Object?>,
      );
      expect(back, isA<StartMegaprojectStageCommand>());
      expect(back.toJson(), {
        'cmd': 'startMegaprojectStage',
        'factionId': 'player',
        'megaprojectId': 'orbital_station',
        'bodyId': 'kora',
      });
    });
  });

  group('deliveries', () {
    /// [rich], with Hollow Reach the player's too and no goods anywhere.
    GameState twoBodies() {
      final s = rich();
      s.body('hollow_reach').ownerId = 'player';
      return s;
    }

    /// Level 0's cost, times [share], goods only.
    Map<String, BigNum> goods([double share = 1]) => {
      for (final MapEntry(:key, :value) in megaprojectCost(
        content,
        station,
        0,
      ).entries)
        if (key != 'credits') key: value.mulDouble(share),
    };

    BigNum credits0() => megaprojectCost(content, station, 0)['credits']!;

    DeliverToMegaprojectCommand deliver(
      String bodyId,
      Map<String, BigNum> amounts,
    ) => DeliverToMegaprojectCommand(
      'player',
      'orbital_station',
      bodyId,
      amounts,
    );

    Map<String, BigNum> progress(GameState s) =>
        s.faction('player').megaprojectProgress['orbital_station'] ?? {};

    test('partial deliveries from two bodies complete a stage', () {
      final s = twoBodies();
      final half = goods(0.5);
      s.body('kora').stock.addAll(half);
      s.body('hollow_reach').stock.addAll(half);

      expect(ok(s, deliver('kora', half)), isNull);
      expect(s.projects, isEmpty);
      expect(progress(s), half);
      for (final id in half.keys) {
        expect(s.body('kora').stock[id], const BigNum.zero());
      }
      expect(megaprojectRemaining(s, content, 'player', station), {
        'credits': credits0(),
        ...half,
      });

      expect(ok(s, deliver('hollow_reach', half)), isNull);
      expect(s.projects, isEmpty, reason: 'credits are still owed');
      final id = ok(s, deliver('kora', {'credits': credits0()}));
      expect(id, startsWith('p'));
      final p = e.projectsFor(s, 'player').single;
      expect(
        (p.id, p.kind, p.targetId),
        (id, ProjectKind.megaprojectStage, 'orbital_station'),
      );
      expect(s.faction('player').credits, n(1e9) - credits0());
      // The delivered goods are the stage's now; nothing is left owed.
      expect(s.faction('player').megaprojectProgress, isEmpty);
      e.advance(s, 7300);
      expect(s.faction('player').megaprojectLevels['orbital_station'], 1);
    });

    test('over-delivery is clamped to what the stage still needs', () {
      final s = twoBodies();
      final kora = s.body('kora')..stock.addAll(goods(3));
      ok(s, deliver('kora', goods(0.25)));
      ok(s, deliver('kora', {...goods(2), 'credits': n(5e8)}));
      // All of it delivered: the stage took exactly its cost.
      for (final MapEntry(:key, :value) in goods(2).entries) {
        expect(kora.stock[key], value, reason: key);
      }
      expect(s.faction('player').credits, n(1e9) - credits0());
      expect(e.projectsFor(s, 'player'), hasLength(1));
    });

    test('a delivery is clamped to the stock and credits held', () {
      final s = twoBodies();
      s.faction('player').credits = n(1000);
      s.body('kora').stock['hull_plate'] = n(5);
      ok(s, deliver('kora', {'hull_plate': n(50), 'credits': n(5000)}));
      expect(progress(s), {'hull_plate': n(5), 'credits': n(1000)});
      expect(s.body('kora').stock['hull_plate'], const BigNum.zero());
      expect(s.faction('player').credits, const BigNum.zero());
    });

    test('the timer starts on the final delivery', () {
      final s = twoBodies();
      s.body('kora').stock.addAll(goods());
      ok(s, deliver('kora', goods(0.5)));
      e.advance(s, 1000);
      expect(s.projects, isEmpty);
      final now = s.time;
      ok(s, deliver('kora', {...goods(), 'credits': credits0()}));
      final p = e.projectsFor(s, 'player').single;
      expect(p.startedAt, now);
      expect(p.finishAt, now + megaprojectStageSeconds(station, 0));
    });

    test('starting a stage delivers what is still owed from one body', () {
      final s = twoBodies();
      s.body('hollow_reach').stock.addAll(goods(0.5));
      s.body('kora').stock.addAll(goods(0.5));
      ok(s, deliver('hollow_reach', goods(0.5)));
      // Kora alone holds only half the cost, which is what is left.
      expect(ok(s, start), startsWith('p'));
      for (final id in goods().keys) {
        expect(s.body('kora').stock[id], const BigNum.zero(), reason: id);
      }
      expect(s.faction('player').megaprojectProgress, isEmpty);

      // Short of what is owed, it fails and changes nothing.
      final short = twoBodies();
      short.body('kora').stock.addAll(goods(0.5));
      ok(short, deliver('kora', goods(0.25)));
      final msg = fails(short, start, CommandError.cannotAfford);
      expect(msg, contains('on Kora'));
    });

    test('progress survives save/load and copy()', () {
      final s = twoBodies();
      s.body('kora').stock.addAll(goods());
      ok(s, deliver('kora', {...goods(0.5), 'credits': n(10)}));
      final loaded =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      final copied = s.copy();
      expect(encode(loaded), encode(s));
      expect(encode(copied), encode(s));
      expect(progress(loaded), progress(s));
      copied
          .faction('player')
          .megaprojectProgress['orbital_station']!['hull_plate'] = n(
        1,
      );
      expect(progress(s)['hull_plate'], goods(0.5)['hull_plate']);
      for (final x in [s, loaded]) {
        ok(x, deliver('kora', {...goods(), 'credits': credits0()}));
        e.advance(x, 7300);
      }
      expect(loaded.faction('player').megaprojectLevels['orbital_station'], 1);
      expect(encode(loaded), encode(s));
    });

    test('a save without progress loads with none', () {
      final m = e.newGame(1).toJson();
      for (final f in (m['factions']! as List).cast<Map<String, Object?>>()) {
        f.remove('megaprojectProgress');
      }
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      expect(
        (r as SaveOk).state.faction('player').megaprojectProgress,
        isEmpty,
      );
    });

    test('failures leave the state unchanged', () {
      final s = twoBodies();
      s.body('kora').stock.addAll(goods());
      fails(
        s,
        DeliverToMegaprojectCommand('player', 'dyson', 'kora', goods()),
        CommandError.unknownDef,
      );
      fails(s, deliver('x', goods()), CommandError.unknownBody);
      fails(s, deliver('brine', goods()), CommandError.notOwner);
      fails(s, deliver('kora', {}), CommandError.invalidAmount);
      fails(
        s,
        deliver('kora', {'hull_plate': n(0)}),
        CommandError.invalidAmount,
      );
      fails(
        s,
        deliver('kora', {'hull_plate': n(-1)}),
        CommandError.invalidAmount,
      );
      fails(s, deliver('kora', {'unobtanium': n(1)}), CommandError.unknownDef);
      expect(
        fails(
          s,
          deliver('kora', {'iron_ore': n(1)}),
          CommandError.invalidAmount,
        ),
        contains('Iron Ore'),
      );
      // Nothing of it held.
      expect(
        fails(
          s,
          deliver('hollow_reach', {'hull_plate': n(1)}),
          CommandError.cannotAfford,
        ),
        contains('Hollow Reach'),
      );
      // Already delivered in full.
      ok(s, deliver('kora', {'hull_plate': goods()['hull_plate']!}));
      expect(
        fails(
          s,
          deliver('kora', {'hull_plate': n(1)}),
          CommandError.invalidAmount,
        ),
        contains('Hull Plate'),
      );
      // A stage under way takes no deliveries.
      ok(s, deliver('kora', {...goods(), 'credits': credits0()}));
      s.body('kora').stock.addAll(goods());
      fails(s, deliver('kora', goods()), CommandError.projectInProgress);
      final top = twoBodies()..body('kora').stock.addAll(goods());
      top.faction('player').megaprojectLevels['orbital_station'] =
          SaveCodec.maxMegaprojectLevel;
      fails(top, deliver('kora', goods()), CommandError.invalidAmount);
    });

    test('a megaproject with a host body type needs one owned', () {
      final c = contentWithMegaprojects([
        {...stationJson(), 'hostBodyType': 'gas_giant'},
      ]);
      final hosted = GameEngine(c);
      final s = twoBodies()..body('kora').stock.addAll(goods());
      final msg = fails(
        s,
        deliver('kora', goods()),
        CommandError.wrongBodyType,
        using: hosted,
      );
      expect(msg, contains('Gas Giant'));
      // Owning one, any owned body may deliver.
      s.body('vastmere').ownerId = 'player';
      ok(s, deliver('kora', goods()), using: hosted);
    });

    test('round-trips as JSON', () {
      final cmd = deliver('kora', {'hull_plate': n(12), 'credits': n(5e3)});
      final back = Command.fromJson(
        jsonDecode(jsonEncode(cmd.toJson())) as Map<String, Object?>,
      );
      expect(back.toJson(), {
        'cmd': 'deliverToMegaproject',
        'factionId': 'player',
        'megaprojectId': 'orbital_station',
        'bodyId': 'kora',
        'amounts': {'hull_plate': '1.2e1', 'credits': '5e3'},
      });
      expect(
        () => Command.fromJson({
          'cmd': 'deliverToMegaproject',
          'factionId': 'player',
          'megaprojectId': 'orbital_station',
          'bodyId': 'kora',
          'amounts': {'hull_plate': 12},
        }),
        throwsFormatException,
      );
    });
  });

  group('completion', () {
    test('raises the level once, and the next stage costs more', () {
      final s = stocked();
      ok(s, start);
      e.advance(s, 7200);
      expect(s.faction('player').megaprojectLevels['orbital_station'], isNull);
      e.tick(s, 60);
      expect(s.faction('player').megaprojectLevels['orbital_station'], 1);
      expect(s.projects, isEmpty);
      e.advance(s, 7200);
      expect(s.faction('player').megaprojectLevels['orbital_station'], 1);

      // The next stage costs level 1's price and takes longer.
      fails(s, start, CommandError.cannotAfford);
      for (final MapEntry(:key, :value) in megaprojectCost(
        content,
        station,
        1,
      ).entries) {
        if (key != 'credits') s.body('kora').stock[key] = value;
      }
      ok(s, start);
      final p = e.projectsFor(s, 'player').single;
      expect(p.finishAt - p.startedAt, closeTo(8280, 1e-9));
    });

    test('while away is listed by name', () {
      final s = stocked();
      ok(s, start);
      final sum = e.catchUpOffline(s, 7300);
      final done = sum.projectsCompleted.single;
      expect(
        (done.kind, done.targetId, done.name),
        (ProjectKind.megaprojectStage, 'orbital_station', 'Orbital Station'),
      );
      expect(s.faction('player').megaprojectLevels['orbital_station'], 1);
    });
  });

  group('bonuses', () {
    test('none before any level', () {
      final b = bonusesFor(rich(), content, 'player');
      expect(b.storagePercent, 0);
      expect(b.housingPercent, 0);
      expect(b.offlineCapSeconds, 0);
      expect(b.outputPercent, 0);
      expect(b.marketDepthPercent, 0);
    });

    test('+10% storage shows in storageCap', () {
      final s = rich();
      final kora = s.body('kora');
      expect(storageCap(s, content, kora), n(1000));
      s.faction('player').megaprojectLevels['orbital_station'] = 1;
      expect(storageCap(s, content, kora).toDouble(), closeTo(1100, 1e-9));
      s.faction('player').megaprojectLevels['orbital_station'] = 3;
      expect(storageCap(s, content, kora).toDouble(), closeTo(1300, 1e-9));
      // An unowned body gets no one's bonus.
      expect(storageCap(s, content, s.body('brine')), n(1000));
    });

    test('+5% housing shows in supported crew', () {
      final s = rich();
      final kora = s.body('kora');
      for (final id in ['h1', 'h2']) {
        kora.buildings.add(
          BuildingState(id: id, defId: 'habitat', crew: 0, lastRunFraction: 1),
        );
      }
      // 20 base crew plus two habitats housing 20 each.
      expect(crewTotals(s, content, 'player').supported, 60);
      s.faction('player').megaprojectLevels['orbital_station'] = 1;
      expect(crewTotals(s, content, 'player').supported, 62);
      s.faction('player').megaprojectLevels['orbital_station'] = 4;
      expect(crewTotals(s, content, 'player').supported, 68);
    });

    group('offline cap', () {
      double simulated(int level, {double? capSeconds}) {
        final s = rich();
        s.faction('player').megaprojectLevels['orbital_station'] = level;
        return e
            .catchUpOffline(s, 1e6, capSeconds: capSeconds)
            .secondsSimulated;
      }

      test('is 12 h base and 13 h at level 1', () {
        expect(offlineCapFor(rich(), content, 'player'), 43200);
        expect(simulated(0), 43200);
        expect(simulated(1), 46800);
      });

      test('is clamped at 48 h at level 50', () {
        final s = rich();
        s.faction('player').megaprojectLevels['orbital_station'] = 50;
        expect(offlineCapFor(s, content, 'player'), 172800);
        expect(RulesDef.maxOfflineCapSeconds, 172800);
        expect(simulated(50), 172800);
      });

      test('an explicit capSeconds still overrides it', () {
        expect(simulated(5, capSeconds: 600), 600);
      });
    });

    test('output adds to what buildings make', () {
      final c = contentWithBonuses([
        {'kind': 'outputPercent', 'amount': 50},
      ]);
      final boosted = GameEngine(c);
      double copperMade(int level) {
        final s = boosted.newGame(1);
        s.faction('player').megaprojectLevels['boost'] = level;
        boosted.advance(s, 600);
        return s.faction('player').lifetimeProduced['copper_ore']!.toDouble();
      }

      final base = copperMade(0);
      expect(base, greaterThan(0));
      expect(copperMade(1), closeTo(base * 1.5, base * 1e-9));
    });

    test('market depth makes a large sale earn more', () {
      final c = contentWithBonuses([
        {'kind': 'marketDepthPercent', 'amount': 100},
      ]);
      final depth = c.resources['steel']!.marketDepth;
      double revenue(int level) {
        final s = GameEngine(c).newGame(1);
        s.faction('player').megaprojectLevels['boost'] = level;
        s.body('kora').stock['steel'] = n(depth);
        return sell(
          s,
          c,
          'player',
          'kora',
          'steel',
          n(depth),
        ).revenue.toDouble();
      }

      // depth × base × (1 − e^(−units / depth)), at the depth and twice it.
      final tol = 6 * depth * 1e-12;
      expect(revenue(0), closeTo(6 * depth * (1 - math.exp(-1)), tol));
      expect(revenue(1), closeTo(6 * 2 * depth * (1 - math.exp(-0.5)), tol));
    });

    test('market depth softens auto-sell too', () {
      final c = contentWithBonuses([
        {'kind': 'marketDepthPercent', 'amount': 100},
      ]);
      double saturation(int level) {
        final s = GameEngine(c).newGame(1);
        s.faction('player').megaprojectLevels['boost'] = level;
        s.body('kora').stock['steel'] = n(3000);
        s
            .faction('player')
            .autoSell
            .add(
              AutoSellRule(
                bodyId: 'kora',
                resourceId: 'steel',
                keepAtLeast: const BigNum.zero(),
              ),
            );
        stepMarket(s, c, 60);
        return s.market.saturation['steel']!;
      }

      expect(saturation(1), greaterThan(saturation(0)));
    });
  });

  group('levels', () {
    test('survive save/load and copy()', () {
      final s = stocked();
      ok(s, start);
      s.faction('player').megaprojectLevels['orbital_station'] = 2;
      final loaded =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      final copied = s.copy();
      expect(encode(loaded), encode(s));
      expect(encode(copied), encode(s));
      copied.faction('player').megaprojectLevels['orbital_station'] = 9;
      expect(s.faction('player').megaprojectLevels['orbital_station'], 2);
      for (final x in [s, loaded]) {
        e.advance(x, 7300);
      }
      expect(loaded.faction('player').megaprojectLevels['orbital_station'], 3);
      expect(encode(loaded), encode(s));
    });

    test('a save without them loads with none', () {
      final m = e.newGame(1).toJson();
      for (final f in (m['factions']! as List).cast<Map<String, Object?>>()) {
        f.remove('megaprojectLevels');
      }
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      expect((r as SaveOk).state.faction('player').megaprojectLevels, isEmpty);
    });
  });

  group('saves with megaprojects are checked:', () {
    Map<String, Object?> save({
      Map<String, Object?> levels = const {},
      List<Map<String, Object?>> projects = const [],
      Map<String, Object?>? progress,
    }) {
      final m = e.newGame(1).toJson()
        ..['time'] = 100
        ..['nextId'] = 100
        ..['projects'] = projects;
      final player = (m['factions']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((f) => f['id'] == 'player');
      player['megaprojectLevels'] = levels;
      if (progress != null) player['megaprojectProgress'] = progress;
      return m;
    }

    Map<String, Object?> stage({
      String id = 'p50',
      String targetId = 'orbital_station',
    }) => {
      'id': id,
      'factionId': 'player',
      'kind': 'megaprojectStage',
      'targetId': targetId,
      'startedAt': 0,
      'finishAt': 7200,
    };

    SaveResult decode(Map<String, Object?> m) =>
        SaveCodec.decode(jsonEncode(m), content);

    test('valid levels and a stage load', () {
      final r = decode(
        save(levels: {'orbital_station': 1000 - 1}, projects: [stage()]),
      );
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
    });

    test('valid progress loads', () {
      final r = decode(
        save(
          levels: {'orbital_station': 1},
          progress: {
            'orbital_station': {'hull_plate': '1.8e2', 'credits': '0'},
          },
        ),
      );
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
    });

    test('an unknown megaproject is an unknown id', () {
      for (final m in [
        save(levels: {'dyson': 1}),
        save(projects: [stage(targetId: 'dyson')]),
        save(
          progress: {
            'dyson': {'hull_plate': '1'},
          },
        ),
        save(
          progress: {
            'orbital_station': {'unobtanium': '1'},
          },
        ),
      ]) {
        final r = decode(m);
        expect((r as SaveError).kind, SaveErrorKind.unknownContentId);
      }
    });

    final invalid = <String, Map<String, Object?>>{
      'a negative level': save(levels: {'orbital_station': -1}),
      'a level above 1000': save(levels: {'orbital_station': 1001}),
      'two stages of one megaproject': save(
        projects: [
          stage(),
          stage(id: 'p51'),
        ],
      ),
      'a stage past the highest level': save(
        levels: {'orbital_station': 1000},
        projects: [stage()],
      ),
      'negative progress': save(
        progress: {
          'orbital_station': {'hull_plate': '-1'},
        },
      ),
      'progress in a good the stage does not take': save(
        progress: {
          'orbital_station': {'iron_ore': '1'},
        },
      ),
      'progress beyond the stage cost': save(
        progress: {
          'orbital_station': {'hull_plate': '1e9'},
        },
      ),
      'progress complete with no stage started': save(
        progress: {
          'orbital_station': {
            for (final MapEntry(:key, :value) in megaprojectCost(
              content,
              station,
              0,
            ).entries)
              key: value.toJson(),
          },
        },
      ),
      'progress while a stage is under way': save(
        projects: [stage()],
        progress: {
          'orbital_station': {'hull_plate': '1'},
        },
      ),
      'progress past the highest level': save(
        levels: {'orbital_station': 1000},
        progress: {
          'orbital_station': {'hull_plate': '1'},
        },
      ),
    };
    for (final MapEntry(key: name, value: m) in invalid.entries) {
      test(name, () {
        final r = decode(m);
        expect(r, isA<SaveError>(), reason: name);
        expect(
          (r as SaveError).kind,
          SaveErrorKind.invalidValue,
          reason: r.message,
        );
      });
    }

    test('a level that is not an integer is malformed', () {
      final r = decode(save(levels: {'orbital_station': 'one'}));
      expect((r as SaveError).kind, SaveErrorKind.missingField);
    });

    test('progress that is not a number is malformed', () {
      final r = decode(
        save(
          progress: {
            'orbital_station': {'hull_plate': 3},
          },
        ),
      );
      expect((r as SaveError).kind, SaveErrorKind.missingField);
    });
  });

  group('content validation', () {
    /// [b] without the milestones that name a megaproject.
    void dropMegaprojectMilestones(Map<String, Object?> b) {
      b['milestones'] = [
        for (final m in (b['milestones']! as List).cast<Map<String, Object?>>())
          if ((m['condition']! as Map)['type'] != 'megaprojectLevel') m,
      ];
    }

    List<String> errors(Map<String, Object?> megaproject) {
      final b = shippedBundle()..['megaprojects'] = [megaproject];
      return switch (Content.fromBundle(b)) {
        ContentOk() => fail('expected ContentInvalid'),
        ContentInvalid(:final errors) => errors,
      };
    }

    test('content without megaprojects has none', () {
      final b = shippedBundle()..remove('megaprojects');
      dropMegaprojectMilestones(b);
      final c = (Content.fromBundle(b) as ContentOk).content;
      expect(c.megaprojects, isEmpty);
    });

    final bad = <String, (Map<String, Object?>, String)>{
      'unknown cost resource': (
        {
          ...stationJson(),
          'baseCost': {'unobtainium': '5'},
        },
        "megaprojects.orbital_station.baseCost: unknown resource 'unobtainium'",
      ),
      'empty cost': (
        {...stationJson(), 'baseCost': <String, Object?>{}},
        'megaprojects.orbital_station.baseCost: must list at least one',
      ),
      'zero cost': (
        {
          ...stationJson(),
          'baseCost': {'credits': '0'},
        },
        'megaprojects.orbital_station.baseCost.credits: must be > 0',
      ),
      'cost growth below 1': (
        {...stationJson(), 'costGrowth': 0.5},
        'megaprojects.orbital_station.costGrowth: must be >= 1',
      ),
      'stage under 10 minutes': (
        {...stationJson(), 'stageSeconds': 60},
        'megaprojects.orbital_station.stageSeconds: must be >= 600',
      ),
      'stage over 6 hours': (
        {...stationJson(), 'stageSeconds': 30000},
        'megaprojects.orbital_station.stageSeconds: must be <= 21600',
      ),
      'stage growth below 1': (
        {...stationJson(), 'stageSecondsGrowth': 0.9},
        'megaprojects.orbital_station.stageSecondsGrowth: must be >= 1',
      ),
      'unknown host body type': (
        {...stationJson(), 'hostBodyType': 'comet'},
        "megaprojects.orbital_station.hostBodyType: unknown body type 'comet'",
      ),
      'no bonuses': (
        {...stationJson(), 'bonusesPerLevel': <Object?>[]},
        'megaprojects.orbital_station.bonusesPerLevel: must list at least one',
      ),
      'unknown bonus kind': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {'kind': 'luck', 'amount': 1},
          ],
        },
        "megaprojects.orbital_station.bonusesPerLevel[0].kind: unknown bonus "
            "kind 'luck'",
      ),
      'bonus not above 0': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {'kind': 'storagePercent', 'amount': 0},
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].amount: must be > 0',
      ),
      'unknown field': (
        {...stationJson(), 'colour': 'red'},
        'megaprojects.orbital_station.colour: unknown field',
      ),
      'missing name': (
        {...stationJson()}..remove('name'),
        'megaprojects.orbital_station.name: missing',
      ),
    };
    for (final MapEntry(key: name, value: (m, want)) in bad.entries) {
      test(name, () => expect(errors(m), contains(want)));
    }

    test('a duplicate id and a non-list section are reported', () {
      final b = shippedBundle()
        ..['megaprojects'] = [stationJson(), stationJson()];
      expect(
        (Content.fromBundle(b) as ContentInvalid).errors,
        contains('megaprojects.orbital_station: duplicate id'),
      );
      final c = shippedBundle()..['megaprojects'] = {'id': 'x'};
      expect(
        (Content.fromBundle(c) as ContentInvalid).errors,
        contains('megaprojects: expected a list'),
      );
    });

    test('a resource only a megaproject uses counts as consumed', () {
      final b = shippedBundle();
      final res = (b['resources']! as List).cast<Map<String, Object?>>();
      // Station segments become unsellable; the station still uses them.
      res.firstWhere((r) => r['id'] == 'station_segment')['basePrice'] = '0';
      expect(Content.fromBundle(b), isA<ContentOk>());
      b['megaprojects'] = <Object?>[];
      dropMegaprojectMilestones(b);
      expect(
        (Content.fromBundle(b) as ContentInvalid).errors,
        contains(
          'resources.station_segment: never consumed and cannot be sold',
        ),
      );
    });
  });
}
