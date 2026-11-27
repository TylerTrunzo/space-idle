import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' hide formatDuration;
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/view_models.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

BuildingRowView _row(BodyView body, String defName) =>
    body.buildings.firstWhere((b) => b.name == defName);

void main() {
  late GameController c;
  setUp(() => c = _controller());

  group('topBar', () {
    test('shows the starting credits, income and crew', () {
      final top = topBar(c);
      expect(top.credits, formatNumber(c.state.faction(_p).credits));
      expect(top.credits, '250');
      expect(top.creditsRate, formatRate(c.flow.creditsPerSec));
      final crew = crewTotals(c.state, content, _p);
      expect(top.crewFree, crew.free);
      expect(top.crewTotal, crew.supported);
    });

    test('pins up to 3 resources with the most stock on owned bodies', () {
      final kora = c.state.body('kora');
      kora.stock
        ..clear()
        ..['steel'] = BigNum.from(50)
        ..['iron_ore'] = BigNum.from(50)
        ..['copper_ore'] = BigNum.from(900)
        ..['silicon'] = BigNum.from(1);
      // Unowned bodies' stock does not count.
      c.state.body('cinder').stock['sulfur'] = BigNum.from(1e6);

      final pinned = topBar(c).pinned;
      // Ties by content order: Iron Ore comes before Steel there.
      expect(pinned.map((p) => p.name), ['Copper Ore', 'Iron Ore', 'Steel']);
      expect(pinned.first.value, '900');
    });

    test('pinned stock reads in whole units, rounded down', () {
      c.state.body('kora').stock
        ..clear()
        ..['copper_ore'] = BigNum.from(2.25)
        ..['iron_ore'] = BigNum.from(1999.9);
      final pinned = {for (final p in topBar(c).pinned) p.name: p.value};
      expect(pinned['Copper Ore'], '2');
      expect(pinned['Iron Ore'], '1.99K');
    });

    test('stays readable at 1e40 credits', () {
      c.state.faction(_p).credits = BigNum.parse('1e40');
      expect(topBar(c).credits, '1e40');
    });
  });

  group('bodyView of an owned body', () {
    test('an extractor row is named for what it mines', () {
      final names = bodyView(c, 'kora')!.buildings.map((b) => b.name);
      expect(names, ['Mine (Iron Ore)', 'Mine (Copper Ore)', 'Smelter']);
    });

    test('Kora has its 3 starting buildings and its slots', () {
      final kora = bodyView(c, 'kora')!;
      expect(kora.name, 'Kora');
      expect(kora.typeName, 'Rocky World');
      expect(kora.owned, isTrue);
      expect(kora.ownerName, 'Kora Compact');
      expect(kora.depositNames, ['Iron Ore', 'Copper Ore', 'Silicon']);
      expect(kora.buildings, hasLength(3));
      expect(kora.slotsUsed, 3);
      expect(kora.slotsTotal, buildSlots(content, c.state.body('kora')));
      expect(kora.claim, isNull);
    });

    test('the smelter row shows its recipe, crew and upgrades', () {
      c.tickSeconds(5);
      final smelter = _row(bodyView(c, 'kora')!, 'Smelter');
      expect(smelter.uses.map((u) => u.name), contains('Iron Ore'));
      expect(smelter.makes.map((u) => u.name), contains('Steel'));
      expect(smelter.uses.first.value, startsWith('-'));
      expect(smelter.makes.first.value, startsWith('+'));
      expect(smelter.crew, 1);
      expect(smelter.crewBaseSlots, 1);
      expect(smelter.crewMax, 1);
      expect(smelter.level, 0);
      expect(smelter.canRemoveCrew, isTrue);
      expect(smelter.canAddCrew, isFalse, reason: 'at its most crew');
      expect(smelter.upgrades.keys, {
        UpgradeTrack.speed,
        UpgradeTrack.efficiency,
        UpgradeTrack.capacity,
      });
      final speed = smelter.upgrades[UpgradeTrack.speed]!;
      expect(speed.label, 'Speed');
      expect(speed.cost, '75');
      expect(speed.affordable, isTrue);
      expect(speed.payback, isNull);
      expect(smelter.upgrades[UpgradeTrack.capacity]!.cost, '450');
      expect(smelter.upgrades[UpgradeTrack.capacity]!.affordable, isFalse);
    });

    test('a starved smelter is stopped or held back, naming Iron Ore', () {
      c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
      c.run(const AssignCrewCommand(_p, 'b1', 0)); // the iron mine
      c.tickSeconds(1);

      final kora = bodyView(c, 'kora')!;
      final smelter = _row(kora, 'Smelter');
      expect(smelter.severity, anyOf(Severity.stopped, Severity.warning));
      expect(smelter.problem, contains('Iron Ore'));
      final mine = kora.buildings.firstWhere((b) => b.id == 'b1');
      expect(mine.severity, Severity.stopped);
      expect(mine.problem, 'Mine on Kora has no crew');
      expect(mine.canAddCrew, isTrue);
      expect(mine.canRemoveCrew, isFalse);
    });

    test('a maxed upgrade track is unavailable, with the core\'s reason', () {
      c.state.faction(_p).credits = BigNum.parse('1e30');
      final b3 = c.state.body('kora').buildings.firstWhere((b) => b.id == 'b3');
      var level = 0;
      while (upgradeMaxedReason(content, b3, UpgradeTrack.efficiency) == null) {
        b3.levels[UpgradeTrack.efficiency] = ++level;
      }
      final why = upgradeMaxedReason(content, b3, UpgradeTrack.efficiency);

      final row = _row(bodyView(c, 'kora')!, 'Smelter');
      final eff = row.upgrades[UpgradeTrack.efficiency]!;
      expect(eff.affordable, isFalse, reason: 'the core refuses it');
      expect(eff.maxedReason, why);
      expect(
        c.run(const UpgradeCommand(_p, 'b3', UpgradeTrack.efficiency)),
        isA<CommandFailed>(),
      );
      // The other tracks are still open.
      expect(row.upgrades[UpgradeTrack.speed]!.maxedReason, isNull);
      expect(row.upgrades[UpgradeTrack.speed]!.affordable, isTrue);
    });

    test('a starved building with a capacity level is still a warning', () {
      // Capacity crew lifts effectiveFraction above its supply share, so
      // clamping it alone read a starved smelter as ok.
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const UpgradeCommand(_p, 'b3', UpgradeTrack.capacity));
      c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
      c.tickSeconds(30);

      final status = c.flow.bodies
          .firstWhere((b) => b.bodyId == 'kora')
          .buildings
          .firstWhere((b) => b.buildingId == 'b3');
      expect(status.runFraction, lessThan(1), reason: 'fixture: starved');
      final smelter = _row(bodyView(c, 'kora')!, 'Smelter');
      expect(smelter.severity, isNot(Severity.ok));
      expect(smelter.runFraction, lessThan(1));
      expect(smelter.problem, contains('Iron Ore'));
    });

    test('a building named in a bottleneck is at least a warning', () {
      final s = c.state;
      final body = s.body('kora');
      final b = body.buildings.firstWhere((x) => x.id == 'b3');
      final row = buildingRowView(
        s,
        content,
        _p,
        b,
        BuildingStatus(
          buildingId: 'b3',
          defId: 'smelter',
          runFraction: 1,
          effectiveFraction: 1,
          limitReason: null,
          crew: 1,
          slots: 1,
          inputsPerSec: const {},
          outputsPerSec: const {},
        ),
        RowContext.of(s, content, _p, body, const [
          Bottleneck(
            kind: BottleneckKind.understaffed,
            bodyId: 'kora',
            buildingId: 'b3',
            resourceId: null,
            runFraction: 0.5,
            buildingIds: ['b3'],
          ),
        ]),
      );
      expect(row.severity, Severity.warning);
      expect(row.problem, isNotNull);
    });

    test('a capacity-crewed building short of housing is not ok', () {
      // Two crew on a 1-slot smelter (a capacity level) lift its output
      // share above 1, so "below 1" missed the housing shortfall.
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const UpgradeCommand(_p, 'b3', UpgradeTrack.capacity));
      c.run(const AssignCrewCommand(_p, 'b3', 2));
      final kora = c.state.body('kora');
      kora.stock['iron_ore'] = BigNum.from(1e6);
      kora.stock['copper_ore'] = BigNum.from(1e6);
      final assigned = crewTotals(c.state, content, _p).assigned;
      c.state.faction(_p).baseCrew = assigned - 1;
      c.tickSeconds(5);

      final smelter = _row(bodyView(c, 'kora')!, 'Smelter');
      expect(smelter.crew, 2);
      expect(smelter.severity, Severity.warning);
      expect(smelter.problem, startsWith('Short of crew: '));
    });

    test('during a crew shortage, rows housing is not slowing go unblamed', () {
      // A shortage is on (housing for 1 of 3), but an empty smelter and a
      // depot (no crew slots) are not held back by housing: they must not
      // be told they are short of crew.
      final kora = c.state.body('kora');
      kora.buildings
        ..add(
          BuildingState(
            id: 'b_empty',
            defId: 'smelter',
            crew: 0,
            levels: {for (final t in UpgradeTrack.values) t: 0},
          ),
        )
        ..add(
          BuildingState(
            id: 'b_depot',
            defId: 'depot',
            crew: 0,
            levels: {for (final t in UpgradeTrack.values) t: 0},
          ),
        );
      kora.stock['iron_ore'] = BigNum.from(1e6);
      c.state.faction(_p).baseCrew = 1;
      c.tickSeconds(5);
      expect(
        c.flow.bottlenecks.map((n) => n.kind),
        contains(BottleneckKind.crewShortage),
        reason: 'fixture: a shortage is on',
      );

      final rows = {for (final r in bodyView(c, 'kora')!.buildings) r.id: r};
      expect(rows['b_empty']!.problem, 'Smelter on Kora has no crew');
      expect(rows['b_depot']!.problem, isNull);
      // A crewed row the shortage does slow still says so.
      expect(rows['b1']!.problem, startsWith('Short of crew'));
    });

    test('a building held back only by a crew shortage says so', () {
      // Housing for 1 crew with 3 assigned: every crewed building runs at
      // a third, and only the faction-wide crewShortage names a cause.
      c.state.faction(_p).baseCrew = 1;
      c.tickSeconds(5);
      expect(
        c.flow.bottlenecks.map((n) => n.kind),
        contains(BottleneckKind.crewShortage),
      );
      final mine = bodyView(
        c,
        'kora',
      )!.buildings.firstWhere((b) => b.id == 'b1');
      final t = crewTotals(c.state, content, _p);
      expect(mine.severity, Severity.warning);
      expect(
        mine.problem,
        'Short of crew: ${t.supported} of ${t.assigned} crew housed',
      );
    });

    test('rows on another faction\'s body offer no actions', () {
      final s = c.state;
      s.faction(_p).credits = BigNum.parse('1e30');
      final body = s.body('cinder')..ownerId = 'rival';
      final b = BuildingState(
        id: 'b_rival',
        defId: 'smelter',
        crew: 1, // crew to take out, so the canRemoveCrew gate shows
        levels: {for (final t in UpgradeTrack.values) t: 0},
      );
      body.buildings.add(b);

      final row = buildingRowView(
        s,
        content,
        _p,
        b,
        null,
        RowContext.of(s, content, _p, body, const []),
      );
      expect(row.canAddCrew, isFalse);
      expect(row.canRemoveCrew, isFalse);
      expect(row.upgrades.values.map((u) => u.affordable), everyElement(false));
    });

    test('a building running freely is ok with no problem', () {
      c.tickSeconds(5);
      final mine = bodyView(
        c,
        'kora',
      )!.buildings.firstWhere((b) => b.id == 'b1');
      expect(mine.severity, Severity.ok);
      expect(mine.runFraction, 1);
      expect(mine.problem, isNull);
    });

    test('storage rows show stock, cap, fill, net, price and auto-sell', () {
      c.tickSeconds(5);
      final kora = c.state.body('kora');
      final cap = storageCap(c.state, content, kora);
      final view = bodyView(c, 'kora')!;
      final iron = view.storage.firstWhere((r) => r.id == 'iron_ore');
      expect(iron.name, 'Iron Ore');
      expect(iron.amount, formatNumber(kora.stock['iron_ore']!));
      expect(iron.cap, formatNumber(cap));
      expect(
        iron.fill,
        closeTo(kora.stock['iron_ore']!.toDouble() / cap.toDouble(), 1e-9),
      );
      expect(
        iron.price,
        formatAmount(salePrice(c.state, content, _p, 'iron_ore')),
      );
      expect(iron.autoSell, isFalse);
      expect(iron.alert, StockAlert.none);
    });

    test('a full store that wastes output is flagged full', () {
      final kora = c.state.body('kora');
      kora.stock['copper_ore'] = storageCap(c.state, content, kora);
      c.tickSeconds(5);
      final copper = bodyView(
        c,
        'kora',
      )!.storage.firstWhere((r) => r.id == 'copper_ore');
      expect(copper.fill, 1);
      expect(copper.alert, StockAlert.full);
    });

    test('a store about to run dry is flagged running out', () {
      // The smelter draws iron ore; with the mine idle it only falls.
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      c.state.body('kora').stock['iron_ore'] = BigNum.from(5);
      c.tickSeconds(1);
      final iron = bodyView(
        c,
        'kora',
      )!.storage.firstWhere((r) => r.id == 'iron_ore');
      expect(iron.net, startsWith('-'));
      expect(iron.alert, StockAlert.runningOut);
    });

    test('every price is the core salePrice, Mass Driver bonus included', () {
      c.state.faction(_p).megaprojectLevels['mass_driver'] = 3;
      for (final id in content.resources.keys) {
        c.state.body('kora').stock[id] = BigNum.from(1);
      }
      final rows = bodyView(c, 'kora')!.storage;
      expect(rows, hasLength(content.resources.length));
      for (final r in rows) {
        expect(
          r.price,
          formatAmount(salePrice(c.state, content, _p, r.id)),
          reason: r.id,
        );
      }
      // The bonus makes a difference somewhere, so the check means it.
      expect(
        content.resources.keys.any(
          (id) =>
              salePrice(c.state, content, _p, id) !=
              price(c.state, content, id),
        ),
        isTrue,
      );
    });

    test('auto-sell rules show on their rows', () {
      c.run(const SetAutoSellCommand(_p, 'kora', 'steel', BigNum.zero()));
      c.tickSeconds(5);
      final steel = bodyView(
        c,
        'kora',
      )!.storage.firstWhere((r) => r.id == 'steel');
      expect(steel.autoSell, isTrue);
    });

    test('routes out and in', () {
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e6);
      final r = c.run(
        CreateRouteCommand(
          _p,
          'kora',
          'brine',
          'iron_ore',
          BigNum.from(0.5),
          1,
        ),
      );
      expect(r, isA<CommandOk>(), reason: c.lastError);

      final out = bodyView(c, 'kora')!.routesOut.single;
      expect(out.fromName, 'Kora');
      expect(out.toName, 'Brine');
      expect(out.resourceName, 'Iron Ore');
      expect(out.rate, '0.5/s');
      expect(out.ships, 1);
      expect(
        out.travel,
        formatDuration(
          travelSeconds(
            c.state,
            content,
            c.state.body('kora'),
            c.state.body('brine'),
          ),
        ),
      );
      expect(bodyView(c, 'brine')!.routesIn.single.id, out.id);
      expect(bodyView(c, 'kora')!.routesIn, isEmpty);
    });
  });

  group('bodyView of an unowned body', () {
    test('has a first claim with no kits needed', () {
      final cinder = bodyView(c, 'cinder')!;
      expect(cinder.owned, isFalse);
      expect(cinder.ownerName, isNull);
      expect(cinder.buildings, isEmpty);
      final claim = cinder.claim!;
      expect(claim.kitsNeeded, 0);
      expect(claim.creditsCost, '5K');
      expect(claim.affordable, isFalse, reason: '250 credits only');
      expect(claim.sourceBodyIds, ['kora']);
    });

    test('a second claim needs kits; sources are the bodies holding them', () {
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('brine').stock['outpost_kit'] = BigNum.from(100);

      final claim = bodyView(c, 'cinder')!.claim!;
      expect(claim.kitsNeeded, 10);
      expect(claim.sourceBodyIds, ['brine']);
      expect(claim.affordable, isTrue);
    });

    test('a body being claimed shows the claim running, not affordable', () {
      c.state.faction(_p).credits = BigNum.from(1e9);
      expect(bodyView(c, 'brine')!.claim!.running, isNull);
      c.run(const ClaimBodyCommand(_p, 'brine', 'kora'));

      final claim = bodyView(c, 'brine')!.claim!;
      expect(claim.affordable, isFalse, reason: 'the core refuses a second');
      expect(claim.running?.title, 'Claiming Brine');
      expect(claim.running?.remaining, '30m');
      expect(
        c.run(const ClaimBodyCommand(_p, 'brine', 'kora')),
        isA<CommandFailed>(),
      );
    });

    test('a hidden body has no view until surveyed', () {
      expect(bodyView(c, 'tessaly'), isNull);
      expect(bodyView(c, 'no_such_body'), isNull);
      c.state.body('tessaly').surveyed = true;
      expect(bodyView(c, 'tessaly'), isNotNull);
    });
  });
}
