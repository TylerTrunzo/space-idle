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

/// Auto-sells Kora's steel and copper ore once, then idles.
final class _SellerBot implements Bot {
  @override
  String get name => 'seller';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) => [
    if (s.faction(factionId).autoSell.isEmpty) ...[
      SetAutoSellCommand(factionId, 'kora', 'steel', BigNum.zero()),
      SetAutoSellCommand(factionId, 'kora', 'copper_ore', BigNum.zero()),
    ],
  ];
}

/// An idle session (24 h by default) with 60 s check-ins: First Foundry is reached in
/// the time away after check-in 0.
BalanceReport _shortCheckIns({double hours = 24}) => runBotSession(
  _engine(),
  _IdleBot(),
  seed: 1,
  hours: hours,
  activeSecondsPerCheckIn: 60,
);

void main() {
  test('report lists dead zones', () {
    final r = runBotSession(_engine(), _IdleBot(), seed: 1, hours: 24);
    expect(r.checkIns, 4);
    expect(r.deadZones.map((d) => d.checkInIndex), [0, 1, 2, 3]);
    expect(r.deadZones.map((d) => d.gameHours), [0, 6, 12, 18]);
  });

  test('milestones reached offline are seen at the next check-in', () {
    // The starting smelter makes 0.2 steel/s: 12 in a 60 s check-in, short
    // of First Foundry's 30, so the player sees it on return at 6 h.
    final r = _shortCheckIns();
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
    final md = _shortCheckIns().toMarkdown();
    expect(md, contains('| Milestone | Id | Hours | Check-in |'));
    expect(md, contains('| First Foundry | first_steel | 6.0 | 1 |'));
    expect(md, contains('| First Claim | own_2_bodies | not reached | |'));
    expect(md, contains('## Dead zones'));
  });

  test('income per day with each resource\'s share', () {
    final r = runBotSession(_engine(), _SellerBot(), seed: 1, hours: 48);
    expect(r.days, hasLength(2));
    for (final d in r.days) {
      expect(d.credits.toDouble(), greaterThan(0));
      expect(d.share.keys, ['copper_ore', 'steel']);
      expect(d.share.values.fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
    }
    // 0.32 copper ore and 0.2 steel a second, each market settled at
    // 1 / (1 + rate × recovery / depth).
    final c = _engine().content;
    double income(String id, double rate) {
      final res = c.resources[id]!;
      final settled =
          1 / (1 + rate * c.rules.marketRecoverySeconds / res.marketDepth);
      return rate * res.basePrice.toDouble() * settled;
    }

    final steel = income('steel', 0.2);
    final copper = income('copper_ore', 0.32);
    expect(r.days.last.share['steel'], closeTo(steel / (steel + copper), 0.01));
    final md = r.toMarkdown();
    expect(md, contains('## Income by day'));
    expect(md, contains('| Day | Credits earned | Top resources |'));
  });

  test('check-ins more than a day apart still give one entry a day', () {
    // Check-ins every 36 h over 72 h: the absences cross the 24 h and 48 h
    // boundaries. Each absence simulates the 12 h offline cap right after
    // the check-in, so day 1 earns its first 12 h, day 2 the 12 h from the
    // 36 h check-in, and day 3 only what that runs past 48 h.
    final r = runBotSession(
      _engine(),
      _SellerBot(),
      seed: 1,
      hours: 72,
      checkInEverySeconds: 36 * 3600,
    );
    expect(r.days.map((d) => d.day), [1, 2, 3]);
    final earned = [for (final d in r.days) d.credits.toDouble()];
    expect(earned.every((v) => v > 0), isTrue, reason: '$earned');
    // Day 3 holds the 180 s of the second absence that ran past 48 h.
    expect(earned[2], lessThan(earned[1] / 100));
  });

  test('new things, day ends and income by tier', () {
    final r = runBotSession(_engine(), BalancedBot(), seed: 1, hours: 48);
    final claimed = r.events.firstWhere((e) => e.kind == SessionEventKind.body);
    expect(claimed.text, endsWith(' claimed'));
    final hit = r.milestones.firstWhere((m) => m.id == 'own_2_bodies');
    expect(claimed.gameHours, hit.gameHours);
    expect(
      r.events.where((e) => e.kind == SessionEventKind.milestone),
      hasLength(r.milestones.length),
    );
    expect(r.newThingsOn(1) + r.newThingsOn(2), r.events.length);
    expect(r.daysWithNewThings(2), 2);

    expect(r.dayEnds.map((d) => d.day), [1, 2]);
    expect(r.dayEnds.last.bodiesOwned, greaterThanOrEqualTo(2));
    expect(r.dayEnds.last.megaprojectLevels.keys, ['orbital_station']);
    for (final d in r.days) {
      final total = [
        for (final t in [0, 1, 2, 3]) r.tierShare(d, t),
      ].fold(0.0, (a, b) => a + b);
      expect(total, closeTo(1, 1e-9));
    }
    final md = r.toMarkdown();
    expect(md, contains('## Days'));
    expect(md, contains('| Day | New | Milestones | Projects |'));
    expect(md, contains('Days with something new'));
    expect(md, contains('## Timeline'));
    expect(md, contains(claimed.text));
  });

  test('json report carries every section', () {
    final j = _shortCheckIns(hours: 12).toJson();
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
      'days',
      'events',
      'dayEnds',
    ]);
    expect((j['milestones']! as List).first, {
      'id': 'first_steel',
      'name': 'First Foundry',
      'gameHours': 6.0,
      'checkInIndex': 1,
    });
  });
}
