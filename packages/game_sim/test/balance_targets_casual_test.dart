import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:test/test.dart';

import 'balance_targets_shared.dart';

void main() {
  final content = shippedContent();

  // The suite's 21-day casual session, seed 1, played once for every test
  // that reads it. The balanced one is in
  // balance_targets_balanced_test.dart, so the runner plays both at once.
  BalanceReport? casualRun;
  BalanceReport casual() => casualRun ??= runBotSession(
    GameEngine(content),
    CasualBot(),
    seed: 1,
    hours: 504,
  );

  // Seed 1 only, to keep the suite quick; docs/balance/ has seeds 1 to 3.
  // The casual bot taps buy-max once a check-in, as stage 2's app lets
  // every player do: the round-4 pacing targets are its
  // (docs/playtests/2026-11-27-round4-findings.md §4).
  group('a 21-day buy-max casual bot run', () {
    late BalanceReport report;
    setUpAll(() {
      report = casual();
    });

    test('reaches Orbital Station level 1 in days 3 to 5', () {
      expect(hoursTo(report, 'station_1'), inInclusiveRange(48, 120));
    });

    test('sees a milestone or project on 5 of every 7 days', () {
      // Contracts left out: findings §4 asks this of milestones and
      // completed projects alone.
      expect(
        report.worstWeekWithMilestoneOrProject(21),
        greaterThanOrEqualTo(5),
        reason: report.toMarkdown(),
      );
    });

    test('goes no more than 3 days with neither megaproject levelling, '
        'from its first station level to day 21', () {
      final from = (hoursTo(report, 'station_1') / 24).ceil();
      bool levelled(int day) =>
          report.dayEnds[day - 1].megaprojectLevels.entries.any(
            (e) =>
                e.value >
                (day == 1
                    ? 0
                    : report.dayEnds[day - 2].megaprojectLevels[e.key]!),
          );
      var gap = 0;
      var worst = 0;
      for (var day = from; day <= 21; day++) {
        gap = levelled(day) ? 0 : gap + 1;
        worst = math.max(worst, gap);
      }
      expect(worst, lessThanOrEqualTo(3), reason: report.toMarkdown());
    });

    test('earns 1.5 times as much around day 21 as around day 14', () {
      // Findings §4, casual bot: "income at day 21 ≥ 1.5× day 14"; 2× was
      // stage 1.5's. Measured on three-day averages ([earnedAround]).
      final (week2, week3) = (
        earnedAround(report, 14),
        earnedAround(report, 21),
      );
      expect(
        week3,
        greaterThanOrEqualTo(week2 * 1.5),
        reason: '$week2 then $week3',
      );
    });

    test('earns no more than 15% from contracts on days 1, 7 and 14', () {
      contractsAtMost(report, 0.15);
      expect(report.rejectedCommands, 0);
    });
  });

  test('the greedy bot earns no more than 15% from contracts on days 1, 7 '
      'and 14', () {
    final report = runBotSession(
      GameEngine(content),
      GreedyBot(),
      seed: 1,
      hours: 336,
    );
    contractsAtMost(report, 0.15);
  });
}
