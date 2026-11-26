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

/// Plays like [inner], keeping every command it issues.
final class _Log implements Bot {
  _Log(this.inner);

  final Bot inner;
  final List<Command> issued = [];

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final cmds = inner.decide(e, s, factionId);
    issued.addAll(cmds);
    return cmds;
  }
}

void main() {
  test('ships move as shipments, and every route stops at what it needs', () {
    final bot = _Log(BalancedBot());
    final r = runBotSession(_engine(), bot, seed: 1, hours: 168);
    expect(r.rejectedCommands, 0);
    final routes = bot.issued.whereType<CreateRouteCommand>().toList();
    // Cargo ships go to a body as a move, not a route.
    expect(routes.where((c) => c.resourceId == 'cargo_ship'), isEmpty);
    final moves = bot.issued.whereType<MoveShipsCommand>();
    expect(moves, isNotEmpty);
    expect(moves.map((m) => m.count), everyElement(greaterThan(0)));
    // A habitat's module comes one at a time.
    final modules = [
      for (final c in routes)
        if (c.resourceId == 'habitat_module') c.stopAtDestination,
    ];
    expect(modules, isNotEmpty);
    expect(modules, everyElement(BigNum.from(1)));
    // Routes feeding buildings pause once the destination holds what it
    // keeps for them; none fills a store.
    expect(routes.map((c) => c.stopAtDestination), everyElement(isNotNull));
  });

  test('new buildings come with their crew', () {
    final bot = _Log(CasualBot());
    runBotSession(_engine(), bot, seed: 1, hours: 48);
    final builds = bot.issued.whereType<BuildCommand>().toList();
    expect(builds, isNotEmpty);
    expect(builds.map((b) => b.autoCrew), everyElement(isTrue));
  });

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

  test('balanced bot reaches every early milestone within a week', () {
    // The magnet chain needs a slot on a body that is full by then; the
    // bot buys one rather than giving up on the magnet works. Only the
    // milestones of goods made, bodies owned and credits up to a billion
    // are due by then; the rest (contracts, megaproject levels, surveys,
    // rates, waste-free time, later credits) are paced over the weeks.
    final early = {
      for (final m in _engine().content.milestones)
        if (switch (m.condition) {
          ProducedCondition() || BodiesOwnedCondition() => true,
          CreditsEarnedCondition(:final amount) => amount <= BigNum.from(1e9),
          _ => false,
        })
          m.id,
    };
    expect(early.length, greaterThanOrEqualTo(19));
    final r = runBotSession(_engine(), BalancedBot(), seed: 1, hours: 192);
    expect(
      r.milestonesNotReached.map((m) => m.id).where(early.contains),
      isEmpty,
      reason: r.toMarkdown(),
    );
    expect(
      r.milestones
          .where((m) => early.contains(m.id) && m.gameHours > 168)
          .map((m) => m.id),
      isEmpty,
      reason: r.toMarkdown(),
    );
    expect(r.rejectedCommands, 0);
    // The optimizer gets five bodies within three days.
    final five = r.milestones.singleWhere((m) => m.id == 'own_5_bodies');
    expect(five.gameHours, lessThanOrEqualTo(72));
  });

  group('the Orbital Station is paced', () {
    // Station goods come from bodies all over the system and add up in
    // deliveries: a casual player reaches level 1 in days 4 to 6 and level
    // 3 in two to three weeks; the optimizer gets there sooner and keeps
    // building.
    late BalanceReport casual;
    late BalanceReport balanced;
    setUpAll(() {
      casual = runBotSession(_engine(), CasualBot(), seed: 1, hours: 504);
      balanced = runBotSession(_engine(), BalancedBot(), seed: 1, hours: 336);
    });

    double hoursTo(BalanceReport r, String id) => r.milestones
        .singleWhere(
          (m) => m.id == id,
          orElse: () {
            fail('${r.botName}: $id not reached\n${r.toMarkdown()}');
          },
        )
        .gameHours;

    test('a casual player reaches level 1 in days 4 to 6', () {
      expect(hoursTo(casual, 'station_1'), inInclusiveRange(72, 144));
    });

    test('and level 3 within three weeks, not before the second', () {
      expect(hoursTo(casual, 'station_3'), inInclusiveRange(240, 504));
    });

    test('the optimizer reaches level 3 sooner, and more by day 14', () {
      expect(
        hoursTo(balanced, 'station_3'),
        lessThan(hoursTo(casual, 'station_3')),
      );
      expect(
        balanced.dayEnds.last.megaprojectLevels['orbital_station'],
        greaterThan(3),
      );
    });

    test('a casual player sees something new on 5 of every 7 days', () {
      expect(casual.worstWeekWithNewThings(21), greaterThanOrEqualTo(5));
      expect(casual.rejectedCommands, 0);
    });
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
    /// A new game with [share] of the goods for the next Orbital Station
    /// stage on Kora, the rest on Hollow Reach (the player's too), and a
    /// billion credits.
    GameState stocked(GameEngine e, {double share = 1}) {
      final s = e.newGame(1)..faction('player').credits = BigNum.from(1e9);
      s.body('hollow_reach').ownerId = 'player';
      final station = e.content.megaprojects['orbital_station']!;
      for (final MapEntry(:key, :value) in megaprojectCost(
        e.content,
        station,
        0,
      ).entries) {
        if (key == 'credits') continue;
        s.body('kora').stock[key] = value.mulDouble(share);
        if (share < 1) {
          s.body('hollow_reach').stock[key] = value.mulDouble(1 - share);
        }
      }
      return s;
    }

    for (final bot in [BalancedBot(), CasualBot(), GreedyBot()]) {
      test('is paid for and started by the ${bot.name} bot', () {
        final e = _engine();
        final s = stocked(e);
        final cmds = bot.decide(e, s, 'player');
        final deliveries = cmds.whereType<DeliverToMegaprojectCommand>();
        expect(deliveries.map((d) => d.bodyId), ['kora', 'kora']);
        // Goods first, then the credits once every good is in.
        expect(deliveries.last.amounts.keys, ['credits']);
        for (final cmd in cmds) {
          expect(e.apply(s, cmd), isA<CommandOk>());
        }
        expect(
          megaprojectStageOf(s, 'player', 'orbital_station'),
          isNotNull,
          reason: '$cmds',
        );
      });
    }

    test('is delivered from every body that holds its goods', () {
      final e = _engine();
      final s = stocked(e, share: 0.5);
      final cmds = BalancedBot().decide(e, s, 'player');
      expect(
        cmds.whereType<DeliverToMegaprojectCommand>().map((d) => d.bodyId),
        ['kora', 'hollow_reach', 'kora'],
      );
      for (final cmd in cmds) {
        expect(e.apply(s, cmd), isA<CommandOk>());
      }
      expect(megaprojectStageOf(s, 'player', 'orbital_station'), isNotNull);
    });

    test('takes what is held when the goods are short, and waits', () {
      final e = _engine();
      final s = stocked(e)..body('kora').stock['reactor_core'] = BigNum.from(1);
      final cmds = BalancedBot().decide(e, s, 'player');
      for (final cmd in cmds) {
        expect(e.apply(s, cmd), isA<CommandOk>());
      }
      expect(megaprojectStageOf(s, 'player', 'orbital_station'), isNull);
      final owed = megaprojectRemaining(
        s,
        e.content,
        'player',
        e.content.megaprojects['orbital_station']!,
      );
      expect(owed.keys, ['credits', 'reactor_core']);
    });

    test("auto-sell keeps what the next stage still lacks", () {
      final e = _engine();
      // A rule already set: the bot delivers the segment it holds, then
      // retunes the rule.
      final s = e.newGame(1)
        ..body('kora').stock['station_segment'] = BigNum.from(1);
      expect(
        e.apply(
          s,
          const SetAutoSellCommand(
            'player',
            'kora',
            'station_segment',
            BigNum.zero(),
          ),
        ),
        isA<CommandOk>(),
      );
      final station = e.content.megaprojects['orbital_station']!;
      final need = megaprojectCost(e.content, station, 0)['station_segment']!;
      s.faction('player').megaprojectProgress['orbital_station'] = {
        'station_segment': need.mulDouble(0.25),
      };
      final rule = GreedyBot()
          .decide(e, s, 'player')
          .whereType<SetAutoSellCommand>()
          .firstWhere(
            (c) => c.bodyId == 'kora' && c.resourceId == 'station_segment',
          );
      // Three quarters still lacking, less the one segment just delivered.
      expect(rule.keepAtLeast, need.mulDouble(0.75) - BigNum.from(1));
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
    /// A rich new game whose next Orbital Station stage has every drone
    /// it needs, with three more on Kora.
    GameState withDrones(GameEngine e) {
      final s = e.newGame(1);
      s.faction('player').credits = BigNum.from(1e9);
      s.body('kora').stock['survey_drone'] = BigNum.from(3);
      final station = e.content.megaprojects['orbital_station']!;
      s.faction('player').megaprojectProgress['orbital_station'] = {
        'survey_drone': megaprojectCost(e.content, station, 0)['survey_drone']!,
      };
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

    for (final bot in [GreedyBot(), BalancedBot()]) {
      test('the ${bot.name} bot keeps drones the station still needs', () {
        final e = _engine();
        final s = withDrones(e)..faction('player').megaprojectProgress.clear();
        final cmds = bot.decide(e, s, 'player');
        expect(cmds.whereType<SurveyCommand>(), isEmpty);
        expect(
          cmds.whereType<DeliverToMegaprojectCommand>().expand(
            (d) => d.amounts.keys,
          ),
          contains('survey_drone'),
        );
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
