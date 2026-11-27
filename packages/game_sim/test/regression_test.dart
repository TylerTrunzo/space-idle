import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

GameEngine _engine() => GameEngine(
  (Content.fromBundle(loadContentDir('../../content')) as ContentOk).content,
);

String _encode(GameState s) => jsonEncode(s.toJson());

/// The state a [BalancedBot] session of [hours] ends in, a copy of each
/// one played once per run of this file: several tests start from the
/// same session.
GameState _played(GameEngine e, {required double hours}) =>
    (_sessions[hours] ??= () {
      late GameState end;
      runBotSession(
        e,
        BalancedBot(),
        seed: 1,
        hours: hours,
        onFinished: (s) => end = s,
      );
      return end;
    }()).copy();

final _sessions = <double, GameState>{};

/// Plays [days] of check-ins every 6 h with [bot] from a new game: one
/// decision, 180 s of play, then the offline catch-up to the next
/// check-in. Before each check-in [between] may hand back another state
/// to go on with.
GameState _checkIns(
  GameEngine e,
  Bot bot, {
  required int days,
  GameState Function(GameState s)? between,
}) {
  var s = e.newGame(1);
  final player = s.factions.firstWhere((f) => f.isPlayer).id;
  for (var i = 0; i < days * 4; i++) {
    if (between != null) s = between(s);
    for (final cmd in bot.decide(e, s, player)) {
      e.apply(s, cmd);
    }
    e.advance(s, 180);
    e.catchUpOffline(s, 21600 - 180);
  }
  return s;
}

/// [s] with the player feeding both megaprojects on its own: the station
/// goods and credits above 1M, the Mass Driver goods only.
GameState _feeding(GameEngine e, GameState s) {
  for (final cmd in [
    SetMegaprojectAutoCommand(
      'player',
      'orbital_station',
      true,
      BigNum.from(1e6),
    ),
    const SetMegaprojectAutoCommand('player', 'mass_driver', true, null),
  ]) {
    expect(e.apply(s, cmd), isA<CommandOk>());
  }
  return s;
}

