import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/build_picker.dart';
import 'package:space_idle/ui/planet/planet_panel.dart';
import 'package:space_idle/ui/top_bar.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

/// The panel for [bodyId] under the real top bar.
Future<void> _pump(
  WidgetTester tester,
  GameController c,
  String bodyId, {
  Size? size,
  double textScale = 1,
}) async {
  // Tall by default, so every row is laid out and on screen; the 360x640
  // tests cover scrolling.
  tester.view.physicalSize = size ?? const Size(800, 2400);
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
          body: Column(
            children: [
              TopBar(onSettings: () {}),
              Expanded(child: PlanetPanel(bodyId: bodyId)),
            ],
          ),
        ),
      ),
    ),
  );
}

int _crew(GameController c, String id) =>
    c.state.body('kora').buildings.firstWhere((b) => b.id == id).crew;

int _level(GameController c, String id, UpgradeTrack t) =>
    c.state.body('kora').buildings.firstWhere((b) => b.id == id).levels[t]!;

Finder _key(String k) => find.byKey(ValueKey(k));

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

void main() {
  late GameController c;
  setUp(() => c = _controller());

  group('header', () {
    testWidgets('shows the name, type and slots', (tester) async {
      await _pump(tester, c, 'kora');
      expect(find.text('Kora'), findsOneWidget);
      expect(find.textContaining('Rocky World'), findsOneWidget);
      expect(
        find.textContaining(
          '3/${buildSlots(content, c.state.body('kora'))} slots',
        ),
        findsOneWidget,
      );
    });
  });

  group('crew', () {
    testWidgets('+ on the iron mine raises its crew when crew is free', (
      tester,
    ) async {
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      await _pump(tester, c, 'kora');
      await tester.tap(_key('crew-add-b1'));
      await tester.pump();
      expect(_crew(c, 'b1'), 1);
      // − takes it out again.
      await tester.tap(_key('crew-remove-b1'));
      await tester.pump();
      expect(_crew(c, 'b1'), 0);
    });

    testWidgets('with no crew free, + is disabled', (tester) async {
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      c.state.faction(_p).baseCrew = crewTotals(c.state, content, _p).assigned;
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      expect(tester.widget<IconButton>(_key('crew-add-b1')).onPressed, isNull);
    });

    testWidgets('crew pips: filled per crew, hollow up to the most', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.run(const UpgradeCommand(_p, 'b3', UpgradeTrack.capacity));
      c.run(const AssignCrewCommand(_p, 'b3', 1));
      await _pump(tester, c, 'kora');
      expect(find.bySemanticsLabel('Crew 1 of 2, 1 base slot'), findsOneWidget);
    });
  });

  group('upgrades', () {
    testWidgets('an affordable upgrade raises its level and costs credits', (
      tester,
    ) async {
      await _pump(tester, c, 'kora');
      expect(find.textContaining('250'), findsWidgets);
      await tester.tap(_key('upgrade-b3-speed'));
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 1);
      // 250 - 75 = 175 credits shown in the top bar.
      expect(find.bySemanticsLabel(RegExp(r'^Credits 175')), findsOneWidget);
    });

    testWidgets('a rapid triple tap with credits for one: +1, one SnackBar, '
        'then unaffordable (Review Focus 3)', (tester) async {
      c.state.faction(_p).credits = BigNum.from(80); // one speed level, 75
      await _pump(tester, c, 'kora');
      final button = _key('upgrade-b3-speed');
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 1);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump();
      expect(_enabled(tester, button), isFalse);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
    });

    testWidgets('a maxed track says why instead of a dead button', (
      tester,
    ) async {
      final b3 = c.state.body('kora').buildings.firstWhere((b) => b.id == 'b3');
      var level = 0;
      while (upgradeMaxedReason(content, b3, UpgradeTrack.efficiency) == null) {
        b3.levels[UpgradeTrack.efficiency] = ++level;
      }
      await _pump(tester, c, 'kora');
      final why = upgradeMaxedReason(content, b3, UpgradeTrack.efficiency)!;
      expect(find.textContaining(why), findsOneWidget);
    });

    testWidgets('a long press buys up to 10 levels while affordable', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e9);
      await _pump(tester, c, 'kora');
      await tester.longPress(_key('upgrade-b3-speed'));
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 10);
    });

    testWidgets('an upgrade button shows its payback', (tester) async {
      await _pump(tester, c, 'kora');
      expect(find.textContaining('pays back'), findsWidgets);
    }, skip: true); // Task 0: upgradePreview fills UpgradeButtonView.payback.
  });

  group('build', () {
    testWidgets('building a mine on a free slot adds a row', (tester) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      await _pump(tester, c, 'kora');
      final before = find
          .byKey(const ValueKey('building-row'))
          .evaluate()
          .length;
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(_key('build-mine-silicon-kora'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('building-row')).evaluate().length,
        before + 1,
      );
      expect(find.textContaining('Mine (Silicon)  Lv'), findsOneWidget);
    });

    testWidgets('the catalog says why Mine (Copper Ore) cannot go on Brine', (
      tester,
    ) async {
      c.state.body('brine').ownerId = _p;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: ControllerScope(
            controller: c,
            child: const Scaffold(body: CatalogSheet()),
          ),
        ),
      );
      final entry = _key('catalog-Mine (Copper Ore)');
      await tester.scrollUntilVisible(entry, 200);
      expect(
        find.descendant(
          of: entry,
          matching: find.textContaining('needs a Copper Ore deposit'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a "not enough X" problem opens X\'s makers', (
      tester,
    ) async {
      c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
      c.run(const AssignCrewCommand(_p, 'b1', 0));
      c.tickSeconds(1);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('problem-b3'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogSheet), findsOneWidget);
      expect(_key('catalog-Mine (Iron Ore)'), findsOneWidget);
      expect(_key('catalog-Smelter'), findsNothing);
    });

    testWidgets(
      'a long press on a building offers Demolish, confirmed inline',
      (tester) async {
        await _pump(tester, c, 'kora');
        await tester.longPress(find.textContaining('Smelter  Lv'));
        await tester.pump();
        await tester.tap(_key('demolish-b3'));
        await tester.pump();
        expect(
          c.state.body('kora').buildings.map((b) => b.id),
          isNot(contains('b3')),
        );
      },
    );
  });

  group('claims', () {
    testWidgets('an unowned body shows its deposits, cost and time', (
      tester,
    ) async {
      await _pump(tester, c, 'cinder');
      expect(find.textContaining('Sulfur'), findsWidgets);
      expect(find.textContaining('5K credits'), findsWidgets);
      expect(find.textContaining('30m'), findsWidgets);
      // 250 credits: disabled, with the reason.
      expect(_enabled(tester, _key('claim')), isFalse);
      expect(find.textContaining('needs 5K credits'), findsOneWidget);
    });

    testWidgets('claiming counts down, then the body is owned', (tester) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      await _pump(tester, c, 'cinder');
      await tester.tap(_key('claim'));
      await tester.pump();
      expect(find.textContaining('Claiming… 30m left'), findsOneWidget);

      c.tickSeconds(30 * 60 + 1);
      await tester.pump();
      expect(c.state.body('cinder').ownerId, _p);
      expect(find.text('Build'), findsOneWidget, reason: 'the owned layout');
      expect(_key('claim'), findsNothing);
    });

    testWidgets('a second claim needing kits picks its source body', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('brine').ownerId = _p;
      c.state.body('brine').stock['outpost_kit'] = BigNum.from(50);
      await _pump(tester, c, 'cinder');
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      await tester.tap(_key('claim'));
      await tester.pump();
      expect(c.state.body('brine').stock['outpost_kit']!.toDouble(), 40);
    });
  });

  group('slots and buy max', () {
    testWidgets('Expand slots shows its price and time, then counts down', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e9);
      await _pump(tester, c, 'kora');
      expect(find.textContaining('Expand slots (+1)'), findsOneWidget);
      await tester.tap(_key('expand-slots'));
      await tester.pump();
      expect(find.textContaining('Extra build slot on Kora'), findsOneWidget);
    });

    testWidgets('Buy max shows what it buys, and buys it', (tester) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.faction(_p).credits = BigNum.from(300);
      await _pump(tester, c, 'kora');
      final button = _key('buy-max');
      expect(
        find.descendant(of: button, matching: find.textContaining('levels')),
        findsWidgets,
      );
      await tester.tap(button);
      await tester.pump();
      // Over half the credits: a second, inline step.
      expect(_key('buy-max-confirm'), findsOneWidget);
      await tester.tap(_key('buy-max-confirm'));
      await tester.pump();
      expect(find.textContaining('Bought '), findsOneWidget, reason: 'outcome');
    });

    testWidgets('Buy max with too few credits says what the next costs', (
      tester,
    ) async {
      c.state.faction(_p).credits = const BigNum.zero();
      await _pump(tester, c, 'kora');
      expect(_enabled(tester, _key('buy-max')), isFalse);
      expect(find.textContaining('the cheapest costs'), findsOneWidget);
    });
  });

  group('fits (Review Focus 4)', () {
    for (final body in ['kora', 'cinder']) {
      testWidgets('$body at 360x640 and 2x text: no overflow', (tester) async {
        c.state.faction(_p).credits = BigNum.from(1e6);
        await _pump(tester, c, body, size: const Size(360, 640), textScale: 2);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(PlanetPanel), const Offset(0, -2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
