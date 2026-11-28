import 'dart:convert';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:game_core/src/sim/megaprojects.dart' show bonusVectorsKept;
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

String encode(GameState s) => jsonEncode(s.toJson());

/// The shipped Orbital Station entry, as a fresh mutable JSON map.
Map<String, Object?> stationJson() => (shippedBundle()['megaprojects']! as List)
    .cast<Map<String, Object?>>()
    .firstWhere((m) => m['id'] == 'orbital_station');

/// The shipped content with its megaprojects file replaced by
/// [megaprojects], less the milestones on any other megaproject.
Content contentWithMegaprojects(List<Map<String, Object?>> megaprojects) {
  final ids = {for (final m in megaprojects) m['id']};
  final b = shippedBundle()..['megaprojects'] = megaprojects;
  (b['milestones']! as List).removeWhere((m) {
    final condition = (m as Map<String, Object?>)['condition']! as Map;
    return condition['type'] == 'megaprojectLevel' &&
        !ids.contains(condition['megaproject']);
  });
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
      expect(content.megaprojects.keys, ['orbital_station', 'mass_driver']);
      expect(station.name, 'Orbital Station');
      expect(station.hostBodyType, isNull);
      // Stage 1.7 task 4: ×2 a level (was ×2.5), with 2e7 credits at
      // level 0 (was 5e6), so a level costs about 1-2 days of the
      // balanced bot's income through day 21.
      expect(station.costGrowth, 2.0);
      expect(station.baseCost['credits'], BigNum.from(2e7));
      expect(station.stageSeconds, 7200);
      expect(station.stageSecondsGrowth, 1.15);
      expect(
        [for (final b in station.bonusesPerLevel) (b.kind, b.amount)],
        [
          (BonusKind.storagePercent, 10),
          (BonusKind.housingPercent, 5),
          (BonusKind.offlineCapSeconds, 3600),
          (BonusKind.marketDepthMultiplier, 1.25),
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

  group('the shipped Mass Driver', () {
    final driver = content.megaprojects['mass_driver']!;
    final deliver = DeliverToMegaprojectCommand(
      'player',
      'mass_driver',
      'kora',
      {'copper_wire': n(1)},
    );

    test('costs credits and bulk tier 0-2 goods, ×2 a level', () {
      expect(driver.name, 'Mass Driver');
      expect(driver.hostBodyType, isNull);
      expect(driver.costGrowth, 2.0);
      expect(driver.baseCost['credits'], BigNum.from(8e6));
      // No food (habitats eat all a casual player makes) and no steel
      // (plate presses for the station take it): stage 1.6 task 5.
      expect(driver.baseCost.keys, [
        'credits',
        'hull_plate',
        'copper_wire',
        'water',
        'silicon_wafer',
      ]);
      for (final MapEntry(key: id, value: v) in driver.baseCost.entries) {
        if (id == 'credits') continue;
        expect(content.resources[id]!.tier, lessThanOrEqualTo(2), reason: id);
        expect(v.toDouble(), inInclusiveRange(1e3, 1e5), reason: id);
      }
    });

    test('raises what tier 1-2 sales earn, ×1.05 a level, compounding', () {
      // No market depth: deeper tier 0-1 markets made them most of an
      // optimizer's sales by day 14 (stage 1.6 task 5). No production
      // speed: no tier range of it lifted mid-game income (stage 1.7). The
      // sale price of tiers 1-2 at ×1.05 adds about 5% of steady income a
      // level on the balanced bot's day 7 and 14, past the plan's 3%,
      // without the economy running away (twelve levels are about ×1.8);
      // stage 1.7 task 4's retune owns the final factor.
      expect(
        [
          for (final b in driver.bonusesPerLevel)
            (b.kind, b.amount, b.appliesToMinTier, b.appliesToMaxTier),
        ],
        [(BonusKind.salePriceMultiplier, 1.05, 1, 2)],
      );
    });

    test('opens at Orbital Station level 1', () {
      expect(driver.requiresMegaproject, {'orbital_station': 1});
      final s = rich();
      s.body('kora').stock['copper_wire'] = n(10);
      const level = 0;
      s.faction('player').megaprojectLevels['orbital_station'] = level;
      expect(megaprojectLockedBy(s, content, 'player', driver), (
        megaprojectId: 'orbital_station',
        level: 1,
      ));
      expect(megaprojectTakesDeliveries(s, content, 'player', driver), isFalse);
      final why = fails(s, deliver, CommandError.megaprojectLocked);
      expect(
        why,
        'Mass Driver opens at Orbital Station level 1 (you have level '
        '$level)',
      );
      fails(
        s,
        const StartMegaprojectStageCommand('player', 'mass_driver', 'kora'),
        CommandError.megaprojectLocked,
      );
      s.faction('player').megaprojectLevels['orbital_station'] = 1;
      expect(megaprojectLockedBy(s, content, 'player', driver), isNull);
      expect(megaprojectTakesDeliveries(s, content, 'player', driver), isTrue);
      ok(s, deliver);
      expect(s.faction('player').megaprojectProgress['mass_driver'], {
        'copper_wire': n(1),
      });
    });
  });

  group('costs', () {
    test('what is still owed ignores float residue of deliveries summed', () {
      // 1.59e7 then 5e4 toward a 1.6e7-credit stage leave 5e4 and a hair
      // in BigNum sums; the hair is not a credit owed.
      final driver = content.megaprojects['mass_driver']!;
      final s = e.newGame(1);
      final cost = megaprojectCost(content, driver, 1)['credits']!;
      expect(cost, BigNum.from(1.6e7));
      s.faction('player')
        ..megaprojectLevels['orbital_station'] = 1
        ..megaprojectLevels['mass_driver'] = 1
        ..megaprojectProgress['mass_driver'] = {
          'credits': cost - BigNum.from(1e5) + BigNum.from(5e4),
        };
      expect(
        megaprojectRemaining(s, content, 'player', driver)['credits'],
        BigNum.from(5e4),
      );
      // A whole credit still owed is still owed, at 1.6e7 and past 1e13,
      // where a part in 1e12 of the cost would be ten credits.
      s.faction('player').megaprojectProgress['mass_driver'] = {
        'credits': cost - BigNum.from(1),
      };
      expect(
        megaprojectRemaining(s, content, 'player', driver)['credits'],
        BigNum.from(1),
      );
      final station = content.megaprojects['orbital_station']!;
      final big = megaprojectCost(content, station, 19)['credits']!;
      expect(big > BigNum.from(1e13), isTrue);
      s.faction('player')
        ..megaprojectLevels['orbital_station'] = 19
        ..megaprojectProgress['orbital_station'] = {
          'credits': big - BigNum.from(1),
        };
      expect(
        megaprojectRemaining(s, content, 'player', station)['credits'],
        BigNum.from(1),
      );
    });

    test('grow by costGrowth a level', () {
      final base = megaprojectCost(content, station, 0);
      expect(base, station.baseCost);
      for (final level in [1, 2, 5]) {
        final cost = megaprojectCost(content, station, level);
        expect(cost.keys, base.keys);
        for (final MapEntry(:key, :value) in cost.entries) {
          // Whole units, rounded up.
          final want =
              (base[key]!.toDouble() * math.pow(station.costGrowth, level))
                  .ceilToDouble();
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

    test('while a stage runs, pays for the next one, which then waits', () {
      final s = stocked();
      ok(s, start);
      for (final id in station.baseCost.keys) {
        if (id != 'credits') s.body('kora').stock[id] = n(1e6);
      }
      // Level 2's cost: the stage after the one under way.
      expect(ok(s, start), isNull);
      expect(s.projects, hasLength(1));
      expect(megaprojectRemaining(s, content, 'player', station), isEmpty);
      expect(megaprojectStageQueued(s, content, 'player', station), isTrue);
      final msg = fails(s, start, CommandError.projectInProgress);
      expect(
        msg,
        'Orbital Station level 2 is paid for; it starts when level 1 is '
        'done (2h left)',
      );
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

    test('deliveries move whole units, so delivering what is shown still '
        'needed completes the cost', () {
      final s = twoBodies();
      final kora = s.body('kora')..stock['hull_plate'] = n(10.7);
      ok(s, deliver('kora', {'hull_plate': n(1e6)}));
      // Only whole units leave: 10 delivered, 0.7 kept.
      expect(progress(s)['hull_plate'], n(10));
      expect(kora.stock['hull_plate']!.toDouble(), closeTo(0.7, 1e-9));
      final shown = megaprojectRemaining(
        s,
        content,
        'player',
        station,
      )['hull_plate']!;
      expect(shown, n(1490));
      kora.stock['hull_plate'] = kora.stock['hull_plate']! + shown;
      ok(s, deliver('kora', {'hull_plate': shown}));
      expect(
        megaprojectRemaining(s, content, 'player', station),
        isNot(contains('hull_plate')),
      );
      expect(kora.stock['hull_plate']!.toDouble(), closeTo(0.7, 1e-9));
    });

    test('progress with a fraction in it (an older save) still shows whole '
        'units still needed, and that amount completes it', () {
      final s = twoBodies();
      s.faction('player').megaprojectProgress['orbital_station'] = {
        'station_segment': n(3.4),
      };
      final shown = megaprojectRemaining(
        s,
        content,
        'player',
        station,
      )['station_segment']!;
      expect(shown, n(197));
      s.body('kora').stock['station_segment'] = shown;
      ok(s, deliver('kora', {'station_segment': shown}));
      expect(progress(s)['station_segment'], n(200));
    });

    test('less than one whole unit is nothing to deliver', () {
      final s = twoBodies();
      s.body('kora').stock['hull_plate'] = n(0.6);
      final msg = fails(
        s,
        deliver('kora', {'hull_plate': n(5)}),
        CommandError.cannotAfford,
      );
      expect(msg, 'There is less than one whole Hull Plate on Kora to deliver');
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
      // Once the stage after one under way is paid for, it takes no more.
      ok(s, deliver('kora', {...goods(), 'credits': credits0()}));
      s.body('kora').stock.addAll(goods(3));
      ok(s, deliver('kora', {...goods(3), 'credits': credits0().mulDouble(3)}));
      fails(s, deliver('kora', goods()), CommandError.projectInProgress);
      final top = twoBodies()..body('kora').stock.addAll(goods());
      top.faction('player').megaprojectLevels['orbital_station'] =
          SaveCodec.maxMegaprojectLevel;
      fails(top, deliver('kora', goods()), CommandError.invalidAmount);
    });

    test('while the last stage is under way, deliveries say so, not that it '
        'is at its highest level', () {
      final s = twoBodies()..body('kora').stock.addAll(goods());
      const max = SaveCodec.maxMegaprojectLevel;
      s.faction('player').megaprojectLevels['orbital_station'] = max - 1;
      startProject(
        s,
        'player',
        ProjectKind.megaprojectStage,
        'orbital_station',
        3600,
      );
      final msg = fails(
        s,
        deliver('kora', goods()),
        CommandError.projectInProgress,
      );
      expect(
        msg,
        'Orbital Station level $max, its highest, is under way (1h left); '
        'there is nothing more to deliver',
      );
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

  group('deliveries while a stage runs', () {
    DeliverToMegaprojectCommand deliver(Map<String, BigNum> amounts) =>
        DeliverToMegaprojectCommand(
          'player',
          'orbital_station',
          'kora',
          amounts,
        );

    /// Level [level]'s cost, goods only.
    Map<String, BigNum> goods(int level) => {
      for (final MapEntry(:key, :value) in megaprojectCost(
        content,
        station,
        level,
      ).entries)
        if (key != 'credits') key: value,
    };

    BigNum credits(int level) =>
        megaprojectCost(content, station, level)['credits']!;

    test('count toward the level after the one being built', () {
      final s = stocked();
      ok(s, start);
      expect(megaprojectDeliveryLevel(s, 'player', station), 1);
      expect(
        megaprojectRemaining(s, content, 'player', station),
        megaprojectCost(content, station, 1),
      );
      s.body('kora').stock['hull_plate'] = n(1e6);
      expect(ok(s, deliver({'hull_plate': n(1e6)})), isNull);
      expect(s.faction('player').megaprojectProgress['orbital_station'], {
        'hull_plate': goods(1)['hull_plate'],
      });
      expect(s.projects, hasLength(1));
      // Part-paid, the next stage does not start when this one completes.
      e.advance(s, 7260);
      expect(s.faction('player').megaprojectLevels['orbital_station'], 1);
      expect(s.projects, isEmpty);
      expect(megaprojectDeliveryLevel(s, 'player', station), 1);
      expect(
        megaprojectRemaining(s, content, 'player', station).keys,
        isNot(contains('hull_plate')),
      );
      // The final delivery starts it at once, as before.
      s.body('kora').stock.addAll(goods(1));
      expect(
        ok(s, deliver({...goods(1), 'credits': credits(1)})),
        startsWith('p'),
      );
      expect(s.projects.single.startedAt, s.time);
    });

    test(
      'paid in full, the next stage starts as the running one completes',
      () {
        final s = stocked();
        ok(s, start);
        final first = s.projects.single;
        e.advance(s, 600);
        s.body('kora').stock.addAll(goods(1));
        expect(ok(s, deliver({...goods(1), 'credits': credits(1)})), isNull);
        expect(s.projects.single, same(first));
        e.advance(s, 7200 - 600);
        // Due exactly at the end of that tick: it completes in the next.
        e.tick(s, 1);
        expect(s.faction('player').megaprojectLevels['orbital_station'], 1);
        final queued = s.projects.single;
        expect(queued.kind, ProjectKind.megaprojectStage);
        expect(queued.startedAt, first.finishAt);
        expect(
          queued.finishAt,
          closeTo(first.finishAt + megaprojectStageSeconds(station, 1), 1e-9),
        );
        expect(s.faction('player').megaprojectProgress, isEmpty);
        e.advance(s, queued.finishAt - s.time);
        e.tick(s, 1);
        expect(s.faction('player').megaprojectLevels['orbital_station'], 2);
        expect(s.projects, isEmpty);
      },
    );

    test('a catch-up across two chained stages matches live play', () {
      GameState queuedTwice() {
        final s = stocked();
        ok(s, start);
        s.body('kora').stock.addAll(goods(1));
        ok(s, deliver({...goods(1), 'credits': credits(1)}));
        return s;
      }

      final away = queuedTwice();
      final sum = e.catchUpOffline(away, 6 * 3600);
      final live = queuedTwice();
      e.advance(live, 6 * 3600, maxStep: 1);
      final steps = queuedTwice();
      e.advance(steps, 6 * 3600);
      // Same 60 s ticks: the same state, byte for byte.
      expect(encode(away), encode(steps));
      for (final x in [away, live]) {
        expect(x.faction('player').megaprojectLevels['orbital_station'], 2);
        expect(x.projects, isEmpty);
      }
      expect(
        [for (final p in sum.projectsCompleted) (p.kind, p.targetId, p.level)],
        [
          (ProjectKind.megaprojectStage, 'orbital_station', 1),
          (ProjectKind.megaprojectStage, 'orbital_station', 2),
        ],
      );
    });

    test('a tick longer than both stages completes the chain', () {
      final s = stocked();
      ok(s, start);
      s.body('kora').stock.addAll(goods(1));
      ok(s, deliver({...goods(1), 'credits': credits(1)}));
      e.tick(s, 20000);
      e.tick(s, 1);
      expect(s.faction('player').megaprojectLevels['orbital_station'], 2);
      expect(s.projects, isEmpty);
    });
  });

  group('completion', () {
    test('raises the level once, and the next stage costs more', () {
      final s = stocked();
      ok(s, start);
      e.advance(s, 7140);
      expect(s.faction('player').megaprojectLevels['orbital_station'], isNull);
      // The tick that ends at its finish time completes it.
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

    test('the totals kept per level vector stay bounded across many '
        'games', () {
      final c = contentWithBonuses([
        {'kind': 'storagePercent', 'amount': 10},
      ]);
      final s = GameEngine(c).newGame(1);
      final f = s.faction('player');
      for (var level = 0; level < 1000; level++) {
        f.megaprojectLevels['boost'] = level;
        expect(bonusesFor(s, c, 'player').storagePercent, 10.0 * level);
        expect(bonusVectorsKept(c), lessThanOrEqualTo(256));
      }
      // Copies at the same levels still share one object.
      expect(
        identical(
          bonusesFor(s, c, 'player'),
          bonusesFor(s.copy(), c, 'player'),
        ),
        isTrue,
      );
    });

    group('sale price multiplier', () {
      final c = contentWithBonuses([
        {
          'kind': 'salePriceMultiplier',
          'amount': 1.2,
          'appliesToMinTier': 1,
          'appliesToMaxTier': 2,
        },
      ]);
      final eng = GameEngine(c);

      GameState at(int level) {
        final s = eng.newGame(1);
        s.faction('player')
          ..megaprojectLevels['boost'] = level
          ..contracts.clear()
          ..contractRefillAt.clear()
          ..contractRefillAt.addAll(List.filled(RulesDef.contractSlots, 1e12));
        return s;
      }

      test('multiplies what a sale earns, factor^level, only on its tiers, '
          'and leaves the market alone', () {
        for (final level in [0, 1, 3]) {
          final want = math.pow(1.2, level).toDouble();
          // Steel is tier 1, iron ore tier 0.
          for (final (id, factor) in [('steel', want), ('iron_ore', 1.0)]) {
            final plain = at(0)..body('kora').stock[id] = n(500);
            final boosted = at(level)..body('kora').stock[id] = n(500);
            final a = sell(plain, c, 'player', 'kora', id, n(500));
            final b = sell(boosted, c, 'player', 'kora', id, n(500));
            expect(b.sold, a.sold);
            expect(
              b.revenue.toDouble(),
              closeTo(a.revenue.toDouble() * factor, 1e-6),
              reason: '$id at $level',
            );
            expect(boosted.market.saturation[id], plain.market.saturation[id]);
            expect(boosted.faction('player').salesRevenue[id], b.revenue);
            expect(
              salePrice(boosted, c, 'player', id).toDouble(),
              closeTo(price(boosted, c, id).toDouble() * factor, 1e-9),
            );
          }
        }
        final b = bonusesFor(at(2), c, 'player');
        expect(
          [
            for (var t = 0; t <= ResourceDef.megaprojectTier; t++)
              b.salePriceMultiplierFor(t),
          ],
          [1, closeTo(1.44, 1e-12), closeTo(1.44, 1e-12), 1, 1],
        );
      });

      test('auto-sell earns it, and the report\'s credits a second, the '
          'measured run and the income agree', () {
        double earned(GameState s) {
          eng.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
          s.body('kora').stock['iron_ore'] = n(900);
          eng.advance(s, 600);
          final before = s.faction('player').salesRevenue['steel']!;
          eng.advance(s, 600);
          return (s.faction('player').salesRevenue['steel']! - before)
                  .toDouble() /
              600;
        }

        final plain = at(0);
        final boosted = at(2);
        final a = earned(plain);
        final b = earned(boosted);
        expect(b, closeTo(a * 1.44, a * 1.44 * 1e-6));
        // Only steel sells: the report reads what the sales earn.
        final ra = buildFlowReport(plain, c, 'player').creditsPerSec.toDouble();
        final rb = buildFlowReport(
          boosted,
          c,
          'player',
        ).creditsPerSec.toDouble();
        expect(rb, closeTo(ra * 1.44, ra * 1.44 * 0.01));
        expect(rb, closeTo(b, b * 0.05));
      });

      test('the report values what is lost at what sales would earn', () {
        BigNum? lost(int level) {
          final s = at(level);
          final kora = s.body('kora');
          kora.stock['iron_ore'] = n(900);
          kora.stock['steel'] = storageCap(s, c, kora);
          final r = buildFlowReport(s, c, 'player');
          return r.bottlenecks
              .firstWhere(
                (b) =>
                    b.kind == BottleneckKind.storageFull &&
                    b.resourceId == 'steel',
              )
              .lostCreditsPerHour;
        }

        final plain = lost(0)!.toDouble();
        expect(plain, greaterThan(0));
        expect(lost(2)!.toDouble(), closeTo(plain * 1.44, plain * 1e-9));
      });

      test('a contract for a good it covers pays at least 1.5 times what '
          'selling the goods earns', () {
        var checked = 0;
        for (var seed = 1; seed <= 12; seed++) {
          final s = eng.newGame(seed);
          final f = s.faction('player')..megaprojectLevels['boost'] = 4;
          // An income, so orders are sized and paid by it.
          eng.apply(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
          s.body('kora').stock['iron_ore'] = n(900);
          eng.advance(s, 1800);
          f.contracts.clear();
          f.contractRefillAt
            ..clear()
            ..addAll([s.time, s.time, s.time]);
          stepContracts(s, c, s.time);
          for (final k in f.contracts) {
            if (c.resources[k.resourceId]!.tier == 0) continue;
            final sold = s.copy();
            sold.body('kora').stock[k.resourceId] = k.quantity;
            final earned = sell(
              sold,
              c,
              'player',
              'kora',
              k.resourceId,
              k.quantity,
            ).revenue;
            final atPrice =
                k.quantity * salePrice(s, c, 'player', k.resourceId);
            expect(earned <= atPrice, isTrue, reason: k.resourceId);
            expect(
              k.rewardCredits.toDouble(),
              greaterThanOrEqualTo(atPrice.toDouble() * 1.5 - 1),
              reason: '${k.resourceId} at seed $seed',
            );
            checked++;
          }
        }
        expect(checked, greaterThan(0));
      });

      test('takes a tier range and a factor of at least 1, like the other '
          'multipliers', () {
        for (final (bonus, error) in [
          (
            {'kind': 'salePriceMultiplier', 'amount': 0.9},
            'must be >= 1 for a multiplier',
          ),
          (
            {
              'kind': 'salePriceMultiplier',
              'amount': 1.1,
              'appliesToMinTier': 2,
              'appliesToMaxTier': 1,
            },
            'must be <= appliesToMaxTier (1)',
          ),
        ]) {
          final r = Content.fromBundle({
            ...shippedBundle(),
            'megaprojects': [
              stationJson(),
              {
                ...stationJson(),
                'id': 'boost',
                'name': 'Boost',
                'bonusesPerLevel': [bonus],
              },
            ],
          });
          expect(r, isA<ContentInvalid>());
          expect((r as ContentInvalid).errors.join("\n"), contains(error));
        }
      });
    });

    group('compounding multipliers', () {
      final c = contentWithBonuses([
        {'kind': 'marketDepthMultiplier', 'amount': 1.2, 'appliesToMaxTier': 1},
        {'kind': 'productionSpeedMultiplier', 'amount': 1.1},
      ]);
      final boost = c.megaprojects['boost']!;

      GameState at(int level) {
        final s = GameEngine(c).newGame(1);
        s.faction('player').megaprojectLevels['boost'] = level;
        return s;
      }

      test('market depth is factor^level, only up to its tier', () {
        for (final level in [0, 1, 3]) {
          final s = at(level);
          final want = math.pow(1.2, level).toDouble();
          for (final id in ['iron_ore', 'steel']) {
            expect(
              marketDepthFor(s, c, 'player', id),
              closeTo(c.resources[id]!.marketDepth * want, 1e-6),
              reason: '$id at level $level',
            );
          }
          // Hull plate is tier 2, past the bonus's tier.
          expect(
            marketDepthFor(s, c, 'player', 'hull_plate'),
            c.resources['hull_plate']!.marketDepth,
          );
        }
      });

      test('production speed is factor^level on what a building uses and '
          'makes', () {
        final s = at(2);
        final kora = s.body('kora');
        final smelter = BuildingState(id: 'x', defId: 'smelter', crew: 1);
        final plain = fullRateFlow(c, kora, smelter, 60, 1);
        final fast = fullRateFlow(
          c,
          kora,
          smelter,
          60,
          1,
          bonuses: bonusesFor(s, c, 'player'),
        );
        expect(
          fast.inputs['iron_ore']!.toDouble(),
          closeTo(plain.inputs['iron_ore']!.toDouble() * 1.21, 1e-9),
        );
        expect(
          fast.outputs['steel']!.toDouble(),
          closeTo(plain.outputs['steel']!.toDouble() * 1.21, 1e-9),
        );
      });

      test('production speed up to a tier leaves higher tiers and habitats '
          'alone', () {
        final c1 = contentWithBonuses([
          {
            'kind': 'productionSpeedMultiplier',
            'amount': 1.1,
            'appliesToMaxTier': 1,
          },
        ]);
        final s = GameEngine(c1).newGame(1);
        s.faction('player').megaprojectLevels['boost'] = 3;
        final bonuses = bonusesFor(s, c1, 'player');
        final kora = s.body('kora');
        double rate(String defId, String id, {bool input = false}) {
          final b = BuildingState(
            id: 'x',
            defId: defId,
            crew: 1,
            depositResourceId: defId == 'mine' ? 'iron_ore' : null,
          );
          final flow = fullRateFlow(c1, kora, b, 1, 1, bonuses: bonuses);
          return (input ? flow.inputs : flow.outputs)[id]!.toDouble();
        }

        double plain(String defId, String id, {bool input = false}) {
          final b = BuildingState(
            id: 'x',
            defId: defId,
            crew: 1,
            depositResourceId: defId == 'mine' ? 'iron_ore' : null,
          );
          final flow = fullRateFlow(c1, kora, b, 1, 1);
          return (input ? flow.inputs : flow.outputs)[id]!.toDouble();
        }

        const f = 1.331;
        expect(
          rate('mine', 'iron_ore'),
          closeTo(plain('mine', 'iron_ore') * f, 1e-9),
        );
        expect(
          rate('smelter', 'steel'),
          closeTo(plain('smelter', 'steel') * f, 1e-9),
        );
        expect(
          rate('plate_press', 'hull_plate'),
          plain('plate_press', 'hull_plate'),
        );
        expect(
          rate('habitat', 'food', input: true),
          plain('habitat', 'food', input: true),
        );
      });

      test('production speed from a tier to a tier leaves the tiers outside '
          'alone', () {
        final c2 = contentWithBonuses([
          {
            'kind': 'productionSpeedMultiplier',
            'amount': 1.1,
            'appliesToMinTier': 1,
            'appliesToMaxTier': 2,
          },
        ]);
        final s = GameEngine(c2).newGame(1);
        s.faction('player').megaprojectLevels['boost'] = 2;
        final bonuses = bonusesFor(s, c2, 'player');
        expect(bonuses.productionSpeedFactors[0], 1);
        expect(bonuses.productionSpeedFactors[1], closeTo(1.21, 1e-12));
        expect(bonuses.productionSpeedFactors[2], closeTo(1.21, 1e-12));
        expect(bonuses.productionSpeedFactors[3], 1);
        final kora = s.body('kora');
        double out(String defId, String id, EmpireBonuses with_) {
          final b = BuildingState(
            id: 'x',
            defId: defId,
            crew: 1,
            depositResourceId: defId == 'mine' ? 'iron_ore' : null,
          );
          return fullRateFlow(
            c2,
            kora,
            b,
            1,
            1,
            bonuses: with_,
          ).outputs[id]!.toDouble();
        }

        // The mine (tier 0) is untouched; the smelter (1) and the press (2)
        // run faster.
        expect(
          out('mine', 'iron_ore', bonuses),
          out('mine', 'iron_ore', EmpireBonuses.none),
        );
        for (final (defId, id) in [
          ('smelter', 'steel'),
          ('plate_press', 'hull_plate'),
        ]) {
          expect(
            out(defId, id, bonuses),
            closeTo(out(defId, id, EmpireBonuses.none) * 1.21, 1e-9),
          );
        }
        final shown = megaprojectBonusesAt(c2.megaprojects['boost']!, 2).single;
        expect(shown.appliesToMinTier, 1);
        expect(shown.appliesToMaxTier, 2);
      });

      test('the engine, the local use auto-sell keeps and the report all '
          'run at the bonus speed', () {
        final s = at(2);
        final kora = s.body('kora');
        final mine = kora.buildings.firstWhere((b) => b.defId == 'mine');
        // Kora's one smelter, kept in ore.
        kora.stock['iron_ore'] = n(500);
        final eng = GameEngine(c);
        eng.advance(s, 60);
        final before = s.faction('player').lifetimeProduced['steel']!;
        eng.advance(s, 60);
        final made = (s.faction('player').lifetimeProduced['steel']! - before)
            .toDouble();
        final speed = 1.21;
        // A smelter makes 1 steel per 5 s cycle.
        expect(made, closeTo(60 / 5 * speed, 1e-6));
        final report = buildFlowReport(s, c, 'player');
        expect(
          report.producedPerSec('steel').toDouble(),
          closeTo(made / 60, 1e-9),
        );
        final rule = AutoSellRule(
          bodyId: 'kora',
          resourceId: 'iron_ore',
          keepAtLeast: const BigNum.zero(),
        );
        // The smelter's use over a 60 s step: 2 ore per 5 s cycle.
        expect(
          autoSellKeep(s, c, rule, 60).localUse.toDouble(),
          closeTo(60 / 5 * 2 * speed, 1e-6),
        );
        expect(mine.lastRunFraction, greaterThan(0));
      });

      test('both stay finite at level 1000', () {
        final s = at(1000);
        final b = bonusesFor(s, c, 'player');
        for (var tier = 0; tier <= ResourceDef.megaprojectTier; tier++) {
          expect(b.marketDepthMultiplierFor(tier).isFinite, isTrue);
          expect(
            b.marketDepthMultiplierFor(tier),
            lessThanOrEqualTo(EmpireBonuses.maxMultiplier),
          );
          expect(b.productionSpeedFor(tier).isFinite, isTrue);
          expect(
            b.productionSpeedFor(tier),
            lessThanOrEqualTo(EmpireBonuses.maxMultiplier),
          );
        }
        s.body('kora').stock['steel'] = n(1e9);
        final sale = sell(s, c, 'player', 'kora', 'steel', n(1e9));
        expect(sale.revenue.toDouble().isFinite, isTrue);
        GameEngine(c).advance(s, 600);
        for (final v in s.body('kora').stock.values) {
          expect(v.toDouble().isFinite, isTrue);
        }
        final shown = megaprojectBonusesAt(boost, 1000);
        expect([for (final x in shown) x.value.isFinite], [true, true]);
      });

      test('the typed description gives each bonus at a level', () {
        final station = content.megaprojects['orbital_station']!;
        final at3 = megaprojectBonusesAt(station, 3);
        expect(
          [for (final b in at3) (b.kind, b.appliesToMaxTier)],
          [
            (BonusKind.storagePercent, null),
            (BonusKind.housingPercent, null),
            (BonusKind.offlineCapSeconds, null),
            (BonusKind.marketDepthMultiplier, null),
          ],
        );
        expect([for (final b in at3.take(3)) b.value], [30, 15, 10800]);
        // 1.25 cubed: the shipped station deepens markets ×1.25 a level.
        expect(at3.last.value, closeTo(1.953125, 1e-12));
        final boosted = megaprojectBonusesAt(boost, 2);
        expect(boosted.first.appliesToMaxTier, 1);
        expect(boosted.first.value, closeTo(1.44, 1e-12));
        expect(megaprojectBonusesAt(station, 0).last.value, 1);
      });
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

    test('progress toward the next level while a stage is under way loads, '
        'complete or not', () {
      final next = megaprojectCost(content, station, 1);
      for (final progress in [
        {'hull_plate': '1'},
        {
          for (final MapEntry(:key, :value) in next.entries)
            key: value.toJson(),
        },
      ]) {
        final r = decode(
          save(projects: [stage()], progress: {'orbital_station': progress}),
        );
        expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
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
      'progress past the next level cost while a stage is under way': save(
        projects: [stage()],
        progress: {
          'orbital_station': {
            'hull_plate': megaprojectCost(
              content,
              station,
              1,
            )['hull_plate']!.mulDouble(1.5).toJson(),
          },
        },
      ),
      'progress past the highest level while its last stage is under way': save(
        levels: {'orbital_station': 999},
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
      'a multiplier below 1': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {'kind': 'marketDepthMultiplier', 'amount': 0.9},
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].amount: must be >= '
            '1 for a multiplier',
      ),
      'a tier on a bonus that takes none': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {'kind': 'storagePercent', 'amount': 10, 'appliesToMaxTier': 1},
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].appliesToMaxTier: '
            'only multiplier bonuses take a tier',
      ),
      'a tier out of range': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {
              'kind': 'productionSpeedMultiplier',
              'amount': 1.1,
              'appliesToMaxTier': 9,
            },
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].appliesToMaxTier: '
            'must be <= 4',
      ),
      'a lowest tier on a bonus that takes none': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {'kind': 'housingPercent', 'amount': 5, 'appliesToMinTier': 1},
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].appliesToMinTier: '
            'only multiplier bonuses take a tier',
      ),
      'a lowest tier out of range': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {
              'kind': 'productionSpeedMultiplier',
              'amount': 1.1,
              'appliesToMinTier': 5,
            },
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].appliesToMinTier: '
            'must be <= 4',
      ),
      'a lowest tier above the highest': (
        {
          ...stationJson(),
          'bonusesPerLevel': [
            {
              'kind': 'productionSpeedMultiplier',
              'amount': 1.1,
              'appliesToMinTier': 2,
              'appliesToMaxTier': 1,
            },
          ],
        },
        'megaprojects.orbital_station.bonusesPerLevel[0].appliesToMinTier: '
            'must be <= appliesToMaxTier (1)',
      ),
      'a requirement on an unknown megaproject': (
        {
          ...stationJson(),
          'requiresMegaproject': {'dyson': 1},
        },
        "megaprojects.orbital_station.requiresMegaproject: unknown "
            "megaproject 'dyson'",
      ),
      'a required level below 1': (
        {
          ...stationJson(),
          'requiresMegaproject': {'orbital_station': 0},
        },
        'megaprojects.orbital_station.requiresMegaproject.orbital_station: '
            'must be >= 1',
      ),
      'a required level past the highest any megaproject reaches': (
        {
          ...stationJson(),
          'requiresMegaproject': {'orbital_station': 1001},
        },
        'megaprojects.orbital_station.requiresMegaproject.orbital_station: '
            'must be <= 1000',
      ),
      'a megaproject that requires itself': (
        {
          ...stationJson(),
          'requiresMegaproject': {'orbital_station': 1},
        },
        'megaprojects.orbital_station.requiresMegaproject: can never open: '
            'it needs itself',
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

    test('two megaprojects that require each other are reported', () {
      final b = shippedBundle()
        ..['megaprojects'] = [
          {
            ...stationJson(),
            'requiresMegaproject': {'boost': 1},
          },
          {
            ...stationJson(),
            'id': 'boost',
            'requiresMegaproject': {'orbital_station': 1},
          },
        ];
      expect(
        (Content.fromBundle(b) as ContentInvalid).errors,
        containsAll([
          'megaprojects.orbital_station.requiresMegaproject: can never open: '
              'it needs itself',
          'megaprojects.boost.requiresMegaproject: can never open: it needs '
              'itself',
        ]),
      );
    });

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
