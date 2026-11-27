import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/ui/map/star_map.dart';
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
