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
  // The content the state was played with.
  final c = fixtureContent();
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
      '2%, wasting nothing and keeping every crew housed', () {
    // On the round-1 version of this state 1 s steps earned 2.1-2.3% less,
    // in the tier-3 chain (magnets into reactor cores and segments), the
    // same before and after the fix wave; on this one they are within
    // 0.01%. Seen again, that gap is the one to chase.
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
      closeTo(earned(ticks).toDouble(), earned(ticks).toDouble() * 0.02),
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

  test('right after a large upgrade spree, credits a second are within 8% '
      'of the next 2.5 h away', () {
    // The round-4 optimizer's state at 26.5 h, seed 1, just after a 578M
    // upgrade spree (its allcmds.jsonl replayed to that point and saved):
    // the report showed 87.2K a second and the next 8,850 s earned 71.9K a
    // second, as prices took a while to fall to the new volume.
    final s =
        (SaveCodec.decode(
                  File(
                    'test/fixtures/optimizer_r4_spree_26h.json',
                  ).readAsStringSync(),
                  c,
                )
                as SaveOk)
            .state;
    // Its Mass Driver stage ends 1,772 s in. Since stage 1.7 a Mass Driver
    // level raises what tier 1-2 sales earn, a real rise the report cannot
    // see coming that far ahead; the stage is held past the window so this
    // measures the prices settling alone.
    final stage = s.projects.singleWhere((p) => p.targetId == 'mass_driver');
    s.projects[s.projects.indexOf(stage)] = ProjectState(
      id: stage.id,
      factionId: stage.factionId,
      kind: stage.kind,
      targetId: stage.targetId,
      startedAt: stage.startedAt,
      finishAt: s.time + 9000,
    );
    final shown = buildFlowReport(s, c, 'player').creditsPerSec.toDouble();
    final away = e.catchUpOffline(s, 8850);
    final earned = away.creditsEarned.toDouble() / 8850;
    expect(shown, closeTo(earned, earned * 0.08), reason: '$shown vs $earned');
  });
}
