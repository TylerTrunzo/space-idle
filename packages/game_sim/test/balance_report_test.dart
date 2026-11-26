import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

GameEngine _engine() => GameEngine(
  (Content.fromBundle(loadContentDir('../../content')) as ContentOk).content,
);

/// Never does anything, so every check-in is a dead zone.
final class _IdleBot implements Bot {
  @override
  String get name => 'idle';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) => [];
}

void main() {
  test('report lists dead zones', () {
    final r = runBotSession(_engine(), _IdleBot(), seed: 1, hours: 24);
    expect(r.checkIns, 4);
    expect(r.deadZones.map((d) => d.checkInIndex), [0, 1, 2, 3]);
    expect(r.deadZones.map((d) => d.gameHours), [0, 6, 12, 18]);
  });

  test('milestones reached offline are seen at the next check-in', () {
    // The starting smelter makes 100 steel in 500 s: after the first
    // 180 s check-in, so the player sees it on return at 6 h.
    final r = runBotSession(_engine(), _IdleBot(), seed: 1, hours: 24);
    final steel = r.milestones.singleWhere((m) => m.id == 'first_steel');
    expect(steel.gameHours, 6);
    expect(steel.checkInIndex, 1);
    expect(r.milestonesNotReached.map((m) => m.id), contains('own_2_bodies'));
  });

  test('unused resources and final stock', () {
    final r = runBotSession(_engine(), _IdleBot(), seed: 1, hours: 24);
    // Copper ore is mined but nothing uses or sells it; circuits are never
    // made. Iron ore feeds the smelter.
    expect(r.unusedResources, containsAll(['copper_ore', 'circuit']));
    expect(r.unusedResources, isNot(contains('iron_ore')));
    expect(r.finalStock['copper_ore'], '1K');
    expect(r.finalCredits, '250');
  });

  test('markdown report contains milestone table', () {
    final md = runBotSession(
      _engine(),
      _IdleBot(),
      seed: 1,
      hours: 24,
    ).toMarkdown();
    expect(md, contains('| Milestone | Id | Hours | Check-in |'));
    expect(md, contains('| First Foundry | first_steel | 6.0 | 1 |'));
    expect(md, contains('| First Claim | own_2_bodies | not reached | |'));
    expect(md, contains('## Dead zones'));
  });

  test('json report carries every section', () {
    final j = runBotSession(_engine(), _IdleBot(), seed: 1, hours: 12).toJson();
    expect(j.keys, [
      'bot',
      'seed',
      'hours',
      'checkIns',
      'milestones',
      'milestonesNotReached',
      'deadZones',
      'unusedResources',
      'finalStock',
      'finalCredits',
      'bottleneckLog',
      'rejectedCommands',
    ]);
    expect((j['milestones']! as List).first, {
      'id': 'first_steel',
      'name': 'First Foundry',
      'gameHours': 6.0,
      'checkInIndex': 1,
    });
  });
}
