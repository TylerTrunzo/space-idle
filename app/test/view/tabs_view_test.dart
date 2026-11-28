import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' hide formatDuration;
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/tabs_view.dart';
import 'package:space_idle/view/view_models.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

void main() {
  late GameController c;
  setUp(() => c = _controller());

  /// The iron mine idle and the ore gone: the smelter stops.
  void starve() {
    c.run(const AssignCrewCommand(_p, 'b1', 0));
    c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
    c.tickSeconds(1);
  }

  group('productionView', () {
    test('every building of the player, by body, as the panel shows it', () {
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const BuildCommand(_p, 'brine', 'smelter'));
      final v = productionView(c);
      expect(v.bodies.map((b) => b.id), ['kora', 'brine']);
      expect(
        v.bodies.first.rows.map((r) => r.id),
        c.state.body('kora').buildings.map((b) => b.id),
      );
      final panel = bodyView(c, 'kora')!.buildings;
      for (final (i, r) in v.bodies.first.rows.indexed) {
        expect(r.name, panel[i].name);
        expect(r.severity, panel[i].severity);
        expect(r.problem, panel[i].problem);
      }
    });

    test('problems: not ok only, stopped first, then by credits lost', () {
      starve();
      final v = productionView(c);
      expect(v.problems, isNotEmpty);
      expect(
        v.problems.map((p) => p.row.severity),
        everyElement(isNot(Severity.ok)),
      );
      for (var i = 1; i < v.problems.length; i++) {
        final a = v.problems[i - 1];
        final b = v.problems[i];
        expect(
          a.row.severity.index,
          greaterThanOrEqualTo(b.row.severity.index),
        );
        if (a.row.severity == b.row.severity) {
          expect(a.lostPerHour >= b.lostPerHour, isTrue);
        }
      }
      final ok = v.bodies
          .expand((b) => b.rows)
          .where((r) => r.severity == Severity.ok)
          .map((r) => r.id);
      expect(v.problems.map((p) => p.row.id), isNot(contains(anyOf(ok))));
    });

    test('a new game runs free: no problems', () {
      c.tickSeconds(1);
      expect(productionView(c).problems, isEmpty);
    });
  });

  group('crewView', () {
    test('free, assigned and supported crew, and every crewed building', () {
      final v = crewView(c);
      final t = crewTotals(c.state, content, _p);
      expect(
        (v.free, v.assigned, v.supported),
        (t.free, t.assigned, t.supported),
      );
      expect(v.crewed.map((x) => x.row.id), ['b1', 'b2', 'b3']);
      expect(v.habitats, isEmpty);
    });

    test('a habitat shows what it houses now and at full rate', () {
      c.state.faction(_p).credits = BigNum.from(1e6);
      final kora = c.state.body('kora');
      kora.stock['habitat_module'] = BigNum.from(1);
      expect(
        c.run(const BuildCommand(_p, 'kora', 'habitat')),
        isA<CommandOk>(),
      );
      for (final id in ['food', 'water', 'oxygen']) {
        kora.stock[id] = BigNum.from(100);
      }
      c.tickSeconds(1);
      final h = crewView(c).habitats.single;
      expect(h.bodyId, 'kora');
      expect(h.housesAtFull, 20);
      expect(h.houses, 20);
    });

    test('where a habitat could go: a body that can take one, else room', () {
      // Nothing to build one with: the first body with a free slot.
      expect(crewView(c).habitatBodyId, 'kora');
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('brine').stock['habitat_module'] = BigNum.from(1);
      expect(crewView(c).habitatBodyId, 'brine', reason: 'it can, now');
    });

    test('the warning reads the forecast', () {
      expect(crewWarningText(null), isNull);
      CrewForecast f(double? t) => CrewForecast(
        housing: 10,
        demand: 12,
        secondsUntilShortage: t,
        creditsPerExtraCrew: const BigNum.zero(),
      );
      expect(crewWarningText(f(null)), isNull);
      expect(crewWarningText(f(0)), 'Crew is short now');
      expect(
        crewWarningText(f(7200)),
        'Crew runs short in ${formatDuration(7200)}',
      );
    });
  });

  group('tradeView', () {
    test('every resource at the price the player sells it for', () {
      c.state.faction(_p).megaprojectLevels['mass_driver'] = 3;
      final v = tradeView(c);
      expect(v.market.map((m) => m.id), content.resources.keys);
      for (final m in v.market) {
        expect(m.price, formatAmount(salePrice(c.state, content, _p, m.id)));
      }
    });

    test('selling lowers the price and the saturation shown', () {
      c.state.body('kora').stock['steel'] = BigNum.from(5000);
      final before = tradeView(c).market.firstWhere((m) => m.id == 'steel');
      expect(before.saturationText, '100% of base price');
      c.run(SellCommand(_p, 'kora', 'steel', BigNum.from(5000)));
      final after = tradeView(c).market.firstWhere((m) => m.id == 'steel');
      expect(after.saturation, lessThan(before.saturation));
      expect(
        salePrice(c.state, content, _p, 'steel').toDouble(),
        lessThan(content.resources['steel']!.basePrice.toDouble()),
      );
      expect(after.price, isNot(before.price));
      expect(after.saturationText, isNot('100% of base price'));
    });

    test('what net production is worth an hour, signed', () {
      c.tickSeconds(1);
      final steel = tradeView(c).market.firstWhere((m) => m.id == 'steel');
      expect(steel.worthPerHour, startsWith('+'));
      expect(steel.worthPerHour, endsWith('/h'));
      final water = tradeView(c).market.firstWhere((m) => m.id == 'water');
      expect(water.worthPerHour, isNull, reason: 'nothing makes or uses it');
    });

    test('auto-sell rules and routes', () {
      c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
      c.state.body('brine').ownerId = _p;
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      final v = tradeView(c);
      final rule = v.rules.single;
      expect(
        (rule.bodyName, rule.resourceName, rule.keep),
        ('Kora', 'Steel', '100'),
      );
      expect(v.routes.single.fromName, 'Kora');
      expect(v.routes.single.toName, 'Brine');
    });
  });
}
