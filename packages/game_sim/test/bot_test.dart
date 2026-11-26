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

  test('bots name themselves', () {
    expect(GreedyBot().name, 'greedy');
    expect(BalancedBot().name, 'balanced');
  });
}
