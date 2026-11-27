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

/// Counts [inner]'s commands per 6 h check-in, auto-sell rules aside, and
/// keeps its buy-max commands.
final class _Counter implements Bot {
  _Counter(this.inner);

  final Bot inner;
  final Map<int, int> perCheckIn = {};

  /// Check-in index to the [BuyUpgradesCommand]s issued in it, with the
  /// credits held when each applied, whether a megaproject then took
  /// credits on its own, and the levels it bought.
  final Map<int, List<(BuyUpgradesCommand, BigNum, bool, int)>> buyMax = {};

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final cmds = inner.decide(e, s, factionId);
    final i = s.time ~/ 21600;
    perCheckIn[i] =
        (perCheckIn[i] ?? 0) +
        cmds.where((c) => c is! SetAutoSellCommand).length;
    // The credits held when each buy-max command applies: after the
    // commands before it.
    final w = s.copy();
    for (final c in cmds) {
      final held = w.faction(factionId).credits;
      final funding = w
          .faction(factionId)
          .megaprojectAuto
          .values
          .any((a) => a.credits);
      final r = e.apply(w, c);
      if (c is BuyUpgradesCommand) {
        final levels = r is CommandOk && r.outcome is UpgradesBought
            ? (r.outcome! as UpgradesBought).levels
            : 0;
        (buyMax[i] ??= []).add((c, held, funding, levels));
      }
    }
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
  // One 8-day balanced session, seed 1, played once for the tests that
  // read it: a shorter session is the same up to its end.
  _Log? weekLog;
  BalanceReport? weekRun;
  BalanceReport week() => weekRun ??= runBotSession(
    _engine(),
    weekLog = _Log(BalancedBot()),
    seed: 1,
    hours: 192,
  );

