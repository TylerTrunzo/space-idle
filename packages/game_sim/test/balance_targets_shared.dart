/// What the balance target tests share: the shipped content, and the
/// readings of a session they check. Split in two files, the balanced and
/// the casual sessions, so the test runner plays them side by side.
library;

import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

/// The shipped content, from the repo root.
Content shippedContent() =>
    (Content.fromBundle(loadContentDir('../../content')) as ContentOk).content;

/// Game hours [r] took to reach milestone [id]; fails the test if never.
double hoursTo(BalanceReport r, String id) => r.milestones
    .singleWhere(
      (m) => m.id == id,
      orElse: () {
        fail('${r.botName}: $id not reached\n${r.toMarkdown()}');
      },
    )
    .gameHours;

/// Expects [report]'s contract rewards to be at most [share] of what was
/// earned on days 1, 7 and 14.
void contractsAtMost(BalanceReport report, double share) {
  for (final day in [1, 7, 14]) {
    final d = report.days[day - 1];
    expect(
      d.contractCredits.toDouble(),
      lessThanOrEqualTo(d.earned.toDouble() * share),
      reason:
          '${report.botName} day $day: ${d.contractCredits} of '
          '${d.earned}',
    );
  }
}

/// [report]'s mean earnings over the three days ending on [day].
///
/// The §4 income ratios compare these, not single days (controller ruling
/// on stage 1.7 task 4): a day's earnings swing by 5-20% from the next
/// with when a megaproject level lands (casual seed 1, days 12-21: 140,
/// 171, 184, 199, 206, 214, 258, 265, 260, 270B), so a ratio of one day
/// against one day measures that noise, not growth. The bars stay 1.2×,
/// 1.1× and 1.5×.
double earnedAround(BalanceReport report, int day) =>
    [
      for (var d = day - 2; d <= day; d++) report.days[d - 1].earned.toDouble(),
    ].reduce((a, b) => a + b) /
    3;
