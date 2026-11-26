import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

GameEngine _engine() => GameEngine(
  (Content.fromBundle(loadContentDir('../../content')) as ContentOk).content,
);

/// Plays like [inner] and keeps the state it was last shown, which is the
/// session's live state, so a test can read it after the session ends.
/// Plans one valid command, then one the engine rejects, through
/// [planCommands] as the real bots do.
final class _BrokenBot implements Bot {
  @override
  String get name => 'broken';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    var step = 0;
    return planCommands(
      e,
      s,
      (w) => switch (step++) {
        0 => SetAutoSellCommand(factionId, 'kora', 'steel', BigNum.from(1)),
        1 => DemolishCommand(factionId, 'no_such_building'),
        _ => const DemolishCommand('player', 'never_reached'),
      },
    );
  }
}

final class _Spy implements Bot {
  _Spy(this.inner);

  final Bot inner;
  GameState? state;

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    state = s;
    return inner.decide(e, s, factionId);
  }
}

/// Counts [inner]'s commands per 6 h check-in, auto-sell rules aside.
final class _Counter implements Bot {
  _Counter(this.inner);

  final Bot inner;
  final Map<int, int> perCheckIn = {};

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final cmds = inner.decide(e, s, factionId);
    final i = s.time ~/ 21600;
    perCheckIn[i] =
        (perCheckIn[i] ?? 0) +
        cmds.where((c) => c is! SetAutoSellCommand).length;
    return cmds;
  }
}

