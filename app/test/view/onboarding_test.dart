import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/goal_strip_view.dart';
import 'package:space_idle/view/onboarding.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller([Content? with_]) => GameController(
  content: with_ ?? content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

int _index(String id) => onboardingSteps.indexWhere((s) => s.id == id);

/// The shipped content as the saved fixtures were played with (see
/// game_core's test helpers: the stage 1.7 retune undone).
Content _fixtureContent() {
  final b = <String, Object?>{
    for (final f in Directory('../content').listSync().whereType<File>())
      if (f.path.endsWith('.json'))
        f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(
          f.readAsStringSync(),
        ),
  };
  for (final m in (b['megaprojects']! as List).cast<Map<String, Object?>>()) {
    final (credits, growth) = switch (m['id']) {
      'orbital_station' => ('5e6', 2.5),
      'mass_driver' => ('2e6', 2.3),
      _ => (null, null),
    };
    if (credits == null) continue;
    (m['baseCost']! as Map<String, Object?>)['credits'] = credits;
    m['costGrowth'] = growth;
  }
  for (final d in (b['buildings']! as List).cast<Map<String, Object?>>()) {
    if (d['id'] != 'habitat') continue;
    ((d['upgrades']! as Map)['capacity']! as Map)['growth'] = 1.2;
  }
  return (Content.fromBundle(b) as ContentOk).content;
}