  test('ships move as shipments, and every route stops at what it needs', () {
    final r = week();
    final bot = weekLog!;
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
    final r = week();
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
    final r = week();
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
    /// Units of each station good a body holds beyond its share: more
    /// than the bot keeps there for its own use, a quarter of storage.
    const spare = 300;

    /// A new game whose next Orbital Station stage already has 90% of
    /// each good, the rest held [share] on Kora and the rest on Hollow
    /// Reach (the player's too), each with [spare] more, and a billion
    /// credits.
    GameState stocked(GameEngine e, {double share = 0.5}) {
      final s = e.newGame(1)..faction('player').credits = BigNum.from(1e9);
      s.body('hollow_reach').ownerId = 'player';
      final station = e.content.megaprojects['orbital_station']!;
      final progress =
          s.faction('player').megaprojectProgress['orbital_station'] = {};
      for (final MapEntry(:key, :value) in megaprojectCost(
        e.content,
        station,
        0,
      ).entries) {
        if (key == 'credits') continue;
        final held = value - value.mulDouble(0.9).floor();
        progress[key] = value - held;
        s.body('kora').stock[key] = held.mulDouble(share) + BigNum.from(spare);
        s.body('hollow_reach').stock[key] =
            held.mulDouble(1 - share) + BigNum.from(spare);
      }
      return s;
    }

    /// Plays [bot] on [s] for [checkIns] check-ins: a decision, its
    /// commands applied, then two game minutes, so the engine's
    /// auto-delivery runs and the casual bot starts a new check-in. Every
    /// command issued, in order.
    List<Command> play(GameEngine e, Bot bot, GameState s, int checkIns) {
      final issued = <Command>[];
      for (var i = 0; i < checkIns; i++) {
        for (final cmd in bot.decide(e, s, 'player')) {
          expect(e.apply(s, cmd), isA<CommandOk>(), reason: '$cmd');
          issued.add(cmd);
        }
        e.advance(s, 120);
      }
      return issued;
    }

    for (final bot in [BalancedBot(), CasualBot(), GreedyBot()]) {
      test('is fed and started on its own by the ${bot.name} bot', () {
        final e = _engine();
        final s = stocked(e);
        final issued = play(e, bot, s, 3);
        // Goods and credits on their own once the station is open and
        // every good its stage lacks is held: nothing by hand.
        expect(issued.whereType<DeliverToMegaprojectCommand>(), isEmpty);
        final settings = issued
            .whereType<SetMegaprojectAutoCommand>()
            .where((c) => c.megaprojectId == 'orbital_station')
            .toList();
        expect(settings.first.goods, GoodsFeedMode.nearReady);
        expect(settings.first.credits, isTrue);
        expect(
          megaprojectStageOf(s, 'player', 'orbital_station'),
          isNotNull,
          reason: '$issued',
        );
      });
    }

    test('keeps an hour of income when the credits go in on their own', () {
      final e = _engine();
      final s = e.newGame(1);
      // Half an hour of play, so auto-sell earns an income.
      play(e, BalancedBot(), s, 15);
      final station = e.content.megaprojects['orbital_station']!;
      // The stage's credits, but not an hour of income besides.
      s.faction('player').credits = megaprojectCost(
        e.content,
        station,
        0,
      )['credits']!;
      s.faction('player').megaprojectProgress['orbital_station'] = {
        for (final MapEntry(:key, :value) in megaprojectCost(
          e.content,
          station,
          0,
        ).entries)
          if (key != 'credits') key: value,
      };
      final cmds = BalancedBot().decide(e, s, 'player');
      final cmd = cmds.whereType<SetMegaprojectAutoCommand>().single;
      final income = buildFlowReport(
        s,
        e.content,
        'player',
      ).creditsPerSec.toDouble();
      expect(income, greaterThan(0));
      expect(cmd.goods, GoodsFeedMode.nearReady);
      expect(cmd.credits, isTrue);
      // The shared reserve is set first, before any credits go in.
      final reserve = cmds.whereType<SetAutoPayReserveCommand>().single;
      expect(cmds.indexOf(reserve), lessThan(cmds.indexOf(cmd)));
      expect(reserve.credits.toDouble(), closeTo(income * 3600, 1));
    });

    test('two megaprojects lacking only credits both get them, above one '
        'shared reserve', () {
      // With a reserve each, the lower one took every credit for good: a
      // stage short of only credits behind it never filled.
      final e = _engine();
      final s = e.newGame(1);
      play(e, BalancedBot(), s, 15);
      final f = s.faction('player');
      f.megaprojectLevels['orbital_station'] = 1;
      for (final m in e.content.megaprojects.values) {
        f.megaprojectProgress[m.id] = {
          for (final MapEntry(:key, :value) in megaprojectCost(
            e.content,
            m,
            megaprojectDeliveryLevel(s, 'player', m),
          ).entries)
            if (key != 'credits') key: value,
        };
      }
      // More than an hour of income, less than either stage's credits.
      f.credits = BigNum.from(2e5);
      play(e, BalancedBot(), s, 1);
      expect(f.autoPayReserve > const BigNum.zero(), isTrue);
      final paid = [
        for (final m in ['orbital_station', 'mass_driver'])
          f.megaprojectProgress[m]!['credits'],
      ];
      for (final m in ['orbital_station', 'mass_driver']) {
        expect(f.megaprojectAuto[m]!.credits, isTrue, reason: m);
      }
      expect(paid.first, isNotNull, reason: 'the station got none');
      // Split 2:1, the balanced bot's weights, odd credits aside.
      expect(
        (paid.first! - paid.last!.mulDouble(2)).toDouble().abs(),
        lessThanOrEqualTo(3),
      );
    });

    test('a megaproject still locked is not set up', () {
      final e = _engine();
      final cmds = BalancedBot().decide(e, e.newGame(1), 'player');
      expect(
        cmds.whereType<SetMegaprojectAutoCommand>().map((c) => c.megaprojectId),
        ['orbital_station'],
      );
    });

    test('goes on being fed while a stage runs', () {
      final e = _engine();
      final s = stocked(e);
      play(e, BalancedBot(), s, 3);
      expect(megaprojectStageOf(s, 'player', 'orbital_station'), isNotNull);
      // Segments made while level 1 runs go to level 2.
      s.body('hollow_reach').stock['station_segment'] = BigNum.from(40);
      play(e, BalancedBot(), s, 1);
      expect(megaprojectStageOf(s, 'player', 'orbital_station'), isNotNull);
      expect(
        s
            .faction('player')
            .megaprojectProgress['orbital_station']!['station_segment'],
        BigNum.from(40),
      );
    });

    test('is fed from every body that holds its goods', () {
      final e = _engine();
      // Kora alone does not hold enough segments for the stage.
      final s = stocked(e)
        ..body('kora').stock['station_segment'] = BigNum.from(1);
      play(e, BalancedBot(), s, 3);
      expect(megaprojectStageOf(s, 'player', 'orbital_station'), isNotNull);
    });

    test('takes its credits on their own before its goods are in, once '
        'every good it lacks is made', () {
      final e = _engine();
      final s = stocked(e)..faction('player').credits = BigNum.from(1e4);
      final station = e.content.megaprojects['orbital_station']!;
      final f = s.faction('player');
      // Nothing held of hull plates: the stage lacks some, which Kora's
      // plate press makes.
      for (final body in ['kora', 'hollow_reach']) {
        s.body(body).stock.remove('hull_plate');
      }
      final cmds = BalancedBot().decide(e, s, 'player');
      final settings = cmds.whereType<SetMegaprojectAutoCommand>().toList();
      expect(settings.first.credits, isFalse, reason: 'nothing makes plates');
      // Its plan builds a plate press toward the stage, and the credits
      // then go in on their own, the plates still owed.
      final press = cmds.indexWhere(
        (c) => c is BuildCommand && c.defId == 'plate_press',
      );
      expect(press, greaterThanOrEqualTo(0));
      expect(settings.last.credits, isTrue);
      expect(cmds.indexOf(settings.last), greaterThan(press));
      for (final cmd in cmds) {
        expect(e.apply(s, cmd), isA<CommandOk>());
      }
      expect(
        megaprojectRemaining(s, e.content, 'player', station).keys,
        contains('hull_plate'),
      );
      expect(f.megaprojectAuto['orbital_station']!.credits, isTrue);
    });

    test('takes what is held when the goods are short, and waits', () {
      final e = _engine();
      // A reactor core short.
      final s = stocked(e);
      final cores = s.faction('player').megaprojectProgress['orbital_station']!;
      cores['reactor_core'] = cores['reactor_core']! - BigNum.from(1);
      for (final body in ['kora', 'hollow_reach']) {
        s.body(body).stock.remove('reactor_core');
      }
      play(e, BalancedBot(), s, 3);
      expect(megaprojectStageOf(s, 'player', 'orbital_station'), isNull);
      final owed = megaprojectRemaining(
        s,
        e.content,
        'player',
        e.content.megaprojects['orbital_station']!,
      );
      expect(owed.keys, ['credits', 'reactor_core']);
      // The credits wait in the bank for the goods.
      expect(
        s.faction('player').megaprojectAuto['orbital_station']!.credits,
        isFalse,
      );
    });

    test('auto-sell holds what a stage fed on its own lacks, once', () {
      final e = _engine();
      // Credits to pay for the stage: it is near ready, so fed at once.
      final s = e.newGame(1)
        ..body('kora').stock['station_segment'] = BigNum.from(1)
        ..faction('player').credits = BigNum.from(1e9);
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
      for (final cmd in GreedyBot().decide(e, s, 'player')) {
        expect(e.apply(s, cmd), isA<CommandOk>());
      }
      final rule = s
          .faction('player')
          .autoSell
          .singleWhere(
            (r) => r.bodyId == 'kora' && r.resourceId == 'station_segment',
          );
      // The bot's rule keeps none for the station: the engine's auto-sell
      // holds the three quarters still lacking.
      expect(rule.keepAtLeast, const BigNum.zero());
      expect(
        autoSellKeep(s, e.content, rule, 1).megaprojectHold,
        need.mulDouble(0.75),
      );
    });
  });