void main() {
  test('greedy bot makes progress in 24h', () {
    final e = _engine();
    final startCredits = e.newGame(1).factions.single.credits;
    final spy = _Spy(GreedyBot());
    final r = runBotSession(e, spy, seed: 1, hours: 24);
    expect(spy.state!.factions.single.credits, greaterThan(startCredits));
    expect(r.milestones, isNotEmpty);
  });

  test("balanced bot reaches 'own 2 bodies' within 72h", () {
    final r = runBotSession(_engine(), BalancedBot(), seed: 1, hours: 72);
    final hit = r.milestones.where((m) => m.id == 'own_2_bodies');
    expect(hit, hasLength(1), reason: r.toMarkdown());
    expect(hit.single.gameHours, lessThanOrEqualTo(72));
  });

  test('balanced bot reaches every milestone within a week', () {
    // The magnet chain needs a slot on a body that is full by then; the
    // bot buys one rather than giving up on the magnet works.
    GameState? end;
    final r = runBotSession(
      _engine(),
      BalancedBot(),
      seed: 1,
      hours: 192,
      onFinished: (s) => end = s,
    );
    expect(
      r.milestonesNotReached.map((m) => m.id),
      isEmpty,
      reason: r.toMarkdown(),
    );
    expect(
      r.milestones.where((m) => m.gameHours > 168).map((m) => m.id),
      isEmpty,
      reason: r.toMarkdown(),
    );
    expect(r.rejectedCommands, 0);
    // Its goods made on different bodies, the Orbital Station still gets
    // built, a day later: the bot routes them to one body. (Station
    // pacing is retuned with the bots in Task 8.)
    expect(
      end!.faction('player').megaprojectLevels['orbital_station'],
      greaterThanOrEqualTo(1),
    );
  });

  test('bot commands are valid and sessions are deterministic', () {
    final e = _engine();
    final a = runBotSession(e, BalancedBot(), seed: 1, hours: 48);
    final b = runBotSession(e, BalancedBot(), seed: 1, hours: 48);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect(a.rejectedCommands, 0);
    expect(
      runBotSession(e, GreedyBot(), seed: 1, hours: 24).rejectedCommands,
      0,
    );
  });

  test('auto-sell keeps a minute of what a body uses', () {
    final e = _engine();
    final s = e.newGame(1);
    final kora = s.body('kora');
    final smelter = kora.buildings.firstWhere((b) => b.defId == 'smelter');
    // Fast enough that a minute of its ore is more than a quarter of storage.
    smelter.levels[UpgradeTrack.speed] = 25;
    final perSec = fullRateFlow(
      e.content,
      kora,
      smelter,
      1,
      crewEfficiency(s, e.content, 'player'),
    ).inputs['iron_ore']!;
    final cap = storageCap(s, e.content, kora);
    expect(perSec.mulDouble(60), greaterThan(cap.mulDouble(0.25)));
    expect(perSec.mulDouble(60), lessThan(cap));

    final rule = GreedyBot()
        .decide(e, s, 'player')
        .whereType<SetAutoSellCommand>()
        .firstWhere((c) => c.bodyId == 'kora' && c.resourceId == 'iron_ore');
    expect(rule.keepAtLeast!.toDouble(), closeTo(perSec.toDouble() * 60, 1e-6));
  });

  group('a megaproject stage', () {
    /// A new game with the goods and credits for the next Orbital Station
    /// stage on Kora.
    GameState stocked(GameEngine e) {
      final s = e.newGame(1)..faction('player').credits = BigNum.from(1e9);
      final station = e.content.megaprojects['orbital_station']!;
      for (final MapEntry(:key, :value) in megaprojectCost(
        e.content,
        station,
        0,
      ).entries) {
        if (key != 'credits') s.body('kora').stock[key] = value;
      }
      return s;
    }

    for (final bot in [BalancedBot(), CasualBot(), GreedyBot()]) {
      test('is started by the ${bot.name} bot when it can afford one', () {
        final e = _engine();
        final s = stocked(e);
        final cmds = bot.decide(e, s, 'player');
        expect(
          cmds.whereType<StartMegaprojectStageCommand>().single.toJson(),
          const StartMegaprojectStageCommand(
            'player',
            'orbital_station',
            'kora',
          ).toJson(),
        );
        for (final cmd in cmds) {
          expect(e.apply(s, cmd), isA<CommandOk>());
        }
      });
    }

    test('is not started when the goods are short', () {
      final e = _engine();
      final s = stocked(e)..body('kora').stock['reactor_core'] = BigNum.from(1);
      expect(
        BalancedBot()
            .decide(e, s, 'player')
            .whereType<StartMegaprojectStageCommand>(),
        isEmpty,
      );
    });

    test("auto-sell keeps the next stage's goods", () {
      final e = _engine();
      final s = e.newGame(1)
        ..body('kora').stock['station_segment'] = BigNum.from(1);
      // At level 5 a stage needs more than a quarter of Kora's storage.
      s.faction('player').megaprojectLevels['orbital_station'] = 5;
      final need = megaprojectCost(
        e.content,
        e.content.megaprojects['orbital_station']!,
        5,
      )['station_segment']!;
      final cap = storageCap(s, e.content, s.body('kora'));
      expect(need, greaterThan(cap.mulDouble(0.25)));
      expect(need, lessThan(cap));
      final rule = GreedyBot()
          .decide(e, s, 'player')
          .whereType<SetAutoSellCommand>()
          .firstWhere(
            (c) => c.bodyId == 'kora' && c.resourceId == 'station_segment',
          );
      expect(rule.keepAtLeast, need);
    });
  });

  test('bots never buy a maxed upgrade track', () {
    // Smelter efficiency made nearly free, so it is the cheapest purchase,
    // and taken to its floor, where it can no longer help.
    final bundle = loadContentDir('../../content');
    final smelter = (bundle['buildings']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((b) => b['id'] == 'smelter');
    ((smelter['upgrades']! as Map)['efficiency']! as Map)['baseCredits'] =
        '1e-9';
    final e = GameEngine((Content.fromBundle(bundle) as ContentOk).content);
    final s = e.newGame(1);
    final b = s.body('kora').buildings.firstWhere((b) => b.defId == 'smelter');
    b.levels[UpgradeTrack.efficiency] = 60;
    expect(
      upgradeMaxedReason(e.content, b, UpgradeTrack.efficiency),
      isNotNull,
    );
    for (final bot in [GreedyBot(), BalancedBot()]) {
      final cmds = bot.decide(e, s, 'player');
      expect(
        cmds.whereType<UpgradeCommand>().where(
          (c) => c.buildingId == b.id && c.track == UpgradeTrack.efficiency,
        ),
        isEmpty,
        reason: bot.name,
      );
    }
  });

  test('bots name themselves', () {
    expect(GreedyBot().name, 'greedy');
    expect(BalancedBot().name, 'balanced');
    expect(CasualBot().name, 'casual');
  });

  test('casual bot plays like balanced on a command budget per check-in', () {
    final counter = _Counter(CasualBot(commandsPerCheckIn: 5));
    final r = runBotSession(_engine(), counter, seed: 1, hours: 24);
    expect(r.rejectedCommands, 0);
    expect(counter.perCheckIn.keys, [0, 1, 2, 3]);
    for (final n in counter.perCheckIn.values) {
      expect(n, inInclusiveRange(1, 5));
    }
  });

  test('a command rejected while planning ends the plan and is returned', () {
    final e = _engine();
    final cmds = _BrokenBot().decide(e, e.newGame(1), 'player');
    expect(cmds, hasLength(2));
    expect(cmds.last, isA<DemolishCommand>());
  });

  test('rejected bot commands are counted in the report', () {
    // 18 decisions per check-in, one rejected command in each.
    final r = runBotSession(_engine(), _BrokenBot(), seed: 1, hours: 12);
    expect(r.rejectedCommands, 2 * 18);
  });

  group('contracts', () {
    /// A new game with one contract for [quantity] of [resourceId] on the
    /// player's board, and [stock] of it on Kora.
    (GameState, ContractState) withContract(
      GameEngine e,
      String resourceId,
      num quantity, {
      num stock = 0,
    }) {
      final s = e.newGame(1);
      final f = s.faction('player')..contractRefillAt.clear();
      final k = ContractState(
        id: s.newId('c'),
        templateId: e.content.contractTemplates.keys.first,
        resourceId: resourceId,
        quantity: BigNum.from(quantity),
        rewardCredits: BigNum.from(1000),
        postedAt: 0,
      );
      f.contracts.add(k);
      s.body('kora').stock[resourceId] = BigNum.from(stock);
      return (s, k);
    }

    for (final bot in [BalancedBot(), CasualBot(), GreedyBot()]) {
      test('the ${bot.name} bot delivers spare stock and completes it', () {
        final e = _engine();
        final (s, k) = withContract(e, 'steel', 100, stock: 600);
        final cmds = bot.decide(e, s, 'player');
        expect(
          cmds.whereType<DeliverContractCommand>().single.toJson(),
          DeliverContractCommand(
            'player',
            k.id,
            'kora',
            BigNum.from(100),
          ).toJson(),
        );
        for (final cmd in cmds) {
          expect(e.apply(s, cmd), isA<CommandOk>());
        }
        expect(s.faction('player').contractsCompleted, 1);
      });

      test('the ${bot.name} bot discards a contract nothing makes', () {
        final e = _engine();
        final (s, k) = withContract(e, 'reactor_core', 10);
        final cmds = bot.decide(e, s, 'player');
        expect(
          cmds.whereType<DiscardContractCommand>().single.toJson(),
          DiscardContractCommand('player', k.id).toJson(),
        );
        for (final cmd in cmds) {
          expect(e.apply(s, cmd), isA<CommandOk>());
        }
      });
    }

    test('a contract it can work toward is kept, its goods held back', () {
      final e = _engine();
      // Kora makes steel; none spare yet.
      final (s, k) = withContract(e, 'steel', 300);
      final plain = withContract(e, 'iron_ore', 100).$1
        ..faction('player').contracts.clear();
      SetAutoSellCommand? steelRule(GameState g) => GreedyBot()
          .decide(e, g, 'player')
          .whereType<SetAutoSellCommand>()
          .where((c) => c.bodyId == 'kora' && c.resourceId == 'steel')
          .firstOrNull;
      s.body('kora').stock['steel'] = BigNum.from(1);
      plain.body('kora').stock['steel'] = BigNum.from(1);
      final cmds = GreedyBot().decide(e, s, 'player');
      expect(cmds.whereType<DiscardContractCommand>(), isEmpty);
      expect(cmds.whereType<DeliverContractCommand>(), isEmpty);
      expect(s.faction('player').contracts, [k]);
      final base = steelRule(plain)?.keepAtLeast ?? const BigNum.zero();
      expect(steelRule(s)!.keepAtLeast, base + BigNum.from(300));
    });
  });

  group('surveys', () {
    GameState withDrones(GameEngine e) {
      final s = e.newGame(1);
      s.faction('player').credits = BigNum.from(1e9);
      s.body('kora').stock['survey_drone'] = BigNum.from(3);
      return s;
    }

    for (final bot in [GreedyBot(), BalancedBot()]) {
      test('the ${bot.name} bot surveys a hidden body once it has drones', () {
        final e = _engine();
        final s = withDrones(e);
        final cmds = bot.decide(e, s, 'player');
        expect(
          cmds.whereType<SurveyCommand>().single.bodyId,
          'tessaly',
          reason: '$cmds',
        );
      });

      test('the ${bot.name} bot does not survey without drones', () {
        final e = _engine();
        final s = withDrones(e)..body('kora').stock.remove('survey_drone');
        expect(bot.decide(e, s, 'player').whereType<SurveyCommand>(), isEmpty);
      });
    }

    test('the balanced bot surveys one body at a time', () {
      final e = _engine();
      final s = withDrones(e)
        ..body('kora').stock['survey_drone'] = BigNum.from(9);
      final cmds = BalancedBot().decide(e, s, 'player');
      expect(cmds.whereType<SurveyCommand>(), hasLength(1));
    });

    test('the balanced bot claims a body once it is surveyed', () {
      final e = _engine();
      final s = withDrones(e);
      for (final b in s.bodies.where((b) => b.surveyed)) {
        b.ownerId ??= 'player';
      }
      s.body('kora').stock['outpost_kit'] = claimCost(
        s,
        e.content,
        'player',
      )['outpost_kit']!;
      s.body('dusk_cairn').surveyed = true;
      final cmds = BalancedBot().decide(e, s, 'player');
      expect(
        cmds.whereType<ClaimBodyCommand>().map((c) => c.bodyId),
        contains('dusk_cairn'),
      );
      expect(
        cmds.whereType<ClaimBodyCommand>().map((c) => c.bodyId),
        isNot(contains('tessaly')),
      );
    });
  });
}
