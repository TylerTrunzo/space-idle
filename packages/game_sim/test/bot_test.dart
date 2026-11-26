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

  test('auto-sell keeps a full offline step of what a body uses', () {
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

  test('bots name themselves', () {
    expect(GreedyBot().name, 'greedy');
    expect(BalancedBot().name, 'balanced');
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
}
