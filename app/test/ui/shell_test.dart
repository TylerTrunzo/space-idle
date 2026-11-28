import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/map/star_map.dart';
import 'package:space_idle/ui/planet/planet_panel.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/ui/top_bar.dart';

/// Boots the app on an empty store and lets start() finish.
Future<void> _boot(WidgetTester tester, {Size? size}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    SpaceIdleApp(
      store: MemorySaveStore(),
      clock: FakeClock(DateTime.utc(2026, 11, 27)),
    ),
  );
  // start() completes in microtasks; the map's ticker never settles, so
  // pump frames rather than pumpAndSettle.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('boots to the Map tab with the top bar', (tester) async {
    await _boot(tester);
    expect(find.byType(Shell), findsOneWidget);
    expect(find.byType(StarMap), findsOneWidget);
    expect(find.byType(TopBar), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    expect(bar.destinations, hasLength(4));
  });

  testWidgets('each nav item switches to its tab', (tester) async {
    await _boot(tester);
    for (final (i, label) in ['Production', 'Crew', 'Trade', 'Map'].indexed) {
      await tester.tap(find.text(label).last);
      await tester.pump();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, (i + 1) % 4, reason: label);
      if (label != 'Map') {
        expect(find.byKey(ValueKey('tab-$label')), findsOneWidget);
      }
    }
  });

  testWidgets('at 1000x800 selecting a body opens the side panel', (
    tester,
  ) async {
    await _boot(tester, size: const Size(1000, 800));
    expect(find.byKey(Shell.sidePanelKey), findsNothing);

    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();
    final panel = find.byKey(Shell.sidePanelKey);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, 400);
    expect(find.byKey(Shell.sheetKey), findsNothing);
    expect(
      find.descendant(of: panel, matching: find.text('Kora')),
      findsOneWidget,
    );
    // The map keeps the rest of the width.
    expect(tester.getSize(find.byType(StarMap)).width, 600);
  });

  testWidgets('at 400x800 selecting a body opens a draggable sheet', (
    tester,
  ) async {
    await _boot(tester, size: const Size(400, 800));
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();

    expect(find.byKey(Shell.sheetKey), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byKey(Shell.sidePanelKey), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(Shell.sheetKey),
        matching: find.text('Kora'),
      ),
      findsOneWidget,
    );
  });

  bool mapTicks(WidgetTester tester) => TickerMode.valuesOf(
    tester.element(find.byType(StarMap, skipOffstage: false)),
  ).enabled;

  testWidgets('a full sheet, a turn to wide and back: the map ticks again', (
    tester,
  ) async {
    await _boot(tester, size: const Size(412, 915));
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();
    final title = find.descendant(
      of: find.byKey(Shell.sheetKey),
      matching: find.text('Kora'),
    );
    await tester.drag(title, const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(mapTicks(tester), isFalse, reason: 'fully covered');

    tester.view.physicalSize = const Size(915, 412); // wide: a side panel
    await tester.pump();
    tester.view.physicalSize = const Size(412, 915); // the sheet again
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(Shell.sheetKey), findsOneWidget);
    expect(mapTicks(tester), isTrue, reason: 'the new sheet is at 45%');
  });

  testWidgets('the map stops animating while the sheet covers it', (
    tester,
  ) async {
    await _boot(tester, size: const Size(400, 800));
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();
    expect(mapTicks(tester), isTrue, reason: 'partly covered');

    // Drag the sheet all the way up, by its title: the sheet's own box
    // fills the map area, so its centre may be on the map above it.
    final title = find.descendant(
      of: find.byKey(Shell.sheetKey),
      matching: find.text('Kora'),
    );
    await tester.drag(title, const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(mapTicks(tester), isFalse, reason: 'fully covered');

    await tester.drag(title, const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(mapTicks(tester), isTrue, reason: 'uncovered again');
  });

  testWidgets('the map stops animating on another tab', (tester) async {
    await _boot(tester);
    expect(mapTicks(tester), isTrue);
    await tester.tap(find.text('Production').last);
    await tester.pump();
    expect(mapTicks(tester), isFalse);
    await tester.tap(find.text('Map').last);
    await tester.pump();
    expect(mapTicks(tester), isTrue);
  });

  testWidgets('Android back closes the selected body before leaving', (
    tester,
  ) async {
    await _boot(tester, size: const Size(400, 800));
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(Shell.sheetKey), findsOneWidget);

    final popped = await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popped, isTrue, reason: 'the app handled back itself');
    expect(find.byKey(Shell.sheetKey), findsNothing);
    expect(find.byType(Shell), findsOneWidget);
  });

  testWidgets('closing the panel clears the selection', (tester) async {
    await _boot(tester, size: const Size(1000, 800));
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.byKey(Shell.sidePanelKey), findsNothing);
  });

  testWidgets('ShellScope.selectBody selects from anywhere', (tester) async {
    await _boot(tester, size: const Size(1000, 800));
    ShellScope.of(tester.element(find.byType(TopBar))).selectBody('cinder');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(Shell.sidePanelKey),
        matching: find.text('Cinder'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching bodies resets what the panel was asking', (
    tester,
  ) async {
    await _boot(tester, size: const Size(1000, 1600));
    final scope = tester.element(find.byType(TopBar));
    final c = ControllerScope.of(scope);
    c.state.faction('player').credits = BigNum.from(1e6);
    for (final id in ['brine', 'hollow_reach']) {
      c.state.body(id).ownerId = 'player';
      c.state.body(id).stock['outpost_kit'] = BigNum.from(50);
    }
    c.tickSeconds(1);
    ShellScope.of(scope).selectBody('cinder');
    await tester.pump();
    // Hollow Reach comes first; take Cinder's kits from Brine.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brine').last);
    await tester.pumpAndSettle();
    final picked = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(picked.value, 'brine');

    ShellScope.of(scope).selectBody('vastmere');
    await tester.pump();
    final fresh = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(
      fresh.value,
      'hollow_reach',
      reason: "Cinder's choice stays with Cinder",
    );
  });

  testWidgets('on a phone, switching bodies drops a pending confirm', (
    tester,
  ) async {
    await _boot(tester, size: const Size(412, 915));
    final scope = tester.element(find.byType(TopBar));
    final c = ControllerScope.of(scope);
    c.state.body('brine').ownerId = 'player';
    final price = slotCost(c.content, c.state.body('kora'))[creditsKey]!;
    c.state.faction('player').credits = price.mulDouble(1.5);
    c.tickSeconds(1);
    ShellScope.of(scope).selectBody('kora');
    await tester.pump();
    expect(find.byKey(Shell.sheetKey), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expand-slots')));
    await tester.pump();
    expect(find.byKey(const ValueKey('confirm-expand-slots')), findsOneWidget);

    ShellScope.of(scope).selectBody('brine');
    await tester.pump();
    expect(find.text('Brine'), findsWidgets);
    expect(
      find.byKey(const ValueKey('confirm-expand-slots')),
      findsNothing,
      reason: "Kora's slot, not Brine's",
    );
  });

  group('the phone sheet', () {
    Future<void> openKora(WidgetTester tester) async {
      await _boot(tester, size: const Size(412, 915));
      ShellScope.of(tester.element(find.byType(TopBar))).selectBody('kora');
      await tester.pump();
      await tester.pump();
    }

    double sheetTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(PlanetPanel)).dy;

    testWidgets('the selected body stays in view above it', (tester) async {
      await openKora(tester);
      final map = tester.getRect(find.byType(Shell));
      final top = tester.getTopLeft(find.byType(StarMap)).dy;
      final visible = Rect.fromLTRB(map.left, top, map.right, sheetTop(tester));
      final kora = tester.getRect(find.bySemanticsLabel('Kora, owned'));
      expect(visible.height, greaterThan(100));
      expect(
        visible.contains(kora.topLeft) && visible.contains(kora.bottomRight),
        isTrue,
        reason: 'Kora at $kora, the map shows $visible',
      );
    });

    testWidgets('it drags with a mouse', (tester) async {
      await openKora(tester);
      final before = sheetTop(tester);
      await tester.drag(
        find.byType(PlanetPanel),
        const Offset(0, -250),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(sheetTop(tester), lessThan(before - 100));
    });

    testWidgets('a tap on its header toggles it full and back', (tester) async {
      await openKora(tester);
      final half = sheetTop(tester);
      final name = find.descendant(
        of: find.byType(PlanetPanel),
        matching: find.text('Kora'),
      );
      await tester.tap(name);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final full = sheetTop(tester);
      expect(full, lessThan(half - 200));
      await tester.tap(name);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sheetTop(tester), closeTo(half, 1));
    });
  });

  testWidgets('the signal marker says surveys come with the Projects tab', (
    tester,
  ) async {
    await _boot(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Unsurveyed signal')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.text('Surveys arrive with the Projects tab'), findsOneWidget);
  });

  testWidgets('the settings button opens the settings sheet', (tester) async {
    await _boot(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('settings-sheet')), findsOneWidget);
  });

  testWidgets('no overflow on a 360x640 phone at 2x text, panel open', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _boot(tester, size: const Size(360, 640));
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
