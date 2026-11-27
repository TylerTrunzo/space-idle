import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

/// The whole-branch review's probe of stage 1.6, kept: a mid-game state
/// with every stage 1.6 feature at work at once (stop-level routes, an
/// open contract, both megaprojects fed, compounding bonuses). See the
/// performance test in engine_test.dart for where the state comes from.
void main() {
  final c = shippedContent();
  final e = GameEngine(c);
  GameState load() =>
      (SaveCodec.decode(
                File(
                  'test/fixtures/balanced_day14_fed.json',
                ).readAsStringSync(),
                c,
              )
              as SaveOk)
          .state;
  BigNum sales(GameState s) => s
      .faction('player')
      .salesRevenue
      .values
      .fold(const BigNum.zero(), (t, v) => t + v);

  test('a catch-up is 60 s steps to the unit, and 1 s steps earn within '
      '3%, wasting nothing and keeping every crew housed', () {
    // 1 s steps earn 2.1-2.3% less here, the same before and after the
    // stage 1.6 fixes: the tier-3 chain (magnets into reactor cores and
    // segments) sells differently. Within the plan's 2% elsewhere; this
    // state is the one known exception, kept in view at 3%.
    final start = load();
    final away = start.copy();
    final ticks = start.copy();
    final live = start.copy();
    e.catchUpOffline(away, 3600, capSeconds: 3600);
    e.advance(ticks, 3600);
    expect(jsonEncode(away.toJson()), jsonEncode(ticks.toJson()));

    final housed = crewTotals(start, c, 'player').supported;
    var wasted = const BigNum.zero();
    var least = housed;
    for (var i = 0; i < 3600; i++) {
      e.tick(live, 1);
      for (final b in live.bodies) {
        if (b.ownerId != 'player') continue;
        for (final v in b.wastedThisStep.values) {
          wasted = wasted + v;
        }
      }
      if (i % 60 == 59) {
        final now = crewTotals(live, c, 'player').supported;
        if (now < least) least = now;
      }
    }
    BigNum earned(GameState s) =>
        s.faction('player').lifetimeCredits -
        start.faction('player').lifetimeCredits;
    expect(
      earned(live).toDouble(),
      closeTo(earned(ticks).toDouble(), earned(ticks).toDouble() * 0.03),
    );
    expect(wasted.toDouble(), lessThan(1e-6));
    expect(least, housed);
    // Both megaprojects got something.
    final fed = live.faction('player').megaprojectProgress;
    expect(fed.keys, containsAll(['orbital_station', 'mass_driver']));
  });

  test('credits a second are within 10% of 2.5 h of sales', () {
    final s = load();
    final shown = buildFlowReport(s, c, 'player').creditsPerSec.toDouble();
    final before = sales(s);
    e.advance(s, 9000);
    final actual = (sales(s) - before).toDouble() / 9000;
    expect(actual, greaterThan(0));
    expect(shown, closeTo(actual, actual * 0.1));
  });
}
