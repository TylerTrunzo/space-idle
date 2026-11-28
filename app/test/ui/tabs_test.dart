import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/building_row.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/ui/tabs/crew_tab.dart';
import 'package:space_idle/ui/tabs/production_tab.dart';
import 'package:space_idle/ui/tabs/trade_tab.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/tabs_view.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  late GameController c;
  late List<VoidCallback> fills;
  String? shown;

  setUp(() {
    fills = [];
    shown = null;
    c = GameController(
      content: content,
      store: MemorySaveStore(),
      clock: FakeClock(DateTime.utc(2026, 11, 27)),
      newGameSeed: 1,
      scheduleFill: fills.add,
    );
  });

  /// Runs every fill asked for.
  void fillAll() {
    while (fills.isNotEmpty) {
      fills.removeAt(0)();
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget tab, {
    Size size = const Size(800, 3000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ControllerScope(
          controller: c,
          child: ShellScope(
            selectedId: null,
            selectBody: (_) {},
            clearSelection: () {},
            showOnMap: (id) => shown = id,
            child: Scaffold(body: tab),
          ),
        ),
      ),
    );
  }

  /// A habitat on Kora with five minutes of life support, housing crew
  /// the faction needs: base crew 2, three assigned.
  void habitatRunningDry() {
    final kora = c.state.body('kora');
    c.state.faction(_p).credits = BigNum.from(1e6);
    kora.stock['habitat_module'] = BigNum.from(1);
    c.run(const BuildCommand(_p, 'kora', 'habitat'));
    for (final id in ['food', 'water', 'oxygen']) {
      kora.stock[id] = BigNum.from(30);
    }
    c.tickSeconds(1);
    c.state.faction(_p).baseCrew = 2;
    c.tickSeconds(1);
  }

  /// The iron mine idle and the ore gone: the smelter stops.
  void starve() {
    c.run(const AssignCrewCommand(_p, 'b1', 0));
    c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
    c.tickSeconds(1);
  }

  group('Production', () {
    testWidgets('every building as the panel\'s row, under its body', (
      tester,
    ) async {
      await pump(tester, const ProductionTab());
      expect(_key('production-body-kora'), findsOneWidget);
      for (final b in c.state.body('kora').buildings) {
        expect(
          find.descendant(
            of: find.byType(BuildingRow),
            matching: _key('crew-add-${b.id}'),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('Problems shows only rows not ok, the worst first', (
      tester,
    ) async {
      starve();
      final problems = productionView(c).problems;
      expect(problems, isNotEmpty);
      await pump(tester, const ProductionTab());
      await tester.tap(_key('filter-problems'));
      await tester.pump();
      final shownRows = tester
          .widgetList<BuildingRow>(find.byType(BuildingRow))
          .map((r) => r.view.id)
          .toList();
      expect(shownRows, problems.map((p) => p.row.id));
      expect(shownRows, isNot(contains('b2')), reason: 'the copper mine runs');
    });

    testWidgets('a body filter shows only its buildings', (tester) async {
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const BuildCommand(_p, 'brine', 'smelter'));
      final brine = c.state.body('brine').buildings.single.id;
      await pump(tester, const ProductionTab());
      await tester.tap(_key('filter-body-brine'));
      await tester.pump();
      final rows = tester
          .widgetList<BuildingRow>(find.byType(BuildingRow))
          .map((r) => r.view.id);
      expect(rows, [brine]);
    });

    testWidgets('tapping a body header shows it on the map', (tester) async {
      await pump(tester, const ProductionTab());
      await tester.tap(_key('production-body-kora'));
      await tester.pump();
      expect(shown, 'kora');
    });

    testWidgets('the first frame after a command works out no previews', (
      tester,
    ) async {
      await pump(tester, const ProductionTab());
      fillAll();
      final before = c.previewsWorkedOut;
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      await tester.pump();
      expect(c.previewsWorkedOut, before, reason: 'nothing in the build');
      expect(c.previewFor('b3', UpgradeTrack.speed).ready, isFalse);
      expect(fills, isNotEmpty, reason: 'asked for, to fill after the frame');
      fillAll();
      expect(c.previewsWorkedOut, greaterThan(before), reason: 'in the fill');
      await tester.pump();
      expect(
        find.descendant(
          of: _key('payback-b3-speed'),
          matching: find.textContaining('Speed:'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a body header is a button named for its body', (tester) async {
      await pump(tester, const ProductionTab());
      final node = tester.getSemantics(
        find.bySemanticsLabel('Kora, show on the map'),
      );
      expect(node.flagsCollection.isButton, isTrue);
    });
  });

  group('Crew', () {
    testWidgets('+ changes the same building as the panel would', (
      tester,
    ) async {
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      await pump(tester, const CrewTab());
      final add = _key('crew-add-b1');
      expect(
        find.ancestor(of: add, matching: find.byType(CrewLine)),
        findsOneWidget,
      );
      await tester.tap(add);
      await tester.pump();
      expect(
        c.state.body('kora').buildings.firstWhere((b) => b.id == 'b1').crew,
        1,
      );
    });

    testWidgets('shows free, assigned and supported crew', (tester) async {
      await pump(tester, const CrewTab());
      final t = crewTotals(c.state, content, _p);
      expect(
        find.textContaining(
          '${t.free} free · ${t.assigned} assigned · '
          '${t.supported} supported',
        ),
        findsOneWidget,
      );
    });

    testWidgets('housing and demand show at once, and stay put on − and +', (
      tester,
    ) async {
      await pump(tester, const CrewTab());
      final f = crewForecast(c.state, content, _p);
      final line = find.textContaining(
        'Housing ${f.housing} · demand ${f.demand}',
      );
      expect(line, findsOneWidget, reason: 'no wait for a fill');
      final row = _key('crewed-b2');
      final top = tester.getTopLeft(row).dy;
      await tester.tap(_key('crew-remove-b2'));
      await tester.pump();
      expect(find.textContaining('Housing '), findsOneWidget);
      expect(tester.getTopLeft(row).dy, top, reason: 'the row did not move');
    });

    testWidgets('an amber warning before a shortage, with a Go', (
      tester,
    ) async {
      habitatRunningDry();
      await pump(tester, const CrewTab());
      final card = _key('crew-warning');
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Crew runs short in'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('build a Habitat on Kora'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.warning_amber_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Go to Kora to build a Habitat'),
        findsOneWidget,
      );
      await tester.tap(_key('crew-warning-go'));
      await tester.pump();
      expect(shown, 'kora');
      final habitat = c.state.body('kora').buildings.last.id;
      expect(_key('habitat-$habitat'), findsOneWidget);
    });

    testWidgets('the countdown follows the clock, and never runs past it', (
      tester,
    ) async {
      habitatRunningDry();
      await pump(tester, const CrewTab());
      String warning() => tester
          .widget<Text>(
            find.descendant(
              of: _key('crew-warning'),
              matching: find.textContaining('Crew '),
            ),
          )
          .data!;
      final first = warning();
      final t0 = crewForecast(c.state, content, _p).secondsUntilShortage!;
      c.tickSeconds(60);
      await tester.pump();
      final t1 = crewForecast(c.state, content, _p).secondsUntilShortage!;
      expect(t1, lessThan(t0));
      expect(warning(), isNot(first));
      expect(warning(), contains(formatDuration(t1)));
      // Past the shortage it says so; no countdown is left.
      for (var i = 0; i < 400; i++) {
        c.tickSeconds(1);
      }
      await tester.pump();
      expect(warning(), startsWith('Crew is short now'));
    });
  });

  group('Trade', () {
    testWidgets('a lower Steel price after selling Steel', (tester) async {
      c.state.body('kora').stock['steel'] = BigNum.from(5000);
      await pump(tester, const TradeTab());
      final row = _key('market-steel');
      final before = salePrice(c.state, content, _p, 'steel');
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('${formatAmount(before)} credits'),
        ),
        findsOneWidget,
      );
      c.run(SellCommand(_p, 'kora', 'steel', BigNum.from(5000)));
      await tester.pump();
      final after = salePrice(c.state, content, _p, 'steel');
      expect(after < before, isTrue);
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('${formatAmount(after)} credits'),
        ),
        findsOneWidget,
      );
      final sat = tradeView(c).market.firstWhere((m) => m.id == 'steel');
      expect(
        find.descendant(of: row, matching: find.text(sat.saturationText)),
        findsOneWidget,
      );
    });

    testWidgets('worth an hour is coloured by its sign, not its text', (
      tester,
    ) async {
      c.tickSeconds(1);
      await pump(tester, const TradeTab());
      final steel = tradeView(c).market.firstWhere((m) => m.id == 'steel');
      expect(steel.worthSign, 1);
      final text = tester.widget<Text>(
        find.descendant(
          of: _key('market-steel'),
          matching: find.text(steel.worthPerHour!),
        ),
      );
      expect(text.style?.color, Palette.green);
    });

    testWidgets('an auto-sell rule is listed and removed', (tester) async {
      c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
      await pump(tester, const TradeTab());
      expect(_key('rule-kora-steel'), findsOneWidget);
      await tester.tap(_key('rule-remove-kora-steel'));
      await tester.pump();
      expect(c.state.faction(_p).autoSell, isEmpty);
      expect(_key('rule-kora-steel'), findsNothing);
    });

    testWidgets('every route, with its status', (tester) async {
      c.state.body('brine').ownerId = _p;
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      c.tickSeconds(1);
      await pump(tester, const TradeTab());
      final r = tradeView(c).routes.single;
      expect(
        find.descendant(
          of: _key('route-${r.id}'),
          matching: find.text(r.statusText),
        ),
        findsOneWidget,
      );
    });
  });

  group('fits at 360x640 and 2x text (Review Focus 4)', () {
    void busy() {
      starve();
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e9);
      c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
      c.run(
        CreateRouteCommand(
          _p,
          'kora',
          'brine',
          'copper_ore',
          BigNum.from(1),
          1,
        ),
      );
      c.state.body('kora').stock['habitat_module'] = BigNum.from(1);
      c.run(const BuildCommand(_p, 'kora', 'habitat'));
      c.tickSeconds(1);
    }

    for (final (name, tab) in [
      ('Production', const ProductionTab()),
      ('Crew', const CrewTab()),
      ('Trade', const TradeTab()),
    ]) {
      testWidgets(name, (tester) async {
        busy();
        await pump(tester, tab, size: const Size(360, 640), textScale: 2);
        fillAll();
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 30; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -500),
          );
          await tester.pump();
          fillAll();
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
