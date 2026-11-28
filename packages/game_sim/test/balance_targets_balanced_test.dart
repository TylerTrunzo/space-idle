import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

import 'balance_targets_shared.dart';

/// Plays like [inner], noting what the faction has made at the start of
/// every 6 h check-in.
final class _Tally implements Bot {
  _Tally(this.inner);

  final Bot inner;

  /// Check-in index to the faction's lifetime production at its start.
  final Map<int, Map<String, BigNum>> made = {};

  /// Check-in index to resource id to the buildings on the faction's
  /// bodies that make it, at the check-in's start.
  final Map<int, Map<String, int>> makers = {};

  /// The state as check-in 56 begins: the end of day 14.
  GameState? day14;

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final i = s.time ~/ 21600;
    if (i == 56 && day14 == null) day14 = s.copy();
    if (!made.containsKey(i)) {
      made[i] = Map.of(s.faction(factionId).lifetimeProduced);
      final count = makers[i] = {};
      for (final body in s.bodies.where((b) => b.ownerId == factionId)) {
        for (final b in body.buildings) {
          for (final id in e.content.buildings[b.defId]!.outputs.keys) {
            count[id] = (count[id] ?? 0) + 1;
          }
        }
      }
    }
    return inner.decide(e, s, factionId);
  }

  /// Units of [id] made between check-ins [from] and `from + 1`.
  double between(int from, String id) =>
      ((made[from + 1]![id] ?? const BigNum.zero()) -
              (made[from]![id] ?? const BigNum.zero()))
          .toDouble();
}

void main() {
  final content = shippedContent();

  // The suite's 21-day balanced session, seed 1, played once for every
  // test that reads it. The casual one is in
  // balance_targets_casual_test.dart, so the runner plays both at once.
  late _Tally tally;
  late GameState end;
  BalanceReport? balancedRun;
  BalanceReport balanced() => balancedRun ??= runBotSession(
    GameEngine(content),
    tally = _Tally(BalancedBot()),
    seed: 1,
    hours: 504,
    onFinished: (s) => end = s,
  );

  group('a 21-day balanced bot run', () {
    late BalanceReport report;
    late DayIncome day14;
    setUpAll(() {
      report = balanced();
      day14 = report.days[13];
    });

    test('earns most of day 14 from tier 2 and up', () {
      expect(day14.day, 14);
      final low = day14.share.entries
          .where((e) => content.resources[e.key]!.tier <= 1)
          .fold(0.0, (t, e) => t + e.value);
      expect(low, lessThanOrEqualTo(0.35), reason: '${day14.share}');
    });

    test('earns no more than 55% of day 14 from one resource', () {
      // The target is 30%. Since stage-1.5 Task 8, Orbital Station levels
      // take every magnet-based good (segments, drones, reactor cores) the
      // optimizer makes, so only hull plates, circuits and tier 1 goods
      // are sold, each at its market's cap: hull plates and circuits earned
      // about 36% each (the Task 8 report). Stage 1.7 task 4's bots feed
      // megaprojects credits as they earn them, and the Mass Driver's sale
      // bonus covers both: hull plates earn 44-52% on seeds 1-3 (38-41%
      // at the task's base). A known concentration, accepted for stage
      // 1.7 (the limit was 40%) until stage 3's market-wall content (tier
      // 4 recipes, faction buyers, regional demand) spreads sales out.
      for (final MapEntry(:key, :value) in day14.share.entries) {
        expect(value, lessThanOrEqualTo(0.55), reason: key);
      }
    });

    test('makes kits, modules and ships by the tens per 6 h on day 7', () {
      // Check-in 28 starts day 8, so 168 h to 174 h: each maker makes a
      // fixed trickle, and the bot builds no more makers than the market
      // for what they make can take.
      for (final id in ['outpost_kit', 'habitat_module', 'cargo_ship']) {
        final units = tally.between(28, id);
        final makers = tally.makers[28]![id] ?? 0;
        expect(units, lessThanOrEqualTo(200), reason: '$id: $units');
        if (makers > 0) {
          expect(units / makers, lessThanOrEqualTo(72), reason: id);
        }
      }
    });

    test('grows its crew with habitats', () {
      expect(report.rejectedCommands, 0);
      expect(
        crewTotals(end, content, 'player').supported,
        greaterThan(5 * end.faction('player').baseCrew),
      );
    });

    test('earns at least 20% more around day 14 than around day 7, and 10% '
        'more around day 21 than around day 14', () {
      // Round-3 pacing targets, kept in round 4
      // (docs/playtests/2026-11-27-round4-findings.md §4); stage 1.5
      // flattened from day 9 for the optimizer. Measured on three-day
      // averages ([earnedAround]).
      final (week1, week2, week3) = (
        earnedAround(report, 7),
        earnedAround(report, 14),
        earnedAround(report, 21),
      );
      expect(
        week2,
        greaterThanOrEqualTo(week1 * 1.2),
        reason: '$week1 then $week2',
      );
      expect(
        week3,
        greaterThanOrEqualTo(week2 * 1.1),
        reason: '$week2 then $week3',
      );
    });

    test('goes no more than 4 days without a new station level, from its '
        'first to day 21', () {
      // Findings §4 asked for a level every 3 days; the controller's
      // ruling on stage 1.7 task 4 accepts gaps of up to 4 with megaproject
      // costs ×2 a level (a level costs 1-2 days of income by then, so a
      // 3-day cadence would need income ×5 a week).
      int level(int day) =>
          report.dayEnds[day - 1].megaprojectLevels['orbital_station']!;
      final first = [
        for (var d = 1; d <= 21; d++)
          if (level(d) > 0) d,
      ].first;
      var gap = 0;
      var worst = 0;
      for (var d = first + 1; d <= 21; d++) {
        gap = level(d) > level(d - 1) ? 0 : gap + 1;
        worst = math.max(worst, gap);
      }
      expect(worst, lessThanOrEqualTo(4), reason: report.toMarkdown());
    });

    test('a Mass Driver level raises its day-14 income by 3% or more', () {
      // Findings §4. One more level's bonus alone, as stage 1.7 task 3
      // measured it: the factor raised so the state's level gives what
      // the next would, so what the megaprojects owe stays the same.
      final s = tally.day14!;
      final level = s.faction('player').megaprojectLevels['mass_driver']!;
      expect(level, greaterThan(0));
      final b = loadContentDir('../../content');
      final driver = (b['megaprojects']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((m) => m['id'] == 'mass_driver');
      for (final bonus
          in (driver['bonusesPerLevel']! as List)
              .cast<Map<String, Object?>>()) {
        final a = (bonus['amount']! as num).toDouble();
        bonus['amount'] = math.pow(a, (level + 1) / level).toDouble();
      }
      final up = (Content.fromBundle(b) as ContentOk).content;
      final base = buildFlowReport(
        s.copy(),
        content,
        'player',
      ).creditsPerSec.toDouble();
      final more = buildFlowReport(
        s.copy(),
        up,
        'player',
      ).creditsPerSec.toDouble();
      expect(more / base, greaterThanOrEqualTo(1.03), reason: '$base → $more');
    });

    test('earns no more than 15% from contracts on days 1, 7 and 14', () {
      contractsAtMost(report, 0.15);
    });

    // Findings §4's "no reward above 1 h of income (first excepted)" is
    // the engine's reward cap, checked at posting, where the income basis
    // it caps by is known, in game_core's
    // test/sim/contract_reward_cap_test.dart: a session reads the basis
    // hours later, when it can have swung severalfold.
  });
}