void main() {
  late GameController c;
  setUp(() => c = _controller());

  int? step() => onboardingStepAt(c.state, content, _p, 0);

  group('onboarding steps', () {
    test('a new game starts at the first: sell some Steel', () {
      expect(step(), 0);
      expect(onboardingSteps[0].title, contains('Sell some Steel'));
    });

    test('selling Steel passes it', () {
      c.state.body('kora').stock['steel'] = BigNum.from(10);
      c.run(SellCommand(_p, 'kora', 'steel', BigNum.from(10)));
      expect(onboardingReached(c.state, content, _p, 0), 1);
      expect(step(), _index('second-smelter'));
    });

    test('turning on auto-sell for Steel passes it too', () {
      c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
      expect(onboardingReached(c.state, content, _p, 0), 1);
    });

    test('steps already done are skipped: two smelters, then crew', () {
      c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const BuildCommand(_p, 'kora', 'smelter'));
      // Its crew came from the free crew: more than the start's.
      final at = step()!;
      expect(at, greaterThan(_index('second-smelter')));
      expect(onboardingSteps[at].id, 'upgrade');
    });

    test('a passed step stays passed when the state undoes it', () {
      c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
      final reached = onboardingReached(c.state, content, _p, 0);
      c.run(const SetAutoSellCommand(_p, 'kora', 'steel', null));
      expect(onboardingStepAt(c.state, content, _p, reached), reached);
    });

    test('the Habitat step comes forward before free crew runs out', () {
      c.state.faction(_p).baseCrew =
          crewTotals(c.state, content, _p).assigned + habitatStepFreeCrew;
      expect(step(), _index('habitat'));
    });

    test('the claim step names what each body mines, and its cost', () {
      final detail = onboardingDetail(
        onboardingSteps[_index('claim')],
        c.state,
        content,
        _p,
      )!;
      final cost = claimCost(c.state, content, _p)[creditsKey]!;
      expect(detail, contains('A claim costs ${formatNumber(cost)} credits'));
      expect(detail, contains('Brine: Water Ice, Ammonia'));
      expect(detail, isNot(contains('Tessaly')), reason: 'hidden');
    });

    test('Buy max is mentioned once, on the upgrade step, with credits '
        'to spare', () {
      final upgrade = onboardingSteps[_index('upgrade')];
      c.state.faction(_p).credits = BigNum.from(80);
      expect(onboardingDetail(upgrade, c.state, content, _p), isNull);
      c.state.faction(_p).credits = BigNum.from(1000);
      expect(
        onboardingDetail(upgrade, c.state, content, _p),
        contains('Buy max'),
      );
      final others = [
        for (final s in onboardingSteps)
          if (s.id != 'upgrade') onboardingDetail(s, c.state, content, _p),
      ];
      expect(
        others.whereType<String>().where((d) => d.contains('Buy max')),
        isEmpty,
      );
    });

    test('the last step done ends the guide', () {
      expect(
        onboardingStepAt(c.state, content, _p, onboardingSteps.length),
        isNull,
      );
    });
  });

  group('goalStripView', () {
    test('a new game: the guide step now, a milestone today, a long aim', () {
      final v = goalStripView(c, guideStep: 0);
      expect(v.now.kind, GoalKind.guide);
      expect(v.now.title, onboardingSteps[0].title);
      expect(v.now.action, const SelectBodyAction('kora'));
      expect(v.today.kind, GoalKind.milestone);
      expect(v.long.title, isNotEmpty);
    });

    test("today's bar is the nearest milestone's milestoneProgress", () {
      final v = goalStripView(c);
      final f = c.state.faction(_p);
      final m = content.milestones.firstWhere(
        (m) => milestoneGoalText(content, m) == v.today.title,
      );
      expect(f.reachedMilestones, isNot(contains(m.id)));
      final p = milestoneProgress(c.state, content, _p, m);
      expect(
        v.today.progress,
        closeTo((p.current.toDouble() / p.target.toDouble()).clamp(0, 1), 1e-9),
      );
      // And no other unreached milestone is nearer.
      for (final o in content.milestones) {
        if (f.reachedMilestones.contains(o.id)) continue;
        final q = milestoneProgress(c.state, content, _p, o);
        if (q.met) continue;
        expect(
          q.current.toDouble() / q.target.toDouble(),
          lessThanOrEqualTo(v.today.progress! + 1e-9),
          reason: o.id,
        );
      }
    });

    test('with the guide over, now is the first bottleneck and its body', () {
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
      c.tickSeconds(1);
      final v = goalStripView(c);
      expect(v.now.kind, GoalKind.problem);
    });

    test('with nothing held back, now is the best upgrade handed in', () {
      final advice = UpgradeAdvice(
        bodyId: 'kora',
        buildingId: 'b1',
        track: UpgradeTrack.speed,
        preview: upgradePreview(
          c.state,
          content,
          _p,
          'b1',
          UpgradeTrack.speed,
        )!,
      );
      // Selling everything leaves nothing held back on a new game.
      for (final id in content.resources.keys) {
        c.run(SetAutoSellCommand(_p, 'kora', id, const BigNum.zero()));
      }
      c.tickSeconds(1);
      expect(c.flow.bottlenecks, isEmpty, reason: "the case needs none");
      final v = goalStripView(c, best: advice);
      expect(v.now.kind, GoalKind.upgrade);
      expect(v.now.title, startsWith('Speed on Kora Mine: pays back in'));
      expect(v.now.action, const SelectBodyAction('kora'));
      final waiting = goalStripView(c, bestReady: false);
      expect(waiting.now.title, contains('Looking for the best upgrade'));
    });

    test('no slot is ever empty, and long agrees with nextGoal', () {
      final fixtures = _fixtureContent();
      final states = <String, GameController>{'new game': c};
      for (final name in [
        'balanced_day14_fed',
        'review_balanced_day14',
        'optimizer_r4_spree_26h',
      ]) {
        final x = _controller(fixtures);
        final text = File('../packages/game_core/test/fixtures/$name.json')
            .readAsStringSync();
        final s = (SaveCodec.decode(text, fixtures) as SaveOk).state;
        x.debugReplaceState(s);
        states[name] = x;
      }
      for (final MapEntry(key: name, value: x) in states.entries) {
        final v = goalStripView(x);
        for (final g in [v.now, v.today, v.long]) {
          expect(g.title, isNotEmpty, reason: '$name ${g.slot}');
        }
        final goal = nextGoal(x.state, x.content, x.playerId, x.flow);
        if (goal is MegaprojectGoal) {
          final m = x.content.megaprojects[goal.megaprojectId]!;
          expect(
            v.long.title,
            startsWith('${m.name} level ${goal.level}'),
            reason: name,
          );
        }
        // Nothing invites a return or counts days.
        for (final g in [v.now, v.today, v.long]) {
          final words = '${g.title} ${g.detail ?? ''}'.toLowerCase();
          for (final banned in ['streak', 'come back', 'daily', 'reward']) {
            expect(words, isNot(contains(banned)), reason: '$name $words');
          }
        }
      }
    });
  });
}
