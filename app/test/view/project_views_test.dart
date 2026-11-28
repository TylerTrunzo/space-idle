import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' hide formatDuration;
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/messages.dart';
import 'package:space_idle/view/project_views.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

/// Plenty of credits and of every resource on Kora.
void _enrich(GameController c) {
  c.state.faction(_p).credits = BigNum.parse('1e15');
  for (final id in content.resources.keys) {
    c.state.body('kora').stock[id] = BigNum.from(1e7);
  }
}

MegaprojectView _mp(GameController c, String id) =>
    megaprojectViews(c).singleWhere((m) => m.id == id);

void main() {
  late GameController c;
  setUp(() => c = _controller());

  group('projectViews', () {
    test('a new claim is at 0 with 30m to go; 15 min later halfway', () {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const ClaimBodyCommand(_p, 'brine', 'kora'));

      final p = projectViews(c).single;
      expect(p.kind, ProjectKind.claim);
      expect(p.title, 'Claiming Brine');
      expect(p.bodyId, 'brine');
      expect(p.progress, 0);
      expect(p.remaining, '30m');

      c.tickSeconds(15 * 60);
      final half = projectViews(c).single;
      expect(half.progress, closeTo(0.5, 1e-9));
      expect(half.remaining, '15m');
    });

    test('surveys, slot expansions and megaproject stages are named', () {
      _enrich(c);
      c.run(const SurveyCommand(_p, null, 'kora'));
      c.run(const ExpandSlotsCommand(_p, 'kora'));
      c.run(const StartMegaprojectStageCommand(_p, 'orbital_station', 'kora'));

      final titles = {for (final p in projectViews(c)) p.kind: p.title};
      // A survey's target is hidden until it completes: not named.
      expect(titles[ProjectKind.survey], 'Surveying a signal');
      expect(titles[ProjectKind.expandSlots], 'Extra build slot on Kora');
      expect(titles[ProjectKind.megaprojectStage], 'Orbital Station level 1');
      final survey = projectViews(c)
          .firstWhere((p) => p.kind == ProjectKind.survey);
      expect(survey.bodyId, isNull);
    });

    test('progress never goes past 0..1 and remaining never negative', () {
      c.state.projects.add(
        ProjectState(
          id: 'p_old',
          factionId: _p,
          kind: ProjectKind.claim,
          targetId: 'cinder',
          startedAt: c.state.time + 100,
          finishAt: c.state.time + 200,
        ),
      );
      final p = projectViews(c).single;
      expect(p.progress, 0);
      expect(p.remaining, isNot(startsWith('-')));
    });
  });

  group('megaprojectViews', () {
    test('covers both megaprojects in content order', () {
      expect(megaprojectViews(c).map((m) => m.id), [
        'orbital_station',
        'mass_driver',
      ]);
    });

    test('a new station shows its level-1 cost lines and next bonus', () {
      final station = _mp(c, 'orbital_station');
      final def = content.megaprojects['orbital_station']!;
      expect(station.name, 'Orbital Station');
      expect(station.level, 0);
      expect(station.nextBonus, megaprojectBonusText(def, 1));
      expect(station.locked, isNull);
      expect(station.running, isNull);
      expect(station.queued, isFalse);
      final cost = megaprojectCost(content, def, 0);
      expect(station.lines.map((l) => l.id), cost.keys);
      final credits = station.lines.firstWhere((l) => l.id == creditsKey);
      expect(credits.name, 'Credits');
      expect(credits.needed, formatNumber(cost[creditsKey]!));
      expect(credits.delivered, '0');
      expect(credits.fill, 0);
    });

    test('the Mass Driver is locked until the station reaches level 1', () {
      final driver = _mp(c, 'mass_driver');
      expect(driver.locked, 'Opens at Orbital Station level 1 (now 0)');
      expect(driver.takesDeliveries, isFalse);
    });

    test(
      'deliveries fill the lines and best sources name the fullest body',
      () {
        _enrich(c);
        c.state.body('brine').ownerId = _p;
        c.state.body('brine').stock['hull_plate'] = BigNum.from(1e9);
        c.run(
          DeliverToMegaprojectCommand(_p, 'orbital_station', 'kora', {
            'hull_plate': BigNum.from(300),
          }),
        );
        final station = _mp(c, 'orbital_station');
        final hull = station.lines.firstWhere((l) => l.id == 'hull_plate');
        expect(hull.name, 'Hull Plate');
        expect(hull.delivered, '300');
        expect(hull.fill, closeTo(300 / 1500, 1e-9));
        expect(station.bestSources['hull_plate']!.name, 'Brine');
        expect(
          station.bestSources['hull_plate']!.value,
          formatNumber(BigNum.from(1e9)),
        );
        expect(station.bestSources.containsKey(creditsKey), isFalse);
      },
    );

    test('the bonus describes the stage the cost lines are for', () {
      final def = content.megaprojects['orbital_station']!;
      var station = _mp(c, 'orbital_station');
      expect(station.nextBonus, megaprojectBonusText(def, 1));
      expect(station.runningBonus, isNull);

      _enrich(c);
      c.run(const StartMegaprojectStageCommand(_p, 'orbital_station', 'kora'));
      station = _mp(c, 'orbital_station');
      // Lines are for level 2's stage now; level 1's is under way.
      expect(station.deliveryLevel, 1);
      expect(
        station.lines.map((l) => l.needed),
        megaprojectCost(content, def, 1).values.map(formatNumber),
      );
      expect(station.nextBonus, megaprojectBonusText(def, 2));
      expect(station.runningBonus, megaprojectBonusText(def, 1));
    });

    test('a running stage and the queued one after it', () {
      _enrich(c);
      c.run(const StartMegaprojectStageCommand(_p, 'orbital_station', 'kora'));
      var station = _mp(c, 'orbital_station');
      expect(station.running?.title, 'Orbital Station level 1');
      expect(station.queued, isFalse);
      expect(station.deliveryLevel, 1);

      c.run(const StartMegaprojectStageCommand(_p, 'orbital_station', 'kora'));
      station = _mp(c, 'orbital_station');
      expect(station.queued, isTrue);
    });

    test('shows the auto settings and whether goods go in now', () {
      expect(_mp(c, 'orbital_station').auto.goods, GoodsFeedMode.off);
      expect(_mp(c, 'orbital_station').auto.goodsFedNow, isFalse);

      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
          credits: true,
          creditWeight: 3,
        ),
      );
      final auto = _mp(c, 'orbital_station').auto;
      expect(auto.goods, GoodsFeedMode.always);
      expect(auto.credits, isTrue);
      expect(auto.creditWeight, 3);
      expect(auto.goodsFedNow, isTrue);

      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
        ),
      );
      // Near ready only feeds once a stage is near ready.
      expect(_mp(c, 'orbital_station').auto.goodsFedNow, isFalse);
    });
  });

  group('contracts', () {
    ContractState post(GameController c) {
      final k = ContractState(
        id: 'c_one',
        templateId: 'veyra_bulk',
        resourceId: 'copper_ore',
        quantity: BigNum.from(1000),
        rewardCredits: BigNum.from(7500),
        postedAt: c.state.time,
      );
      c.state.faction(_p).contracts.add(k);
      return k;
    }

    test('a posted contract with its progress, reward and sources', () {
      post(c);
      c.state.body('kora').stock['copper_ore'] = BigNum.from(400);
      c.run(DeliverContractCommand(_p, 'c_one', 'kora', BigNum.from(250)));

      final k = contractViews(c).single;
      expect(k.id, 'c_one');
      expect(k.title, 'Veyra Exchange');
      expect(k.resourceName, 'Copper Ore');
      expect(k.delivered, '250');
      expect(k.quantity, '1K');
      expect(k.fill, closeTo(0.25, 1e-9));
      expect(k.reward, '7.5K');
      expect(k.sources.single.bodyId, 'kora');
      expect(k.sources.single.bodyName, 'Kora');
      expect(k.sources.single.amount, '150');
    });

    test('nextContractIn reads the soonest refill', () {
      final f = c.state.faction(_p);
      f.contractRefillAt
        ..clear()
        ..addAll([c.state.time + 7200, c.state.time + 3600]);
      expect(nextContractIn(c), '1h');
      f.contractRefillAt
        ..clear()
        ..add(c.state.time - 5);
      expect(nextContractIn(c), 'due now');
      f.contractRefillAt.clear();
      expect(nextContractIn(c), isNull);
    });

    test('a source gives at most what the contract still wants', () {
      post(c);
      c.state.body('kora').stock['copper_ore'] = BigNum.from(5000);
      final k = contractViews(c).single;
      expect(k.remaining, BigNum.from(1000));
      expect(k.sources.single.amount, '1K');
      expect(k.sources.single.units, BigNum.from(1000));
    });

    test('Deliver all is previewed on a copy, by body, with a warning '
        'where a body\'s own buildings use the good', () {
      c.state
          .faction(_p)
          .contracts
          .add(
            ContractState(
              id: 'c_ore',
              templateId: 'veyra_bulk',
              resourceId: 'iron_ore',
              quantity: BigNum.from(100),
              rewardCredits: BigNum.from(900),
              postedAt: c.state.time,
            ),
          );
      final brine = c.state.body('brine')..ownerId = _p;
      c.state.body('kora').stock['iron_ore'] = BigNum.from(70);
      brine.stock['iron_ore'] = BigNum.from(50);
      final before = c.state.copy();
      final preview = contractDeliverAllPreview(c, 'c_ore');
      expect(preview, isA<ContractPreviewReady>());
      final ready = preview as ContractPreviewReady;
      expect(ready.gives.map((g) => (g.name, g.value)), [
        ('Kora', '70'),
        ('Brine', '30'),
      ]);
      expect(ready.total, '100 Iron Ore');
      // Kora's Smelter uses Iron Ore; Brine has no buildings.
      expect(ready.warnings, hasLength(1));
      expect(ready.warnings.single, startsWith("Kora's own buildings use"));
      // Nothing changed for real.
      expect(c.state.body('kora').stock['iron_ore'], BigNum.from(70));
      expect(
        jsonEncode(c.state.toJson()),
        jsonEncode(before.toJson()),
        reason: 'a copy only',
      );
    });

    test('Deliver all with nothing to give says why', () {
      post(c);
      final preview = contractDeliverAllPreview(c, 'c_one');
      expect(preview, isA<ContractPreviewFailed>());
      expect((preview as ContractPreviewFailed).message, isNotEmpty);
    });
  });

  group('surveyViews', () {
    test('a signal in Veyra: its cost, time, and what it needs', () {
      final v = surveyViews(c).single;
      expect(v.systemId, 'veyra');
      expect(v.systemName, 'Veyra');
      expect(v.signals, 2);
      expect(v.cost, '20K credits and 3 Survey Drone');
      expect(v.price, BigNum.from(20000));
      expect(v.time, '3h');
      // A new game has 250 credits and no drones.
      expect(v.blockedReason, startsWith('needs 20K credits'));
      c.state.faction(_p).credits = BigNum.from(1e6);
      expect(
        surveyViews(c).single.blockedReason,
        'needs 3 Survey Drone on one of your bodies in Veyra',
      );
      c.state.body('kora').stock['survey_drone'] = BigNum.from(3);
      final ready = surveyViews(c).single;
      expect(ready.blockedReason, isNull);
      expect(ready.sourceBodyId, 'kora');
      expect(ready.sourceName, 'Kora');
    });

    test('no row once every signal is surveyed or under survey', () {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('kora').stock['survey_drone'] = BigNum.from(6);
      c.run(const SurveyCommand(_p, null, 'kora'));
      expect(surveyViews(c).single.signals, 1);
      c.run(const SurveyCommand(_p, null, 'kora'));
      expect(surveyViews(c), isEmpty);
    });
  });

  group('megaproject cards', () {
    test('a line owes its remainder and names its holders, fullest first', () {
      c.state.body('brine').ownerId = _p;
      c.state.body('brine').stock['hull_plate'] = BigNum.from(2000);
      c.state.body('kora').stock['hull_plate'] = BigNum.from(40);
      final station = _mp(c, 'orbital_station');
      final hull = station.lines.firstWhere((l) => l.id == 'hull_plate');
      expect(hull.owed, BigNum.from(1500));
      expect(hull.holders.map((h) => (h.bodyName, h.amount)), [
        ('Brine', '1.5K'),
        ('Kora', '40'),
      ]);
      final credits = station.lines.firstWhere((l) => l.id == creditsKey);
      expect(credits.holders, isEmpty);
      expect(station.deliverAll, '1.5K Hull Plate');
    });

    test('nothing to deliver from any body: no Deliver all', () {
      expect(_mp(c, 'orbital_station').deliverAll, isNull);
    });

    test('unfunded by the player\'s choice', () {
      expect(_mp(c, 'orbital_station').unfunded, isFalse);
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      expect(_mp(c, 'orbital_station').unfunded, isTrue);
    });

    test('the feed line says whether goods go in now, and why', () {
      expect(
        _mp(c, 'orbital_station').feed,
        'Goods go in only when you deliver them',
      );
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      expect(_mp(c, 'orbital_station').feed, startsWith('Goods go in from'));
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
          credits: true,
        ),
      );
      expect(
        _mp(c, 'orbital_station').feed,
        'Goods wait until the stage is near ready: its credits due within '
        '12h of what auto-pay gives it',
      );
      // The credits held pay for the stage: near ready from the command on.
      c.state.faction(_p).credits = BigNum.parse('1e9');
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
        ),
      );
      final v = _mp(c, 'orbital_station');
      expect(v.auto.goodsFedNow, isTrue);
      expect(
        v.feed,
        'Goods are going in: feeding started because the credits held, '
        'the reserve included, paid for the stage, and it keeps going until '
        'the stage is paid for',
      );
      expect(
        _mp(c, 'mass_driver').feed,
        'Goods go in only when you deliver them',
      );
    });

    test('a contract holding goods it is fed is named, for a Go', () {
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      c.state
          .faction(_p)
          .contracts
          .add(
            ContractState(
              id: 'c_hull',
              templateId: 'veyra_bulk',
              resourceId: 'hull_plate',
              quantity: BigNum.from(100),
              rewardCredits: BigNum.from(900),
              postedAt: c.state.time,
            ),
          );
      c.state.body('kora').stock['hull_plate'] = BigNum.from(60);
      c.tickSeconds(1);
      final block = _mp(c, 'orbital_station').blocks.single;
      expect(block.contractId, 'c_hull');
      expect(
        block.text,
        "Veyra Exchange's contract holds 60 Hull Plate this needs",
      );
    });
  });
}
