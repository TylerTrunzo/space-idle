import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/storage_routes_view.dart';
import 'package:space_idle/view/view_models.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

ResourceRowView _row(GameController c, String body, String id) =>
    bodyView(c, body)!.storage.firstWhere((r) => r.id == id);

AutoSellRule _rule(GameController c, String body, String id) => c.state
    .faction(_p)
    .autoSell
    .singleWhere((r) => r.bodyId == body && r.resourceId == id);

void main() {
  late GameController c;
  setUp(() => c = _controller());

  group('auto-sell on a storage row', () {
    test('no rule: no keep and nothing held', () {
      final iron = _row(c, 'kora', 'iron_ore');
      expect(iron.autoSell, isFalse);
      expect(iron.keepAtLeast, isNull);
      expect(iron.held, isNull);
    });

    test('a rule shows what it keeps, and the parts of it', () {
      // The smelter draws iron ore, so the body's own use is held too.
      c.run(SetAutoSellCommand(_p, 'kora', 'iron_ore', BigNum.from(100)));
      c.tickSeconds(1);
      final k = autoSellKeep(
        c.state,
        content,
        _rule(c, 'kora', 'iron_ore'),
        autoSellStepSeconds,
      );
      final iron = _row(c, 'kora', 'iron_ore');
      expect(iron.keepAtLeast, BigNum.from(100));
      expect(iron.held, startsWith('Auto-sell keeps ${formatNumber(k.keeps)}'));
      expect(iron.held, contains('100 you set'));
      expect(
        iron.held,
        contains('${formatNumber(k.localUse)} for its buildings'),
      );
      expect(iron.held, isNot(contains('contracts')));
    });

    test('a contract hold is named, so "why is this not selling" shows', () {
      final kora = c.state.body('kora');
      kora.stock['steel'] = BigNum.from(50);
      c.run(const SetAutoSellCommand(_p, 'kora', 'steel', BigNum.zero()));
      c.state
          .faction(_p)
          .contracts
          .add(
            ContractState(
              id: 'k1',
              templateId: content.contractTemplates.keys.first,
              resourceId: 'steel',
              quantity: BigNum.from(80),
              rewardCredits: BigNum.from(1000),
              postedAt: 0,
            ),
          );
      c.tickSeconds(1);
      final k = autoSellKeep(
        c.state,
        content,
        _rule(c, 'kora', 'steel'),
        autoSellStepSeconds,
      );
      expect(k.contractHold > const BigNum.zero(), isTrue);
      final steel = _row(c, 'kora', 'steel');
      expect(
        steel.held,
        contains('${formatNumber(k.contractHold)} for contracts'),
      );
      expect(steel.held, contains('nothing above that to sell'));
    });
  });

  group('sellOptions', () {
    test('25%, 50% and All, each with what it would earn; a dry run', () {
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      final before = SaveCodec.encode(c.state);
      final options = sellOptions(c, 'kora', 'steel');
      expect(SaveCodec.encode(c.state), before);
      expect(options.map((o) => o.label), ['25%', '50%', 'All']);
      expect(options.map((o) => o.amount), [
        BigNum.from(100),
        BigNum.from(200),
        BigNum.from(400),
      ]);
      // The revenue is what the sell command then pays.
      final r = c.run(SellCommand(_p, 'kora', 'steel', BigNum.from(400)));
      final sold = (r as CommandOk).outcome! as Sold;
      expect(options.last.revenue, formatNumber(sold.revenue));
    });

    test('a small stock leaves out the parts that round to nothing', () {
      c.state.body('kora').stock['steel'] = BigNum.from(1);
      expect(sellOptions(c, 'kora', 'steel').map((o) => o.label), ['All']);
    });

    test('an empty store offers nothing', () {
      expect(sellOptions(c, 'kora', 'steel'), isEmpty);
    });
  });

  group('routes', () {
    String route({BigNum? stop, int ships = 1, double rate = 0.5}) {
      c.state.body('brine').ownerId = _p;
      final r = c.run(
        CreateRouteCommand(
          _p,
          'kora',
          'brine',
          'iron_ore',
          BigNum.from(rate),
          ships,
          stopAtDestination: stop,
        ),
      );
      expect(r, isA<CommandOk>(), reason: c.lastError);
      return ((r as CommandOk).outcome! as RouteCreated).routeId;
    }

    test('a route shows what it can carry and what holds it', () {
      final id = route(rate: 1000);
      c.tickSeconds(1);
      final t = routeThroughput(c.state, content, id);
      final v = bodyView(c, 'kora')!.routesOut.single;
      expect(v.throughput, '${formatAmount(BigNum.from(t.perSec))}/s');
      expect(v.limit, routeLimitText(t.binding));
      expect(v.limit, isNotEmpty);
    });

    test('a route held at its stop level says it has stopped', () {
      c.state.body('brine').stock['iron_ore'] = BigNum.from(500);
      final id = route(stop: BigNum.from(10));
      c.tickSeconds(1);
      final r = c.state.routes.singleWhere((r) => r.id == id);
      expect(routePaused(c.state, content, r), isTrue);
      final v = bodyView(c, 'brine')!.routesIn.single;
      expect(v.status, RouteStatus.stopped);
      expect(v.statusText, startsWith('Stopped'));
      expect(v.stop, '10');
      expect(v.stopValue, BigNum.from(10));
    });

    test('a route with nothing to send waits for stock', () {
      route();
      c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
      c.run(const AssignCrewCommand(_p, 'b1', 0)); // the mine stops
      c.tickSeconds(1);
      final v = bodyView(c, 'kora')!.routesOut.single;
      expect(v.status, RouteStatus.waiting);
      expect(v.statusText, contains('Iron Ore'));
      expect(v.stop, isNull);
    });

    group('routeStatusOf says what a route waits on', () {
      ({RouteStatus status, String text}) of(
        RouteLimit binding, {
        double perSec = 0,
        bool paused = false,
      }) => routeStatusOf(
        paused: paused,
        throughput: (perSec: perSec, binding: binding),
        fromName: 'Kora',
        toName: 'Brine',
        resourceName: 'Iron Ore',
      );

      test('paused: stopped at the stop level', () {
        final s = of(RouteLimit.stopLevel, paused: true);
        expect(s.status, RouteStatus.stopped);
        expect(s.text, 'Stopped: Brine holds its stop level');
      });

      test('nothing at the source', () {
        final s = of(RouteLimit.sourceStock);
        expect(s.status, RouteStatus.waiting);
        expect(s.text, 'Waiting for Iron Ore at Kora');
      });

      test('no room at the destination', () {
        final s = of(RouteLimit.destinationRoom);
        expect(s.status, RouteStatus.waiting);
        expect(s.text, 'Waiting for room at Brine');
      });

      test("other routes' cargo fills the stop level, not paused yet", () {
        final s = of(RouteLimit.stopLevel);
        expect(s.status, RouteStatus.waiting);
        expect(s.text, "Waiting: cargo on its way fills Brine's stop level");
      });

      test('carrying anything is moving', () {
        expect(of(RouteLimit.rate, perSec: 0.5).status, RouteStatus.moving);
        expect(of(RouteLimit.rate, perSec: 0.5).text, 'Moving');
      });
    });

    test('a route to a body no longer owned waits for room there', () {
      route();
      c.state.body('brine').ownerId = null;
      c.tickSeconds(1);
      final v = bodyView(c, 'kora')!.routesOut.single;
      expect(v.status, RouteStatus.waiting);
      expect(v.statusText, 'Waiting for room at Brine');
    });

    test('a route carries its rate and the spare ships at its source', () {
      route(rate: 2.5);
      final v = bodyView(c, 'kora')!.routesOut.single;
      expect(v.rateValue, BigNum.from(2.5));
      final left = c.state.body('kora').stock[content.rules.cargoShipResource]!;
      expect(v.spareShips, left.toDouble().floor());
    });

    test('editableNumber writes a figure a field can read back', () {
      expect(editableNumber(BigNum.from(1500)), '1500');
      expect(editableNumber(BigNum.from(0.5)), '0.5');
      expect(double.parse(editableNumber(BigNum.parse('1e40'))), 1e40);
    });

    test('a running route is moving', () {
      route();
      c.tickSeconds(1);
      expect(bodyView(c, 'kora')!.routesOut.single.status, RouteStatus.moving);
    });
  });

  group('routeForm', () {
    test('owned bodies in the system, stocked resources and ships here', () {
      c.state.body('brine').ownerId = _p;
      final f = routeForm(c, 'kora');
      expect(f.destinations.map((d) => d.id), ['brine']);
      expect(f.resources.map((r) => r.id), contains('iron_ore'));
      expect(f.resources.map((r) => r.id), isNot(contains('steel')));
      expect(
        f.ships,
        c.state
            .body('kora')
            .stock[content.rules.cargoShipResource]!
            .floor()
            .toDouble()
            .round(),
      );
    });

    test('with no other body there is nowhere to go', () {
      expect(routeForm(c, 'kora').destinations, isEmpty);
    });
  });
}
