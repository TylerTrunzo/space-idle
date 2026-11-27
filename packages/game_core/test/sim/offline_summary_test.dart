import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

void main() {
  final c = shippedContent();
  final e = GameEngine(c);

  group('crew shortage in the away summary', () {
    /// Round-3 casual bug 2: housing supports fewer crew than are assigned
    /// while plate presses starve for steel and nothing sells. Three
    /// presses join the starting mines and smelter: 6 crew assigned, 4
    /// housed.
    GameState bug2() {
      final s = e.newGame(1);
      s.faction('player').baseCrew = 4;
      for (var i = 0; i < 3; i++) {
        s
            .body('kora')
            .buildings
            .add(
              BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
            );
      }
      return s;
    }

    test('ranks first whenever it costs credits, even below bigger '
        'losses', () {
      final s = bug2();
      final sum = e.catchUpOffline(s, 3600);
      final first = sum.topBottlenecks.first;
      expect(first.kind, BottleneckKind.crewShortage);
      expect(first.lostCreditsPerHour! > const BigNum.zero(), isTrue);
      // The starved presses and the unsold goods each lose more than the
      // shortage does; it still comes first.
      final unsold = buildFlowReport(
        s,
        c,
        'player',
      ).bottlenecks.singleWhere((b) => b.kind == BottleneckKind.noSales);
      expect(unsold.lostCreditsPerHour! > first.lostCreditsPerHour!, isTrue);
      expect(
        sum.topBottlenecks
            .skip(1)
            .every((b) => b.lostCreditsPerHour! > first.lostCreditsPerHour!),
        isTrue,
      );
    });

    test('is named in the headline', () {
      final sum = e.catchUpOffline(bug2(), 3600);
      expect(
        sum.headline,
        'Away 1h; +${formatNumber(sum.creditsGained)} credits; '
        'Crew short: 4 housed for 6 assigned',
      );
      expect((sum.housingAfter.supported, sum.housingAfter.assigned), (4, 6));
    });

    test('ranks by its loss like the others when it costs nothing', () {
      // One crew housed for the smelter's two, and no ore: no crewed
      // building runs, so the shortage loses nothing.
      final s = e.newGame(1);
      s.faction('player').baseCrew = 1;
      s.body('kora').stock.clear();
      for (final b in s.body('kora').buildings) {
        b.crew = 0;
        if (b.defId == 'smelter') {
          b
            ..levels[UpgradeTrack.capacity] = 1
            ..crew = 2;
        }
      }
      final sum = e.catchUpOffline(s, 600);
      final crew = sum.topBottlenecks.singleWhere(
        (b) => b.kind == BottleneckKind.crewShortage,
      );
      expect(crew.lostCreditsPerHour, const BigNum.zero());
      expect(sum.topBottlenecks.first.kind, BottleneckKind.input);
    });
  });

  test('a fully housed faction shows no crew shortage, whatever float '
      'residue its housing bonus leaves', () {
    // Station level 3 houses 15% more: 20 + 5 × 20 × 2 × 1.15 comes to
    // 249.99999999999997, with 250 crew assigned.
    final s = e.newGame(1);
    s.faction('player').megaprojectLevels['orbital_station'] = 3;
    final kora = s.body('kora');
    for (var i = 0; i < 5; i++) {
      kora.buildings.add(
        BuildingState(id: 'h$i', defId: 'habitat', crew: 0, lastRunFraction: 1)
          ..levels[UpgradeTrack.capacity] = 4,
      );
    }
    kora.stock
      ..['food'] = n(1e6)
      ..['water'] = n(1e6)
      ..['oxygen'] = n(1e6);
    final smelter = kora.buildings.firstWhere((b) => b.defId == 'smelter');
    smelter
      ..levels[UpgradeTrack.capacity] = 200
      ..crew += crewTotals(s, c, 'player').free;
    final t = crewTotals(s, c, 'player');
    expect((t.supported, t.assigned, t.overAssigned), (250, 250, 0));
    expect(crewEfficiency(s, c, 'player'), 1);
    expect(
      buildFlowReport(
        s,
        c,
        'player',
      ).bottlenecks.where((b) => b.kind == BottleneckKind.crewShortage),
      isEmpty,
    );
    final sum = e.catchUpOffline(s, 3600);
    expect(
      sum.topBottlenecks.where((b) => b.kind == BottleneckKind.crewShortage),
      isEmpty,
    );
    expect(sum.topBottlenecks.first.kind, BottleneckKind.input);
    expect(sum.headline, isNot(contains('Crew short')));
  });

  test('housing before and after the absence', () {
    // Food for 10 minutes: the habitat houses 20 crew beyond the base 20
    // until it runs out.
    final s = e.newGame(1);
    final kora = s.body('kora');
    kora.buildings.add(
      BuildingState(id: 'h1', defId: 'habitat', crew: 0, lastRunFraction: 1),
    );
    kora.stock
      ..['food'] = n(60)
      ..['water'] = n(1000)
      ..['oxygen'] = n(1000);
    final sum = e.catchUpOffline(s, 3600);
    expect(sum.housingBefore.supported, 40);
    expect(sum.housingBefore.assigned, 3);
    expect(sum.housingAfter.supported, 20);
    expect(sum.headline, isNot(contains('Crew short')));
  });

  test('credits per second before and after are the reports\' own', () {
    final s = e.newGame(1);
    e.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
    final before = buildFlowReport(s.copy(), c, 'player').creditsPerSec;
    final sum = e.catchUpOffline(s, 3600);
    expect(sum.creditsPerSecBefore, before);
    expect(
      sum.creditsPerSecAfter,
      buildFlowReport(s, c, 'player').creditsPerSec,
    );
    expect(sum.creditsPerSecAfter > const BigNum.zero(), isTrue);
  });

  test('waste is valued in credits at current prices', () {
    final s = e.newGame(1);
    final kora = s.body('kora');
    kora.stock['copper_ore'] = storageCap(s, c, kora);
    final sum = e.catchUpOffline(s, 3600);
    expect(sum.totalWasted.toDouble(), closeTo(0.32 * 3600, 1e-6));
    expect(
      sum.wastedValue.toDouble(),
      closeTo(0.32 * 3600 * price(s, c, 'copper_ore').toDouble(), 1e-6),
    );
  });

  test('an ongoing bottleneck says since when, and whether it got worse', () {
    final s = e.newGame(1);
    final kora = s.body('kora');
    // The iron mine idles and the smelter runs dry: noted from t = 0.
    e.apply(s, const AssignCrewCommand('player', 'b1', 0));
    kora.stock['iron_ore'] = n(0);
    kora.stock['copper_ore'] = storageCap(s, c, kora);
    e.advance(s, 60);
    // A little ore turns up: the smelter runs at half for a second as the
    // absence begins, then dries up again: its loss doubles.
    kora.stock['iron_ore'] = n(0.2);
    final sum = e.catchUpOffline(s, 3600);
    final smelter = sum.topBottlenecks.singleWhere(
      (b) => b.kind == BottleneckKind.input,
    );
    final starved = sum.ongoingFor(smelter)!;
    expect(starved.since, 0);
    expect(starved.worseThanBefore, isTrue);
    expect(
      starved.lostBefore!.toDouble(),
      closeTo(smelter.lostCreditsPerHour!.toDouble() / 2, 1e-6),
    );
    // The full copper store wastes the same before and after.
    final full = sum.topBottlenecks.singleWhere(
      (b) => b.kind == BottleneckKind.storageFull,
    );
    expect(sum.ongoingFor(full)!.worseThanBefore, isFalse);
    // A bottleneck that began while away is not ongoing.
    final s2 = e.newGame(1);
    e.apply(s2, const AssignCrewCommand('player', 'b1', 0));
    final fresh = e.catchUpOffline(s2, 3600);
    final dry = fresh.topBottlenecks.singleWhere(
      (b) => b.kind == BottleneckKind.input,
    );
    expect(fresh.ongoingFor(dry), isNull);
  });

  group('next goal', () {
    test('is the milestone the current rates reach soonest', () {
      final s = e.newGame(1);
      // 12 of 30 steel made after a minute, at 0.2 a second: 90 s to go.
      final sum = e.catchUpOffline(s, 60);
      final goal = sum.nextGoal! as MilestoneGoal;
      expect(goal.milestoneId, 'first_steel');
      expect(goal.current.toDouble(), closeTo(12, 1e-9));
      expect(goal.target, n(30));
      expect(goal.etaSeconds, closeTo(90, 1e-6));
    });

    test('is the next megaproject stage when it comes sooner, with its '
        'ETA', () {
      final s = e.newGame(1);
      final f = s.faction('player');
      // Every milestone reached; the station's goods are all held, and
      // copper ore sells for its credits.
      f.reachedMilestones.addAll([for (final m in c.milestones) m.id]);
      final station = c.megaprojects['orbital_station']!;
      final cost = megaprojectCost(c, station, 0);
      for (final MapEntry(key: id, value: v) in cost.entries) {
        if (id != 'credits') s.body('kora').stock[id] = v;
      }
      e.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      final sum = e.catchUpOffline(s, 60);
      final goal = sum.nextGoal! as MegaprojectGoal;
      expect(goal.megaprojectId, 'orbital_station');
      expect(goal.level, 1);
      expect(goal.remaining, megaprojectRemaining(s, c, 'player', station));
      final short = cost['credits']! - f.credits;
      expect(
        goal.etaSeconds,
        closeTo((short / sum.creditsPerSecAfter).toDouble(), 1e-6),
      );
    });

    test('has no ETA for a stage whose goods are not being made', () {
      final s = e.newGame(1);
      s.faction('player').reachedMilestones.addAll([
        for (final m in c.milestones) m.id,
      ]);
      final sum = e.catchUpOffline(s, 60);
      final goal = sum.nextGoal! as MegaprojectGoal;
      expect(goal.etaSeconds, isNull);
    });
  });

  test('the summary round-trips through JSON', () {
    final s = e.newGame(1);
    s.faction('player').baseCrew = 2;
    final kora = s.body('kora');
    kora.stock['copper_ore'] = storageCap(s, c, kora);
    e.apply(s, const AssignCrewCommand('player', 'b1', 0));
    e.advance(s, 60);
    kora.stock['iron_ore'] = n(0.2);
    s.faction('player').credits = n(1e7);
    final claim = e.apply(
      s,
      const ClaimBodyCommand('player', 'hollow_reach', 'kora'),
    );
    expect(claim, isA<CommandOk>());
    final sum = e.catchUpOffline(s, 4 * 86400);
    expect(sum.projectsCompleted, isNotEmpty);
    expect(sum.ongoing, isNotEmpty);
    expect(sum.nextGoal, isNotNull);
    final json = jsonEncode(sum.toJson());
    final back = OfflineSummary.fromJson(
      jsonDecode(json) as Map<String, Object?>,
    );
    expect(jsonEncode(back.toJson()), json);
    expect(back.headline, sum.headline);
    expect(back.housingAfter.supported, sum.housingAfter.supported);
    expect(back.creditsPerSecAfter, sum.creditsPerSecAfter);
    expect(back.wastedValue, sum.wastedValue);
    expect(
      back.topBottlenecks.map((b) => b.lostCreditsPerHour),
      sum.topBottlenecks.map((b) => b.lostCreditsPerHour),
    );
  });
}