  group('growing the supply of a stage good', () {
    /// A new game with the Mass Driver open and [presses] plate presses on
    /// Kora, a minute played; each megaproject's next stage lacks only
    /// the hull plates [owed] lists of it (none for one not listed).
    GameState shape(GameEngine e, Map<String, int> owed, {int presses = 1}) {
      final c = e.content;
      final s = e.newGame(1);
      final f = s.faction('player');
      f.megaprojectLevels['orbital_station'] = 1;
      f.baseCrew += presses;
      for (var i = 0; i < presses; i++) {
        s
            .body('kora')
            .buildings
            .add(
              BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
            );
      }
      for (final m in c.megaprojects.values) {
        final cost = megaprojectCost(
          c,
          m,
          megaprojectDeliveryLevel(s, 'player', m),
        );
        f.megaprojectProgress[m.id] = {
          for (final MapEntry(key: id, value: v) in cost.entries)
            if (id != 'credits')
              id: id == 'hull_plate' ? v - BigNum.from(owed[m.id] ?? 0) : v,
        };
      }
      e.advance(s, 60);
      return s;
    }

    /// Hull plates Kora's presses make in a day: under 6,000.
    double day(GameEngine e, GameState s) =>
        buildFlowReport(
          s,
          e.content,
          'player',
        ).netProducedPerSec('hull_plate').toDouble() *
        86400;

    test('a good a stage lacks for more than a day gets a step', () {
      final e = _engine();
      final s = shape(e, {'orbital_station': 9000});
      expect(day(e, s), lessThan(9000));
      expect(growthStepFor(e, s, 'player', 'orbital_station'), isNotNull);
    });

    test('a good another megaproject takes first counts its need too', () {
      // Each alone comes within a day; the Mass Driver's comes after the
      // station's, which auto-delivery feeds first.
      final e = _engine();
      final s = shape(e, {'orbital_station': 4000, 'mass_driver': 3000});
      expect(day(e, s), inInclusiveRange(4000, 7000));
      expect(growthStepFor(e, s, 'player', 'orbital_station'), isNull);
      expect(growthStepFor(e, s, 'player', 'mass_driver'), isNotNull);
      final alone = shape(e, {'mass_driver': 3000});
      expect(growthStepFor(e, alone, 'player', 'mass_driver'), isNull);
    });

    test('a maker short of a good already being grown does not end the '
        'search', () {
      // The first press reads as short of hull plates themselves (a loop):
      // growing that leads nowhere, so the second press's steel is grown.
      final e = _engine();
      final s = shape(e, {'orbital_station': 9000}, presses: 2);
      final first = s
          .body('kora')
          .buildings
          .firstWhere((b) => b.defId == 'plate_press');
      first
        ..lastLimitReason = 'input:hull_plate'
        ..lastRunFraction = 0.5;
      expect(growthStepFor(e, s, 'player', 'orbital_station'), isNotNull);
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

  test('casual bot plays like balanced on a command budget per check-in, '
      'buying max once in each', () {
    final counter = _Counter(CasualBot(commandsPerCheckIn: 5));
    final r = runBotSession(_engine(), counter, seed: 1, hours: 24);
    expect(r.rejectedCommands, 0);
    expect(counter.perCheckIn.keys, [0, 1, 2, 3]);
    for (final n in counter.perCheckIn.values) {
      // The buy-max command is one of the five.
      expect(n, inInclusiveRange(1, 5));
    }
    expect(counter.buyMax.keys, [0, 1, 2, 3]);
    for (final buys in counter.buyMax.values) {
      final (cmd, held, _, _) = buys.single;
      expect(cmd.budget, lessThanOrEqualTo(held));
      expect(cmd.budget, greaterThanOrEqualTo(const BigNum.zero()));
    }
    final all = counter.buyMax.values.expand((b) => b).toList();
    // It buys levels.
    expect(all.any((b) => b.$4 > 0), isTrue);
    // It leaves what it saves for a goal (the first claim, on day 1),
    // with no megaproject taking credits on its own.
    expect(all.any((b) => !b.$3 && b.$1.budget < b.$2), isTrue);
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
          // One command from every body.
          DeliverContractCommand(
            'player',
            k.id,
            null,
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

    for (final bot in [BalancedBot(), CasualBot()]) {
      test('the ${bot.name} bot discards a contract it cannot fill within '
          'a day, and keeps one it can', () {
        final e = _engine();
        // Kora makes 0.2 steel a second: about 17K a day.
        final (far, k) = withContract(e, 'steel', 1e6, stock: 10);
        expect(
          bot
              .decide(e, far, 'player')
              .whereType<DiscardContractCommand>()
              .map((c) => c.contractId),
          [k.id],
        );
        final (near, _) = withContract(e, 'steel', 5000, stock: 10);
        expect(
          bot.decide(e, near, 'player').whereType<DiscardContractCommand>(),
          isEmpty,
        );
      });
    }

    test('the greedy bot keeps a contract it can work toward, however '
        'long it takes', () {
      final e = _engine();
      final (s, _) = withContract(e, 'steel', 1e6, stock: 10);
      expect(
        GreedyBot().decide(e, s, 'player').whereType<DiscardContractCommand>(),
        isEmpty,
      );
    });

    test('a contract it can work toward is kept, its goods held back '
        'once', () {
      final e = _engine();
      // Kora makes steel; none spare yet.
      final (s, k) = withContract(e, 'steel', 300);
      final plain = withContract(e, 'iron_ore', 100).$1
        ..faction('player').contracts.clear();
      for (final g in [s, plain]) {
        g.body('kora').stock['steel'] = BigNum.from(1);
      }
      AutoSellRule steelRule(GameState g) {
        for (final cmd in GreedyBot().decide(e, g, 'player')) {
          expect(e.apply(g, cmd), isA<CommandOk>());
        }
        return g
            .faction('player')
            .autoSell
            .singleWhere((r) => r.bodyId == 'kora' && r.resourceId == 'steel');
      }

      final rule = steelRule(s);
      expect(s.faction('player').contracts, [k]);
      // The bot's rule keeps what it keeps without the contract; the
      // engine's auto-sell holds the contract's 300.
      expect(rule.keepAtLeast, steelRule(plain).keepAtLeast);
      expect(
        autoSellKeep(s, e.content, rule, 1).contractHold,
        BigNum.from(300),
      );
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
        // The station takes them on its own, at the next game minute.
        for (final cmd in cmds) {
          expect(e.apply(s, cmd), isA<CommandOk>());
        }
        e.advance(s, 60);
        expect(
          s
              .faction('player')
              .megaprojectProgress['orbital_station']?['survey_drone'],
          BigNum.from(3),
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
