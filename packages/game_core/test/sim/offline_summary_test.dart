import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:game_core/src/sim/milestones.dart' show factionStock;
import 'package:game_core/src/sim/offline_summary.dart' show megaprojectEtas;
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

    test('shows in the crew counts on return', () {
      final sum = e.catchUpOffline(bug2(), 3600);
      expect((sum.housingAfter.supported, sum.housingAfter.assigned), (4, 6));
      expect(sum.housingAfter.overAssigned, 2);
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
    expect(sum.housingAfter.overAssigned, 0);
  });

  test('an ongoing crew shortage is compared on its full-staffing loss', () {
    // Short of crew from the start; the habitat's food runs out while away,
    // so the shortage deepens.
    final s = e.newGame(1);
    s.faction('player').baseCrew = 2;
    final kora = s.body('kora');
    kora.buildings.add(
      BuildingState(id: 'h1', defId: 'habitat', crew: 0, lastRunFraction: 1)
        ..levels[UpgradeTrack.capacity] = 0,
    );
    kora.buildings.first.levels[UpgradeTrack.capacity] = 30;
    kora.buildings.first.crew = 22;
    kora.stock
      ..['food'] = n(30)
      ..['water'] = n(1000)
      ..['oxygen'] = n(1000);
    e.advance(s, 60);
    final before = buildFlowReport(
      s.copy(),
      c,
      'player',
    ).bottlenecks.singleWhere((b) => b.kind == BottleneckKind.crewShortage);
    final sum = e.catchUpOffline(s, 3600);
    final crew = sum.topBottlenecks.first;
    expect(crew.kind, BottleneckKind.crewShortage);
    final ongoing = sum.ongoingFor(crew)!;
    expect(ongoing.lostBefore, before.lostCreditsPerHour);
    expect(ongoing.worseThanBefore, isTrue);
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
    expect(sum.housingAfter.overAssigned, 0);
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

  group('bottlenecks by cause', () {
    /// A new game with [presses] plate presses on Kora, all short of the
    /// 0.2 steel a second the smelter makes; the plates and copper ore
    /// auto-sell.
    GameState starved(int presses) {
      final s = e.newGame(1);
      s.faction('player').baseCrew = 40;
      for (final id in ['hull_plate', 'copper_ore']) {
        e.apply(s, SetAutoSellCommand('player', 'kora', id, n(0)));
      }
      for (var i = 0; i < presses; i++) {
        s
            .body('kora')
            .buildings
            .add(
              BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
            );
      }
      e.advance(s, 60);
      return s;
    }

    bool shortOfSteel(Bottleneck b) =>
        b.kind == BottleneckKind.input && b.resourceId == 'steel';

    test('17 presses short of steel are one entry, their losses summed', () {
      // Round-4 casual bug 2: 17 identical dock rows filled the top 3.
      final s = starved(17);
      final r = buildFlowReport(s, c, 'player');
      final each = r.bottlenecks.where(shortOfSteel).toList();
      expect(each, hasLength(17));
      final group = r.groupedBottlenecks.where(shortOfSteel).single;
      expect(group.count, 17);
      expect(group.buildingId, isNull);
      expect(group.buildingIds, [for (final b in each) b.buildingId]);
      final total = each.fold(
        0.0,
        (t, b) => t + b.lostCreditsPerHour!.toDouble(),
      );
      expect(
        group.lostCreditsPerHour!.toDouble(),
        closeTo(total, total * 1e-9),
      );
      final sum = e.catchUpOffline(s, 3600);
      expect(sum.topBottlenecks.where(shortOfSteel).single.count, 17);
      final keys = [for (final b in sum.topBottlenecks) b.groupKey];
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('the groups rank the same after 1 s steps as after 60 s ones', () {
      final a = starved(17);
      final b = a.copy();
      e.advance(a, 600);
      e.advance(b, 600, maxStep: 1);
      List<String> ranked(GameState s) => [
        for (final n in buildFlowReport(s, c, 'player').groupedBottlenecks)
          n.groupKey,
      ];
      expect(ranked(b), ranked(a));
    });

    test('a full store that costs more outranks the group', () {
      final s = starved(17);
      final kora = s.body('kora');
      // The copper mine, sped up and with no rule selling its ore, wastes
      // it at a full store.
      kora.buildings
              .firstWhere((b) => b.id == 'b2')
              .levels[UpgradeTrack.speed] =
          60;
      kora.stock['copper_ore'] = storageCap(s, c, kora);
      s
          .faction('player')
          .autoSell
          .removeWhere((r) => r.resourceId == 'copper_ore');
      final sum = e.catchUpOffline(s, 3600);
      final kinds = [for (final b in sum.topBottlenecks) b.kind];
      expect(kinds.indexOf(BottleneckKind.storageFull), 0);
      expect(kinds, contains(BottleneckKind.input));
      final full = sum.topBottlenecks.first;
      final group = sum.topBottlenecks.firstWhere(shortOfSteel);
      expect(full.lostCreditsPerHour! > group.lostCreditsPerHour!, isTrue);
    });

    test('what the cap cut while away is in the top 3 when it is the most, '
        'though no store is full on return', () {
      // Round-4 casual bug 2: 1.29B wasted while away, never shown.
      final s = starved(17);
      // A lot of 100K steel lands on Kora 10 minutes in: what passes the
      // cap is cut, and the presses have used the rest by the return.
      s.shipments.add(
        Shipment(
          routeId: 'move',
          fromBodyId: 'brine',
          toBodyId: 'kora',
          ownerId: 'player',
          resourceId: 'steel',
          amount: n(1e5),
          departAt: s.time,
          arriveAt: s.time + 600,
        ),
      );
      final sum = e.catchUpOffline(s, 3600);
      expect(
        buildFlowReport(s, c, 'player').bottlenecks.map((b) => b.kind),
        isNot(contains(BottleneckKind.storageFull)),
      );
      final top = sum.topBottlenecks.first;
      expect(top.kind, BottleneckKind.storageFull);
      expect((top.bodyId, top.resourceId), ('kora', 'steel'));
      // Its text is the display's to build: the summary has no English.
      expect((top.fromAbsence, top.message), (true, ''));
      // The value cut, an hour, over the hour away.
      expect(
        top.lostCreditsPerHour!.toDouble(),
        closeTo(sum.wastedValue.toDouble(), sum.wastedValue.toDouble() * 0.01),
      );
      expect(top.firstSeenAt, greaterThan(sum.awayFrom));
      expect(sum.ongoingFor(top), isNull);
    });
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
      // Its auto-delivery never set: a new player's goal, though nothing
      // pays it yet.
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

    test('skips a megaproject owed credits that nothing pays', () {
      // Round-4 optimizer: with credit auto-pay turned off and nothing
      // paid by hand, the next goal still named the station.
      final s = e.newGame(1);
      final f = s.faction('player');
      final station = c.megaprojects['orbital_station']!;
      for (final MapEntry(key: id, value: v) in megaprojectCost(
        c,
        station,
        0,
      ).entries) {
        if (id != 'credits') s.body('kora').stock[id] = v;
      }
      e.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      NextGoal? goal() =>
          nextGoal(s, c, 'player', buildFlowReport(s, c, 'player'));
      // Never set, it is the player's goal.
      f.reachedMilestones.addAll([for (final m in c.milestones) m.id]);
      expect((goal()! as MegaprojectGoal).megaprojectId, station.id);
      f.reachedMilestones.clear();
      // Goods go in on their own; credits do not: a choice.
      e.apply(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          true,
          false,
        ),
      );
      e.advance(s, 120);
      expect(megaprojectRemaining(s, c, 'player', station).keys, ['credits']);
      // The milestone the rates reach soonest instead.
      expect(goal(), isA<MilestoneGoal>());
      // Nor once every milestone is reached.
      f.reachedMilestones.addAll([for (final m in c.milestones) m.id]);
      expect(goal(), isNull);
      // With a credit paid by hand it is the player's goal again.
      f.megaprojectProgress[station.id]!['credits'] = n(1);
      expect((goal()! as MegaprojectGoal).megaprojectId, station.id);
      f.megaprojectProgress[station.id]!.remove('credits');
      // And with credit auto-pay on.
      e.apply(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          true,
          true,
        ),
      );
      expect((goal()! as MegaprojectGoal).megaprojectId, station.id);
    });

    test('is never a megaproject still locked', () {
      final s = e.newGame(1);
      final f = s.faction('player');
      f.reachedMilestones.addAll([for (final m in c.milestones) m.id]);
      // Every good of the Mass Driver held; the station's are not made.
      final driver = c.megaprojects['mass_driver']!;
      for (final MapEntry(key: id, value: v) in megaprojectCost(
        c,
        driver,
        0,
      ).entries) {
        if (id != 'credits') s.body('kora').stock[id] = v;
      }
      e.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      // Both take credits on their own, so both are the player's goals.
      for (final m in ['orbital_station', 'mass_driver']) {
        e.apply(s, SetMegaprojectAutoCommand('player', m, false, true));
      }
      e.advance(s, 60);
      final report = buildFlowReport(s, c, 'player');
      expect(
        (nextGoal(s, c, 'player', report)! as MegaprojectGoal).megaprojectId,
        'orbital_station',
      );
      f.megaprojectLevels['orbital_station'] = 2;
      expect(
        (nextGoal(s, c, 'player', report)! as MegaprojectGoal).megaprojectId,
        'mass_driver',
      );
    });

    group('shares what auto-delivery hands over', () {
      final station = c.megaprojects['orbital_station']!;
      final driver = c.megaprojects['mass_driver']!;

      /// A new game with every milestone reached, no contracts, the Mass
      /// Driver open with a stage of it under way (so the next one waits
      /// once paid for), Kora's copper ore and steel auto-sold, and
      /// [credits] held. Each megaproject's next stage is paid for but for
      /// what [owed] lists of it.
      GameState shape(
        Map<String, Map<String, num>> owed, {
        required num credits,
      }) {
        final s = e.newGame(1);
        final f = s.faction('player');
        f.reachedMilestones.addAll([for (final m in c.milestones) m.id]);
        f.contracts.clear();
        f.contractRefillAt
          ..clear()
          ..addAll(List.filled(RulesDef.contractSlots, 1e12));
        f.megaprojectLevels['orbital_station'] = 1;
        s.projects.add(
          ProjectState(
            id: s.newId('p'),
            factionId: 'player',
            kind: ProjectKind.megaprojectStage,
            targetId: 'mass_driver',
            startedAt: 0,
            finishAt: 1e9,
          ),
        );
        for (final m in [station, driver]) {
          final cost = megaprojectCost(
            c,
            m,
            megaprojectDeliveryLevel(s, 'player', m),
          );
          f.megaprojectProgress[m.id] = {
            for (final MapEntry(key: id, value: v) in cost.entries)
              id: v - n(owed[m.id]?[id] ?? 0),
          };
        }
        f.credits = n(credits);
        for (final id in ['copper_ore', 'steel']) {
          e.apply(s, SetAutoSellCommand('player', 'kora', id, n(0)));
        }
        return s;
      }

      /// Seconds of 60 s steps until [m]'s next stage has been paid for in
      /// full, or, unless [fed], can be from what [s] holds.
      double reached(GameState s, MegaprojectDef m, {bool fed = false}) {
        final start = s.time;
        final f = s.faction('player');
        bool can() {
          if (megaprojectStageQueued(s, c, 'player', m)) return true;
          if (fed) return false;
          final held = factionStock(s, 'player');
          return megaprojectRemaining(s, c, 'player', m).entries.every(
            (x) =>
                (x.key == 'credits' ? f.credits : held[x.key] ?? n(0)) >=
                x.value,
          );
        }

        while (!can()) {
          e.advance(s, 60);
          expect(s.time - start, lessThan(4e5));
        }
        return s.time - start;
      }

      test('a stage paid by hand waits for credits paid to another on '
          'their own, after it in content order', () {
        // The optimizer's day 14: the Mass Driver takes every credit above
        // its reserve, so the station's credits wait for it.
        final s = shape({
          'orbital_station': {'credits': 9000},
          // A good nothing makes: the Mass Driver never completes, but its
          // credits are paid in.
          'mass_driver': {'credits': 12000, 'silicon_wafer': 1},
        }, credits: 3000);
        e
          ..apply(
            s,
            const SetMegaprojectAutoCommand(
              'player',
              'mass_driver',
              true,
              true,
            ),
          )
          ..apply(s, SetAutoPayReserveCommand('player', n(1000)));
        e.advance(s, 120);
        final goal =
            nextGoal(s, c, 'player', buildFlowReport(s, c, 'player'))!
                as MegaprojectGoal;
        expect(goal.megaprojectId, 'orbital_station');
        final actual = reached(s, station);
        expect(goal.etaSeconds, closeTo(actual, actual * 0.15));
      });

      test('and before it in content order', () {
        // The casual day 7: the station takes the credits, the Mass
        // Driver's wait.
        final s = shape({
          'orbital_station': {'credits': 12000, 'reactor_core': 1},
          'mass_driver': {'credits': 9000},
        }, credits: 3000);
        e
          ..apply(
            s,
            const SetMegaprojectAutoCommand(
              'player',
              'orbital_station',
              true,
              true,
            ),
          )
          ..apply(s, SetAutoPayReserveCommand('player', n(1000)));
        e.advance(s, 120);
        final goal =
            nextGoal(s, c, 'player', buildFlowReport(s, c, 'player'))!
                as MegaprojectGoal;
        expect(goal.megaprojectId, 'mass_driver');
        final actual = reached(s, driver);
        expect(goal.etaSeconds, closeTo(actual, actual * 0.15));
      });

      test('credits for two megaprojects fed them both are split evenly: '
          'the one owing less is done first', () {
        final s = shape({
          'orbital_station': {'credits': 9000, 'reactor_core': 1},
          'mass_driver': {'credits': 6000},
        }, credits: 3000);
        for (final m in [station, driver]) {
          e.apply(s, SetMegaprojectAutoCommand('player', m.id, true, true));
        }
        e
          ..apply(s, SetAutoPayReserveCommand('player', n(1000)))
          ..advance(s, 120);
        final report = buildFlowReport(s, c, 'player');
        final etas = megaprojectEtas(s, c, 'player', report);
        expect(etas['orbital_station'], isNull);
        final goal = nextGoal(s, c, 'player', report)! as MegaprojectGoal;
        expect(goal.megaprojectId, 'mass_driver');
        final actual = reached(s, driver, fed: true);
        expect(goal.etaSeconds, closeTo(actual, actual * 0.15));
        // Half the income went to each: the Mass Driver's 6K took about
        // twice as long as its credits alone would.
        final owed = 6000 - 2 * 60 * report.creditsPerSec.toDouble();
        expect(actual, greaterThan(owed / report.creditsPerSec.toDouble()));
      });

      test('from the review\'s optimizer state on day 14, the ETA is the '
          'one a run without commands gives', () {
        // Balanced bot, seed 1, day 14, saved before the reserve was
        // shared: both megaprojects take credits (above the lower of their
        // two reserves, as the save is read) and lack nothing else.
        final saved = File(
          'test/fixtures/review_balanced_day14.json',
        ).readAsStringSync();
        final s = (SaveCodec.decode(saved, c) as SaveOk).state;
        final f = s.faction('player');
        expect(
          [for (final a in f.megaprojectAuto.values) a.credits],
          [true, true],
        );
        final goal =
            nextGoal(s, c, 'player', buildFlowReport(s, c, 'player'))!
                as MegaprojectGoal;
        expect(goal.megaprojectId, 'orbital_station');
        expect(goal.remaining.keys, ['credits']);
        final start = s.time;
        while (megaprojectStageOf(s, 'player', 'orbital_station') == null) {
          e.advance(s, 60);
          expect(s.time - start, lessThan(120 * 3600));
        }
        final actual = s.time - start;
        expect(goal.etaSeconds, closeTo(actual, actual * 0.15));
      });

      test('a good held for both goes to the first fed it, then what is '
          'made', () {
        // Hull plates for both, as many held as the station lacks: the
        // Mass Driver's come only as Kora's press makes them.
        final s = shape({
          'orbital_station': {'hull_plate': 30, 'reactor_core': 1},
          'mass_driver': {'hull_plate': 30},
        }, credits: 0);
        s.faction('player').baseCrew += 1;
        s.body('kora')
          ..buildings.add(
            BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
          )
          ..stock['hull_plate'] = n(30);
        for (final m in [station, driver]) {
          e.apply(s, SetMegaprojectAutoCommand('player', m.id, true, false));
        }
        final goal =
            nextGoal(s, c, 'player', buildFlowReport(s, c, 'player'))!
                as MegaprojectGoal;
        expect(goal.megaprojectId, 'mass_driver');
        final actual = reached(s, driver, fed: true);
        expect(actual, greaterThan(120));
        expect(goal.etaSeconds, closeTo(actual, actual * 0.15));
      });
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

  test('a next goal of an unknown kind is refused with a FormatException', () {
    expect(
      () => NextGoal.fromJson({'kind': 'station', 'etaSeconds': 5}),
      throwsFormatException,
    );
    final stage = MegaprojectGoal(
      megaprojectId: 'orbital_station',
      level: 2,
      remaining: {'credits': n(5)},
    );
    final back = NextGoal.fromJson(stage.toJson()) as MegaprojectGoal;
    expect(
      (back.megaprojectId, back.level, back.etaSeconds),
      ('orbital_station', 2, null),
    );
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
    expect(back.creditsEarned, sum.creditsEarned);
    expect(back.housingAfter.supported, sum.housingAfter.supported);
    expect(back.creditsPerSecAfter, sum.creditsPerSecAfter);
    expect(back.wastedValue, sum.wastedValue);
    expect(
      back.topBottlenecks.map((b) => b.lostCreditsPerHour),
      sum.topBottlenecks.map((b) => b.lostCreditsPerHour),
    );
  });
}
