import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/planet_panel.dart';
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

/// The panel for [bodyId]; tall by default, so every row is on screen.
Future<void> _pump(
  WidgetTester tester,
  GameController c,
  String bodyId, {
  Size? size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size ?? const Size(800, 3200);
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
        child: Scaffold(
          body: PlanetPanel(key: ValueKey(bodyId), bodyId: bodyId),
        ),
      ),
    ),
  );
}

Finder _key(String k) => find.byKey(ValueKey(k));

BigNum _stock(GameController c, String body, String id) =>
    c.state.body(body).stock[id] ?? const BigNum.zero();

AutoSellRule? _rule(GameController c, String body, String id) => c.state
    .faction(_p)
    .autoSell
    .where((r) => r.bodyId == body && r.resourceId == id)
    .firstOrNull;

String get _ship => content.rules.cargoShipResource;

/// Opens the New route form and fills in its rate.
Future<void> _newRoute(WidgetTester tester, String rate) async {
  await tester.tap(_key('new-route'));
  await tester.pump();
  await tester.enterText(_key('route-rate'), rate);
  await tester.pump();
}

void main() {
  late GameController c;
  setUp(() => c = _controller());

  group('storage', () {
    testWidgets('a row shows stock over cap, net, and the sale price', (
      tester,
    ) async {
      await _pump(tester, c, 'kora');
      final row = bodyView(
        c,
        'kora',
      )!.storage.firstWhere((r) => r.id == 'iron_ore');
      final card = _key('storage-iron_ore');
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('${row.amount} / ${row.cap}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining(row.price)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byType(LinearProgressIndicator),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Sell shows what each part earns; All sells it all', (
      tester,
    ) async {
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      c.tickSeconds(1);
      final before = c.state.faction(_p).credits;
      await _pump(tester, c, 'kora');
      await tester.tap(_key('sell-steel'));
      await tester.pump();
      final all = sellOptions(c, 'kora', 'steel').last;
      expect(
        find.descendant(
          of: _key('sell-steel-all'),
          matching: find.textContaining('${all.revenue} credits'),
        ),
        findsOneWidget,
      );
      expect(c.state.faction(_p).credits, before, reason: 'not yet');

      await tester.tap(_key('sell-steel-all'));
      await tester.pump();
      expect(_stock(c, 'kora', 'steel'), const BigNum.zero());
      expect(c.state.faction(_p).credits > before, isTrue);
      expect(find.textContaining('Sold 400 Steel'), findsOneWidget);
    });

    testWidgets('auto-sell: on keeps 100, the keep changes, off removes it', (
      tester,
    ) async {
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('autosell-steel'));
      await tester.pump();
      expect(_rule(c, 'kora', 'steel')?.keepAtLeast, BigNum.from(100));

      await tester.tap(_key('keep-steel-1000'));
      await tester.pump();
      expect(_rule(c, 'kora', 'steel')?.keepAtLeast, BigNum.from(1000));

      await tester.tap(_key('autosell-steel'));
      await tester.pump();
      expect(_rule(c, 'kora', 'steel'), isNull);
    });

    testWidgets('a row says what auto-sell holds back', (tester) async {
      c.run(SetAutoSellCommand(_p, 'kora', 'iron_ore', BigNum.from(100)));
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      final held = bodyView(
        c,
        'kora',
      )!.storage.firstWhere((r) => r.id == 'iron_ore').held!;
      expect(
        find.descendant(
          of: _key('storage-iron_ore'),
          matching: find.text(held),
        ),
        findsOneWidget,
      );
    });
  });

  group('routes', () {
    setUp(() => c.state.body('brine').ownerId = _p);

    testWidgets('a new route shows on both bodies; removing it returns '
        'its ship', (tester) async {
      final ships = _stock(c, 'kora', _ship);
      await _pump(tester, c, 'kora');
      await _newRoute(tester, '0.5');
      await tester.tap(_key('route-create'));
      await tester.pump();
      final r = c.state.routes.single;
      expect(r.fromBodyId, 'kora');
      expect(r.toBodyId, 'brine');
      expect(r.cargoShips, 1);
      expect(_stock(c, 'kora', _ship), ships - BigNum.from(1));
      expect(_key('route-${r.id}'), findsOneWidget);
      expect(_key('route-create'), findsNothing, reason: 'the form closed');

      await _pump(tester, c, 'brine');
      expect(_key('route-${r.id}'), findsOneWidget, reason: 'routes in');

      await tester.tap(_key('remove-route-${r.id}'));
      await tester.pump();
      expect(c.state.routes, isEmpty);
      expect(_stock(c, 'kora', _ship), ships);
      expect(_key('route-${r.id}'), findsNothing);
    });

    testWidgets('a route the core refuses says why in the form', (
      tester,
    ) async {
      await _pump(tester, c, 'kora');
      await _newRoute(tester, '0');
      await tester.tap(_key('route-create'));
      await tester.pump();
      expect(c.state.routes, isEmpty);
      final why = c.lastError!;
      expect(
        find.descendant(of: _key('route-form'), matching: find.text(why)),
        findsOneWidget,
      );
    });

    testWidgets('a rate that is not a number is caught before the core', (
      tester,
    ) async {
      await _pump(tester, c, 'kora');
      await _newRoute(tester, 'fast');
      await tester.tap(_key('route-create'));
      await tester.pump();
      expect(c.state.routes, isEmpty);
      expect(find.textContaining('a number of units a second'), findsOneWidget);
    });

    testWidgets('a route shows its throughput, its limit and its status', (
      tester,
    ) async {
      c.run(
        CreateRouteCommand(
          _p,
          'kora',
          'brine',
          'iron_ore',
          BigNum.from(1000),
          1,
        ),
      );
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      final v = bodyView(c, 'kora')!.routesOut.single;
      final card = _key('route-${v.id}');
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(
            'Carries up to ${v.throughput}, held by ${v.limit}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text(v.statusText)),
        findsOneWidget,
      );
    });

    testWidgets('the stop level is set and taken off', (tester) async {
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      final r = c.state.routes.single;
      await _pump(tester, c, 'kora');
      expect(find.textContaining('Never stops'), findsOneWidget);
      await tester.tap(_key('stop-edit-${r.id}'));
      await tester.pump();
      await tester.enterText(_key('stop-field-${r.id}'), '50');
      await tester.tap(_key('stop-set-${r.id}'));
      await tester.pump();
      expect(c.state.routes.single.stopAtDestination, BigNum.from(50));
      expect(find.textContaining('Stops when Brine holds 50'), findsOneWidget);

      await tester.tap(_key('stop-edit-${r.id}'));
      await tester.pump();
      await tester.tap(_key('stop-clear-${r.id}'));
      await tester.pump();
      expect(c.state.routes.single.stopAtDestination, isNull);
    });

    testWidgets('Move ships sends cargo ships to another body', (tester) async {
      final ships = _stock(c, 'kora', _ship);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('move-ships'));
      await tester.pump();
      await tester.tap(_key('move-send'));
      await tester.pump();
      expect(_stock(c, 'kora', _ship), ships - BigNum.from(1));
      expect(c.state.shipments, hasLength(1));
      expect(find.textContaining('Sent 1 Cargo Ship'), findsOneWidget);
    });

    testWidgets('with no other body here, the forms say why not', (
      tester,
    ) async {
      c.state.body('brine').ownerId = null;
      await _pump(tester, c, 'kora');
      expect(_key('new-route'), findsNothing);
      expect(
        find.textContaining('another body in this system'),
        findsOneWidget,
      );
    });
  });

  group('fits (Review Focus 4)', () {
    testWidgets('storage and routes at 360x640 and 2x text', (tester) async {
      c.state.body('brine').ownerId = _p;
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      c.run(
        CreateRouteCommand(
          _p,
          'kora',
          'brine',
          'iron_ore',
          BigNum.from(0.5),
          1,
          stopAtDestination: BigNum.from(500),
        ),
      );
      c.run(SetAutoSellCommand(_p, 'kora', 'iron_ore', BigNum.from(100)));
      c.tickSeconds(1);
      await _pump(tester, c, 'kora', size: const Size(360, 640), textScale: 2);
      final list = find
          .descendant(
            of: find.byType(PlanetPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> show(String k) async {
        await tester.scrollUntilVisible(_key(k), 200, scrollable: list);
        await tester.pump();
      }

      await show('sell-steel');
      await tester.tap(_key('sell-steel'));
      await tester.pump();
      await show('sell-steel-all');
      await show('new-route');
      await tester.tap(_key('new-route'));
      await tester.pump();
      await show('route-create');
      await show('move-ships');
      await tester.tap(_key('move-ships'));
      await tester.pump();
      await show('move-send');
      final r = c.state.routes.single;
      await show('stop-edit-${r.id}');
      await tester.tap(_key('stop-edit-${r.id}'));
      await tester.pump();
      await show('stop-set-${r.id}');
      await tester.drag(find.byType(PlanetPanel), const Offset(0, -4000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
