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

/// The keys of the selected keep chips.
List<String> _selected(WidgetTester tester) => [
  for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
    if (chip.selected) (chip.key! as ValueKey<String>).value,
];

/// The spans under [of] whose text contains [figure] and that are set in
/// the monospace face.
List<TextSpan> _monoSpans(WidgetTester tester, Finder of, String figure) => [
  for (final t in tester.widgetList<RichText>(
    find.descendant(of: of, matching: find.byType(RichText)),
  ))
    ..._spans(t.text).where(
      (s) =>
          (s.text ?? '').contains(figure) &&
          s.style?.fontFamily == monoFontFamily,
    ),
];

List<TextSpan> _spans(InlineSpan root) {
  final out = <TextSpan>[];
  root.visitChildren((s) {
    if (s is TextSpan) out.add(s);
    return true;
  });
  return out;
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
      expect(_selected(tester), ['keep-steel-100']);

      await tester.tap(_key('keep-steel-1000'));
      await tester.pump();
      expect(_rule(c, 'kora', 'steel')?.keepAtLeast, BigNum.from(1000));
      expect(_selected(tester), ['keep-steel-1000']);

      await tester.tap(_key('autosell-steel'));
      await tester.pump();
      expect(_rule(c, 'kora', 'steel'), isNull);
    });

    testWidgets('the switch is named for its resource; its words toggle it', (
      tester,
    ) async {
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      expect(find.bySemanticsLabel(RegExp('^Auto-sell Steel')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: _key('storage-steel'),
          matching: find.text('Auto-sell'),
        ),
      );
      await tester.pump();
      expect(_rule(c, 'kora', 'steel'), isNotNull);
    });

    testWidgets('an open chooser follows the stock; All sells what is there', (
      tester,
    ) async {
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('sell-steel'));
      await tester.pump();
      // More comes in while it is open.
      c.state.body('kora').stock['steel'] = BigNum.from(800);
      c.tickSeconds(0.01);
      await tester.pump();
      final all = sellOptions(c, 'kora', 'steel').last;
      expect(
        find.descendant(
          of: _key('sell-steel-all'),
          matching: find.textContaining(
            '${all.amountText} for ${all.revenue} credits',
          ),
        ),
        findsOneWidget,
      );
      // More again, with no rebuild: All still sells all of it.
      c.state.body('kora').stock['steel'] = BigNum.from(900);
      await tester.tap(_key('sell-steel-all'));
      await tester.pump();
      expect(_stock(c, 'kora', 'steel'), const BigNum.zero());
    });

    testWidgets('prices and revenues are in the monospace face', (
      tester,
    ) async {
      c.state.body('kora').stock['steel'] = BigNum.from(400);
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      final row = bodyView(
        c,
        'kora',
      )!.storage.firstWhere((r) => r.id == 'steel');
      expect(_monoSpans(tester, _key('storage-steel'), row.price), isNotEmpty);
      await tester.tap(_key('sell-steel'));
      await tester.pump();
      final all = sellOptions(c, 'kora', 'steel').last;
      expect(
        _monoSpans(tester, _key('sell-steel-all'), all.revenue),
        isNotEmpty,
      );
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

    testWidgets('a route\'s rate and ships are changed on its card', (
      tester,
    ) async {
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      final r = c.state.routes.single;
      final ships = _stock(c, 'kora', _ship);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('route-edit-${r.id}'));
      await tester.pump();
      // The fields start at the route's own figures.
      expect(
        tester.widget<TextField>(_key('rate-field-${r.id}')).controller!.text,
        '1',
      );
      await tester.enterText(_key('rate-field-${r.id}'), '3');
      await tester.tap(_key('ships-${r.id}-add'));
      await tester.pump();
      await tester.tap(_key('route-save-${r.id}'));
      await tester.pump();
      final now = c.state.routes.single;
      expect(now.ratePerSecond, BigNum.from(3));
      expect(now.cargoShips, 2);
      expect(_stock(c, 'kora', _ship), ships - BigNum.from(1));
      expect(_key('route-save-${r.id}'), findsNothing, reason: 'closed');
      expect(find.textContaining('3/s set · 2 ships'), findsOneWidget);
    });

    testWidgets('the stop level is set and taken off on the card', (
      tester,
    ) async {
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      final r = c.state.routes.single;
      await _pump(tester, c, 'kora');
      expect(find.textContaining('Never stops'), findsOneWidget);
      await tester.tap(_key('route-edit-${r.id}'));
      await tester.pump();
      await tester.enterText(_key('stop-field-${r.id}'), '750');
      await tester.tap(_key('route-save-${r.id}'));
      await tester.pump();
      expect(c.state.routes.single.stopAtDestination, BigNum.from(750));
      expect(find.textContaining('Stops when Brine holds 750'), findsOneWidget);

      // It reopens at its level, and an empty field takes it off.
      await tester.tap(_key('route-edit-${r.id}'));
      await tester.pump();
      expect(
        tester.widget<TextField>(_key('stop-field-${r.id}')).controller!.text,
        '750',
      );
      await tester.enterText(_key('stop-field-${r.id}'), '');
      await tester.tap(_key('route-save-${r.id}'));
      await tester.pump();
      expect(c.state.routes.single.stopAtDestination, isNull);
    });

    testWidgets('an edit the core refuses says why on the card', (
      tester,
    ) async {
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      final r = c.state.routes.single;
      await _pump(tester, c, 'kora');
      await tester.tap(_key('route-edit-${r.id}'));
      await tester.pump();
      await tester.enterText(_key('rate-field-${r.id}'), '0');
      await tester.tap(_key('route-save-${r.id}'));
      await tester.pump();
      expect(c.state.routes.single.ratePerSecond, BigNum.from(1));
      expect(
        find.descendant(
          of: _key('route-${r.id}'),
          matching: find.text(c.lastError!),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with no cargo ships here, the forms say so and wait', (
      tester,
    ) async {
      c.state.body('kora').stock[_ship] = const BigNum.zero();
      await _pump(tester, c, 'kora');
      await tester.tap(_key('new-route'));
      await tester.pump();
      expect(find.text('No cargo ships here'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('route-create')).onPressed,
        isNull,
      );
      await tester.tap(_key('move-ships'));
      await tester.pump();
      expect(find.text('No cargo ships here'), findsOneWidget);
      expect(tester.widget<FilledButton>(_key('move-send')).onPressed, isNull);
    });

    testWidgets('route figures are in the monospace face', (tester) async {
      c.run(
        CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
      );
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      final v = bodyView(c, 'kora')!.routesOut.single;
      expect(
        _monoSpans(tester, _key('route-${v.id}'), v.throughput),
        isNotEmpty,
      );
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
    testWidgets('1e40 of a stock and its chooser at 360x640 and 2x text', (
      tester,
    ) async {
      c.state.body('kora').stock['steel'] = BigNum.parse('1e40');
      c.tickSeconds(1);
      await _pump(tester, c, 'kora', size: const Size(360, 640), textScale: 2);
      final list = find
          .descendant(
            of: find.byType(PlanetPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        _key('sell-steel'),
        200,
        scrollable: list,
      );
      await tester.ensureVisible(_key('sell-steel'));
      await tester.pump();
      await tester.tap(_key('sell-steel'));
      await tester.pump();
      await tester.ensureVisible(_key('sell-steel-all'));
      await tester.pump();
      expect(
        find.descendant(
          of: _key('sell-steel-all'),
          matching: find.textContaining('1e40'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

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
      await show('route-edit-${r.id}');
      await tester.tap(_key('route-edit-${r.id}'));
      await tester.pump();
      await show('route-save-${r.id}');
      await tester.drag(find.byType(PlanetPanel), const Offset(0, -4000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
