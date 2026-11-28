import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/build_picker.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/planet_panel.dart';
import 'package:space_idle/ui/top_bar.dart';
import 'package:space_idle/view/body_actions_view.dart';
import 'package:space_idle/view/spend_view.dart';

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
      // One speed level (75) is half of 150: no confirm, and the next
      // costs more than the 75 left.
      c.state.faction(_p).credits = BigNum.from(150);
      await _pump(tester, c, 'kora');
      final button = _key('upgrade-b3-speed');
      await tester.tap(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 1);
      expect(find.byType(SnackBar), findsOneWidget);
      // The messenger builds only the head of its queue: wait the shown
      // one out, and no second one may follow it.
      // (Its timer starts once it is in.)
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: 'one, not queued');
      expect(_enabled(tester, button), isFalse);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
    });

    testWidgets('repeated failures replace their own message, not others', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(150);
      await _pump(tester, c, 'kora');
      ScaffoldMessenger.of(tester.element(find.byType(PlanetPanel)))
          .showSnackBar(const SnackBar(content: Text('Unrelated news')));
      await tester.pumpAndSettle();
      final button = _key('upgrade-b3-speed');
      // One level, then three failures within the frame.
      for (var i = 0; i < 4; i++) {
        await tester.tap(button);
      }
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 1);
      expect(find.text('Unrelated news'), findsOneWidget, reason: 'kept');
      // It times out; then one failure message, then nothing.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Unrelated news'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: 'one, not queued');
    });

    testWidgets('a new failure replaces the one showing', (tester) async {
      await _pump(tester, c, 'kora');
      final context = tester.element(find.byType(PlanetPanel));
      runAndReport(context, c, const AssignCrewCommand(_p, 'nope', 1));
      await tester.pumpAndSettle();
      final first = c.lastError!;
      expect(find.text(first), findsOneWidget);
      runAndReport(context, c, const DemolishCommand(_p, 'nope-either'));
      await tester.pumpAndSettle();
      expect(find.text(first), findsNothing);
      expect(find.text(c.lastError!), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: 'one, not queued');
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
      // The long press shows the ten levels' total before buying.
      expect(_level(c, 'b3', UpgradeTrack.speed), 0);
      final ten = bulkUpgrade(c, 'b3', UpgradeTrack.speed, 10);
      expect(
        find.textContaining('Spend ${formatNumber(ten.price)} of'),
        findsOneWidget,
      );
      expect(find.textContaining('on 10 Speed levels'), findsOneWidget);
      await tester.tap(_key('confirm-upgrade-b3'));
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
      // The sheet closed, and its sentence shows on the shell.
      expect(find.byType(CatalogSheet), findsNothing);
      expect(find.textContaining('Built Mine on Kora'), findsOneWidget);
    });

    testWidgets('a failed Build says why inside the catalog, still open', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      await _pump(tester, c, 'kora');
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      // The credits go without a tick: the button is stale.
      c.state.faction(_p).credits = const BigNum.zero();
      await tester.tap(_key('build-mine-silicon-kora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CatalogSheet), findsOneWidget);
      expect(
        find.descendant(
          of: _key('catalog-messages'),
          matching: find.byType(SnackBar),
        ),
        findsOneWidget,
      );
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

  group('spends over half the credits take a second tap', () {
    // Credits of which [price] is two thirds: over half, affordable.
    BigNum oneAndAHalfTimes(BigNum price) => price.mulDouble(1.5);

    testWidgets('Upgrade', (tester) async {
      c.state.faction(_p).credits = BigNum.from(100); // 75 of 100
      await _pump(tester, c, 'kora');
      await tester.tap(_key('upgrade-b3-speed'));
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 0);
      expect(find.textContaining('Spend 75 of 100 credits'), findsOneWidget);
      await tester.tap(_key('confirm-upgrade-b3'));
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 1);
    });

    testWidgets('Cancel spends nothing', (tester) async {
      c.state.faction(_p).credits = BigNum.from(100);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('upgrade-b3-speed'));
      await tester.pump();
      await tester.tap(_key('cancel-upgrade-b3'));
      await tester.pump();
      expect(_key('confirm-upgrade-b3'), findsNothing);
      expect(_level(c, 'b3', UpgradeTrack.speed), 0);
    });

    testWidgets('Claim', (tester) async {
      final price = claimCost(c.state, content, _p)[creditsKey]!;
      c.state.faction(_p).credits = oneAndAHalfTimes(price);
      await _pump(tester, c, 'cinder');
      await tester.tap(_key('claim'));
      await tester.pump();
      expect(projectOn(c.state, ProjectKind.claim, 'cinder'), isNull);
      expect(find.textContaining('to claim Cinder'), findsOneWidget);
      await tester.tap(_key('confirm-claim'));
      await tester.pump();
      expect(projectOn(c.state, ProjectKind.claim, 'cinder'), isNotNull);
    });

    testWidgets('a new kit source takes the Claim back to one tap', (
      tester,
    ) async {
      for (final id in ['brine', 'hollow_reach']) {
        c.state.body(id).ownerId = _p;
        c.state.body(id).stock['outpost_kit'] = BigNum.from(50);
      }
      final price = claimCost(c.state, content, _p)[creditsKey]!;
      c.state.faction(_p).credits = oneAndAHalfTimes(price);
      await _pump(tester, c, 'cinder');
      await tester.tap(_key('claim'));
      await tester.pump();
      // The confirm names the source it would take the kits from.
      expect(find.textContaining('kits from Hollow Reach'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brine').last);
      await tester.pumpAndSettle();
      expect(_key('confirm-claim'), findsNothing, reason: 'asked for Hollow');

      await tester.tap(_key('claim'));
      await tester.pump();
      expect(find.textContaining('kits from Brine'), findsOneWidget);
      await tester.tap(_key('confirm-claim'));
      await tester.pump();
      expect(
        c.state.body('brine').stock['outpost_kit']!.toDouble(),
        lessThan(50),
      );
      expect(c.state.body('hollow_reach').stock['outpost_kit']!.toDouble(), 50);
    });

    testWidgets('Expand slots', (tester) async {
      final price = slotCost(content, c.state.body('kora'))[creditsKey]!;
      c.state.faction(_p).credits = oneAndAHalfTimes(price);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('expand-slots'));
      await tester.pump();
      expect(projectOn(c.state, ProjectKind.expandSlots, 'kora'), isNull);
      await tester.tap(_key('confirm-expand-slots'));
      await tester.pump();
      expect(projectOn(c.state, ProjectKind.expandSlots, 'kora'), isNotNull);
    });

    testWidgets('Build', (tester) async {
      final price = content.buildings['mine']!.buildCost[creditsKey]!;
      c.state.faction(_p).credits = oneAndAHalfTimes(price);
      await _pump(tester, c, 'kora');
      final before = c.state.body('kora').buildings.length;
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      await tester.tap(_key('build-mine-silicon-kora'));
      await tester.pumpAndSettle();
      expect(c.state.body('kora').buildings, hasLength(before));
      await tester.tap(_key('confirm-catalog-Mine (Silicon)'));
      await tester.pumpAndSettle();
      expect(c.state.body('kora').buildings, hasLength(before + 1));
    });

    testWidgets('under half, one tap: Upgrade, Claim, Expand slots', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e9);
      await _pump(tester, c, 'kora');
      await tester.tap(_key('upgrade-b3-speed'));
      await tester.tap(_key('expand-slots'));
      await tester.pump();
      expect(_level(c, 'b3', UpgradeTrack.speed), 1);
      expect(projectOn(c.state, ProjectKind.expandSlots, 'kora'), isNotNull);
      await _pump(tester, c, 'cinder');
      await tester.tap(_key('claim'));
      await tester.pump();
      expect(projectOn(c.state, ProjectKind.claim, 'cinder'), isNotNull);
      expect(find.textContaining('Spend '), findsNothing);
    });
  });

  group('switching bodies', () {
    testWidgets('a demolish confirm on Kora does not follow to Brine', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e9);
      c.state.body('brine').ownerId = _p;
      for (var i = 0; i < 3; i++) {
        expect(
          c.run(const BuildCommand(_p, 'brine', 'smelter')),
          isA<CommandOk>(),
        );
      }
      final brine = c.state.body('brine').buildings.map((b) => b.id).toList();
      var body = 'kora';
      late StateSetter set;
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: ControllerScope(
            controller: c,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, s) {
                  set = s;
                  // Keyed as the shell keys it.
                  return PlanetPanel(key: ValueKey(body), bodyId: body);
                },
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.textContaining('Smelter  Lv').first);
      await tester.pump();
      expect(_key('demolish-b3'), findsOneWidget);

      set(() => body = 'brine');
      await tester.pump();
      expect(find.textContaining('Demolish '), findsNothing);
      for (final id in brine) {
        expect(_key('demolish-$id'), findsNothing);
      }
      expect(c.state.body('brine').buildings, hasLength(3));
    });
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

  group('slots', () {
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

    testWidgets('Expand slots blocked: a lock and the reason', (tester) async {
      await _pump(tester, c, 'kora'); // 250 credits
      final why = expandSlotsView(c, 'kora')!.blockedReason!;
      final line = find.ancestor(
        of: find.text(why),
        matching: find.byType(BlockedReason),
      );
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
    });

    testWidgets('Buy max is in the top bar, not on a body', (tester) async {
      await _pump(tester, c, 'kora');
      expect(
        find.descendant(
          of: find.byType(PlanetPanel),
          matching: find.textContaining('Buy max'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byType(TopBar), matching: _key('buy-max')),
        findsOneWidget,
      );
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

    testWidgets('a kit claim with two sources at 360x640 and 2x text', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      for (final id in ['brine', 'hollow_reach']) {
        c.state.body(id).ownerId = _p;
        c.state.body(id).stock['outpost_kit'] = BigNum.from(50);
      }
      await _pump(
        tester,
        c,
        'cinder',
        size: const Size(360, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byType(DropdownButton<String>),
        100,
        scrollable: find
            .descendant(
              of: find.byType(PlanetPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(PlanetPanel), const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