void main() {
  test('save/load and copy() at every check-in change nothing over 7 days', () {
    final e = _engine();
    final straight = _encode(
      _checkIns(e, BalancedBot(), days: 7, between: (s) => _feeding(e, s)),
    );
    // Each check-in goes on from a copy's save, loaded: a field either one
    // drops shows as a difference by the end.
    final reloaded = _checkIns(
      e,
      BalancedBot(),
      days: 7,
      between: (s) =>
          (SaveCodec.decode(SaveCodec.encode(_feeding(e, s).copy()), e.content)
                  as SaveOk)
              .state,
    );
    expect(_encode(reloaded), straight);
    // The settings were there to be saved, and fed something.
    final f = reloaded.faction('player');
    expect(f.megaprojectAuto.keys, ['orbital_station', 'mass_driver']);
  });

  test('milestone progress agrees with the milestones a bot run reaches', () {
    final e = _engine();
    final c = e.content;
    var checked = 0;
    _checkIns(
      e,
      BalancedBot(),
      days: 4,
      between: (s) {
        final f = s.faction('player');
        for (final m in c.milestones) {
          // Rate milestones are tested once a game minute.
          if (m.condition is ProductionRateCondition) continue;
          final p = milestoneProgress(s, c, 'player', m);
          if (p.met) expect(f.reachedMilestones, contains(m.id), reason: m.id);
          // Counts that never fall stay met once reached.
          final neverFalls = switch (m.condition) {
            ProducedCondition() ||
            CreditsEarnedCondition() ||
            ContractsCompletedCondition() ||
            MegaprojectLevelCondition() ||
            BodiesSurveyedCondition() => true,
            _ => false,
          };
          if (neverFalls && f.reachedMilestones.contains(m.id)) {
            expect(p.met, isTrue, reason: m.id);
          }
          checked++;
        }
        return s;
      },
    );
    expect(checked, greaterThan(0));
    expect([
      for (final m in c.milestones) milestoneGoalText(c, m),
    ], everyElement(isNotEmpty));
  });

  test('seeded random commands never break the state', () {
    final e = _engine();
    final c = e.content;
    final s = _played(e, hours: 48);
    final rng = Rng(7);
    T pick<T>(List<T> xs) => xs[rng.nextInt(xs.length)];

    final bodies = [...s.bodies.map((b) => b.id), 'nowhere', ''];
    final buildings = [
      for (final b in s.bodies)
        for (final x in b.buildings) x.id,
      'b0',
      'ghost_building',
    ];
    final defs = [...c.buildings.keys, 'warp_core'];
    final resources = [...c.resources.keys, 'unobtainium'];
    final megaprojects = [...c.megaprojects.keys, 'dyson'];
    final factions = ['player', 'player', 'player', 'ghost'];
    final amounts = [
      BigNum.from(0),
      BigNum.from(-1),
      BigNum.parse('1e300'),
      BigNum.from(2.5e-7),
      BigNum.from(1),
      BigNum.from(50),
    ];
    final counts = [0, -1, 1, 3, 1 << 40];
    List<String> routes() => [...s.routes.map((r) => r.id), 'r0'];
    List<String> contracts() => [
      ...s.faction('player').contracts.map((k) => k.id),
      'c0',
    ];

    Command next() {
      final f = pick(factions);
      return switch (rng.nextInt(18)) {
        0 => BuildCommand(
          f,
          pick(bodies),
          pick(defs),
          depositResourceId: pick([null, ...resources]),
          autoCrew: rng.nextInt(2) == 0,
        ),
        1 => DemolishCommand(f, pick(buildings)),
        2 => AssignCrewCommand(f, pick(buildings), pick(counts)),
        3 => UpgradeCommand(f, pick(buildings), pick(UpgradeTrack.values)),
        4 => CreateRouteCommand(
          f,
          pick(bodies),
          pick(bodies),
          pick(resources),
          pick(amounts),
          pick(counts),
          stopAtDestination: pick([null, ...amounts]),
        ),
        5 => UpdateRouteCommand(
          f,
          pick(routes()),
          ratePerSecond: pick([null, ...amounts]),
          cargoShips: pick([null, ...counts]),
          stopAtDestination: pick([null, ...amounts]),
          removeStopAtDestination: rng.nextInt(3) == 0,
        ),
        6 => MoveShipsCommand(f, pick(bodies), pick(bodies), pick(counts)),
        7 => RemoveRouteCommand(f, pick(routes())),
        8 => SellCommand(f, pick(bodies), pick(resources), pick(amounts)),
        9 => SetAutoSellCommand(
          f,
          pick(bodies),
          pick(resources),
          pick([null, ...amounts]),
        ),
        10 => ClaimBodyCommand(f, pick(bodies), pick(bodies)),
        11 => SurveyCommand(f, pick([null, ...bodies]), pick(bodies)),
        12 => ExpandSlotsCommand(f, pick(bodies)),
        13 => StartMegaprojectStageCommand(f, pick(megaprojects), pick(bodies)),
        14 => DeliverToMegaprojectCommand(f, pick(megaprojects), pick(bodies), {
          for (var i = rng.nextInt(3); i > 0; i--)
            pick(['credits', ...resources]): pick(amounts),
        }),
        15 => DeliverContractCommand(
          f,
          pick(contracts()),
          pick(bodies),
          pick(amounts),
        ),
        16 => SetMegaprojectAutoCommand(
          f,
          pick(megaprojects),
          rng.nextInt(2) == 0,
          pick([null, ...amounts]),
        ),
        _ => DiscardContractCommand(f, pick(contracts())),
      };
    }

    void decodes(String why) {
      final r = SaveCodec.decode(SaveCodec.encode(s), c);
      expect(
        r,
        isA<SaveOk>(),
        reason: r is SaveError ? '$why: ${r.message}' : '',
      );
    }

    var applied = 0;
    for (var i = 0; i < 1500; i++) {
      final cmd = next();
      final json = cmd.toJson();
      // Every command round-trips through JSON.
      final back = Command.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(back.toJson(), json);
      final before = _encode(s);
      final CommandResult r;
      try {
        r = e.apply(s, cmd);
      } on Object catch (err) {
        fail('${jsonEncode(json)} threw $err');
      }
      switch (r) {
        case CommandFailed(:final message):
          expect(_encode(s), before, reason: '${jsonEncode(json)}: $message');
        case CommandOk(:final outcome):
          applied++;
          expect(outcome, isNotNull, reason: jsonEncode(json));
          decodes(jsonEncode(json));
      }
      if (i % 50 == 49) {
        e.advance(s, 600);
        decodes('after ticks');
      }
    }
    // Enough of them were valid to exercise success paths too.
    expect(applied, greaterThan(50));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('report credits per second match what 2.5 h away earns, from a '
      'day-7 state', () {
    // Round-3 optimizer bug 3: the report showed 680-744K a second while
    // 2.5 h away earned 395K a second, presses draining stock.
    final e = _engine();
    final s = _played(e, hours: 168);
    // Auto-delivery stays on as the bot left it: the report's credits are
    // what sales earn, before what auto-delivery pays in, so they are set
    // against what was earned, the credits paid in included.
    expect(s.faction('player').megaprojectAuto, isNotEmpty);
    final shown = buildFlowReport(
      s,
      e.content,
      'player',
    ).creditsPerSec.toDouble();
    final away = e.catchUpOffline(s, 9000);
    expect(
      away.creditsEarned.toDouble(),
      closeTo((away.creditsGained + away.creditsPaidIn).toDouble(), 1),
    );
    final earned = away.creditsEarned.toDouble() / 9000;
    expect(earned, greaterThan(0));
    expect(shown, closeTo(earned, earned * 0.1));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a 6 h catch-up matches 1 s steps from a day-3 state, feeding '
      'megaprojects on their own', () {
    final e = _engine();
    final played = _played(e, hours: 72);
    final unfed = played.copy();
    e.catchUpOffline(unfed, 21600);
    final start = _feeding(e, played);
    final away = start.copy();
    final live = start.copy();
    e.catchUpOffline(away, 21600);
    e.advance(live, 21600, maxStep: 1);
    final (a, l) = (away.faction('player'), live.faction('player'));
    expect(
      [for (final p in away.projects) (p.id, p.finishAt)],
      [for (final p in live.projects) (p.id, p.finishAt)],
    );
    expect(a.megaprojectLevels, l.megaprojectLevels);
    expect(
      a.megaprojectProgress.keys.toList(),
      l.megaprojectProgress.keys.toList(),
    );
    // Something went in on its own (the Mass Driver is still locked).
    final hand = unfed.faction('player');
    expect(
      jsonEncode([l.megaprojectLevels, l.megaprojectProgress]),
      isNot(jsonEncode([hand.megaprojectLevels, hand.megaprojectProgress])),
    );
    // Goods fed match; credits paid in differ by at most a minute's
    // income, which 60 s steps pay in a minute later.
    final minute = l.lifetimeCredits.toDouble() / start.time * 60;
    for (final MapEntry(key: m, value: got) in l.megaprojectProgress.entries) {
      for (final MapEntry(key: id, value: v) in got.entries) {
        final want = v.toDouble();
        expect(
          a.megaprojectProgress[m]![id]!.toDouble(),
          closeTo(want, id == 'credits' ? minute + want * 1e-3 : want * 0.02),
          reason: '$m $id',
        );
      }
    }
    expect(
      a.lifetimeCredits.toDouble(),
      closeTo(
        l.lifetimeCredits.toDouble(),
        l.lifetimeCredits.toDouble() * 1e-3,
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a 6 h catch-up matches 1 s steps from a day-3 state', () {
    final e = _engine();
    final start = _played(e, hours: 72);
    final away = start.copy();
    final live = start.copy();
    e.catchUpOffline(away, 21600);
    e.advance(live, 21600, maxStep: 1);
    final (a, l) = (away.faction('player'), live.faction('player'));
    expect(
      [for (final p in away.projects) (p.id, p.finishAt)],
      [for (final p in live.projects) (p.id, p.finishAt)],
    );
    expect(a.megaprojectLevels, l.megaprojectLevels);
    expect(
      [for (final b in away.bodies) (b.ownerId, b.extraSlots, b.surveyed)],
      [for (final b in live.bodies) (b.ownerId, b.extraSlots, b.surveyed)],
    );
    expect(
      [for (final k in a.contracts) (k.id, k.resourceId)],
      [for (final k in l.contracts) (k.id, k.resourceId)],
    );
    expect(a.contractRefillAt, l.contractRefillAt);
    expect(a.reachedMilestones, l.reachedMilestones);
    expect(
      a.credits.toDouble(),
      closeTo(l.credits.toDouble(), l.credits.toDouble() * 1e-3),
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('feeding the Mass Driver water never costs housing, at 1 s or 60 s '
      'steps', () {
    // Auto-delivery leaves a body only a few seconds of its own use, so a
    // Mass Driver fed the habitats' water could starve them.
    final e = _engine();
    final c = e.content;
    final played = _played(e, hours: 72);
    final f = played.faction('player');
    // The Mass Driver open, two levels in, so it wants plenty of both.
    f.megaprojectLevels
      ..['orbital_station'] = 2
      ..['mass_driver'] = 2;
    final driver = c.megaprojects['mass_driver']!;
    // Habitats use food, water and oxygen.
    final habitat = c.buildings['habitat']!;
    final shared = [
      for (final id in megaprojectCost(c, driver, 2).keys)
        if (habitat.inputs.containsKey(id)) id,
    ];
    expect(shared, isNotEmpty);
    final unfed = played.copy();
    expect(
      e.apply(
        played,
        const SetMegaprojectAutoCommand('player', 'mass_driver', true, null),
      ),
      isA<CommandOk>(),
    );
    final runs = {
      'unfed 1 s': (unfed.copy(), 1.0),
      'unfed 60 s': (unfed, 60.0),
      'fed 1 s': (played.copy(), 1.0),
      'fed 60 s': (played, 60.0),
    };
    final least = {for (final k in runs.keys) k: 1 << 30};
    final start = crewTotals(played, c, 'player').supported;
    expect(start, greaterThan(f.baseCrew));
    // Four hours, crew read each game minute.
    for (var minute = 0; minute < 240; minute++) {
      for (final MapEntry(key: k, value: (g, step)) in runs.entries) {
        e.advance(g, 60, maxStep: step);
        final housed = crewTotals(g, c, 'player').supported;
        if (housed < least[k]!) least[k] = housed;
      }
    }
    // What habitats use went in, and a good share of what the stage
    // asks: feeding put the habitats' supply under real pressure.
    final fed = runs['fed 1 s']!.$1.faction('player');
    final got = fed.megaprojectProgress['mass_driver'] ?? const {};
    final need = megaprojectCost(c, driver, 2);
    for (final id in shared) {
      expect(got[id], isNotNull, reason: '$id: $got');
      expect(
        got[id]!.toDouble(),
        greaterThanOrEqualTo(need[id]!.toDouble() * 0.5),
        reason: '$id: ${got[id]} of ${need[id]}',
      );
    }
    for (final step in ['1 s', '60 s']) {
      expect(
        least['fed $step'],
        greaterThanOrEqualTo(least['unfed $step']!),
        reason: '$least',
      );
    }
    expect(
      least['fed 1 s']!.toDouble(),
      closeTo(least['fed 60 s']!.toDouble(), least['fed 60 s']! * 0.02),
      reason: '$least',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
