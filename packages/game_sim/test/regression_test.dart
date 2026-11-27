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

/// The state a [BalancedBot] session of [hours] ends in.
GameState _played(GameEngine e, {required double hours}) {
  late GameState end;
  runBotSession(
    e,
    BalancedBot(),
    seed: 1,
    hours: hours,
    onFinished: (s) => end = s,
  );
  return end;
}

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

void main() {
  test('save/load and copy() at every check-in change nothing over 7 days', () {
    final e = _engine();
    final straight = _encode(_checkIns(e, BalancedBot(), days: 7));
    // Each check-in goes on from a copy's save, loaded: a field either one
    // drops shows as a difference by the end.
    final reloaded = _checkIns(
      e,
      BalancedBot(),
      days: 7,
      between: (s) =>
          (SaveCodec.decode(SaveCodec.encode(s.copy()), e.content) as SaveOk)
              .state,
    );
    expect(_encode(reloaded), straight);
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
      return switch (rng.nextInt(17)) {
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
    final shown = buildFlowReport(
      s,
      e.content,
      'player',
    ).creditsPerSec.toDouble();
    final away = e.catchUpOffline(s, 9000);
    final earned = away.creditsGained.toDouble() / 9000;
    expect(earned, greaterThan(0));
    expect(shown, closeTo(earned, earned * 0.1));
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
}
