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
  });
}
