import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/ui/broken_save_screen.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/shell.dart';

final Content content = loadEmbeddedContent();

/// A slot whose read waits for [gate].
final class _SlowStore implements SaveStore {
  final gate = Completer<String?>();
  @override
  Future<String?> read() => gate.future;
  @override
  Future<void> write(String text) async {}
}

/// Steps the binding through [states] in order: the test binding, unlike
/// the platform, does not fill in the states between two.
void _go(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

const _toBackground = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

const _toForeground = [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

Future<void> _pumpApp(
  WidgetTester tester,
  SaveStore store,
  FakeClock clock,
) async {
  // A real app starts resumed; the test binding starts with no state, and
  // from none a pause skips hide. Start resumed and end resumed.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() {
    switch (tester.binding.lifecycleState) {
      case AppLifecycleState.paused:
        _go(tester, _toForeground);
      case AppLifecycleState.detached:
        _go(tester, [AppLifecycleState.resumed]);
      case _:
        break;
    }
  });
  await tester.pumpWidget(SpaceIdleApp(store: store, clock: clock));
  await tester.pump();
  await tester.pump();
}

GameController _controllerIn(WidgetTester tester) =>
    ControllerScope.of(tester.element(find.byType(Shell)));

/// A stored envelope saved at [clock]'s time, holding a new game.
String _savedNow(FakeClock clock) => jsonEncode({
  'savedAt': clock.now().millisecondsSinceEpoch,
  'save': SaveCodec.encode(GameEngine(content).newGame(1)),
});

void main() {
  late FakeClock clock;
  setUp(() => clock = FakeClock(DateTime.utc(2026, 11, 27, 12)));

  testWidgets('shows a loading screen until start() completes', (tester) async {
    final store = _SlowStore();
    await tester.pumpWidget(SpaceIdleApp(store: store, clock: clock));
    await tester.pump();
    expect(find.byKey(SpaceIdleApp.loadingKey), findsOneWidget);
    expect(find.byType(Shell), findsNothing);

    store.gate.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Shell), findsOneWidget);
  });

  group('lifecycle', () {
    testWidgets('pausing saves and stops the timer; resuming catches up', (
      tester,
    ) async {
      final store = MemorySaveStore();
      await _pumpApp(tester, store, clock);
      final c = _controllerIn(tester);
      final writes = store.writes;

      _go(tester, _toBackground);
      await tester.pump();
      expect(store.writes, greaterThan(writes), reason: 'saved on pause');

      // Paused: the timer is off, so frames pass and the game stands still.
      final time = c.state.time;
      clock.advance(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(c.state.time, time);

      clock.advance(const Duration(minutes: 10));
      _go(tester, _toForeground);
      await tester.pump();
      expect(c.state.time, closeTo(time + 605, 1e-6), reason: 'caught up');

      // Resumed: the timer runs again.
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.time, closeTo(time + 606, 1e-6));
    });

    testWidgets('hiding and detaching save too', (tester) async {
      final store = MemorySaveStore();
      await _pumpApp(tester, store, clock);

      var writes = store.writes;
      _go(tester, _toBackground.take(2).toList());
      await tester.pump();
      expect(store.writes, greaterThan(writes), reason: 'saved on hide');

      writes = store.writes;
      _go(tester, [AppLifecycleState.paused]);
      await tester.pump();
      writes = store.writes;
      _go(tester, [AppLifecycleState.detached]);
      await tester.pump();
      expect(store.writes, greaterThan(writes), reason: 'saved on detach');
    });
  });

  group('away summary placeholder', () {
    testWidgets('a launch after time away shows it; OK clears it', (
      tester,
    ) async {
      final store = MemorySaveStore(_savedNow(clock));
      clock.advance(const Duration(hours: 2));
      await _pumpApp(tester, store, clock);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('While you were away'), findsOneWidget);
      expect(find.textContaining('2h'), findsWidgets);
      expect(find.textContaining('credits'), findsWidgets);

      expect(find.byType(AlertDialog), findsOneWidget, reason: 'one dialog');
      await tester.tap(find.text('OK'));
      // Frames until the dialog's route has gone (the map's ticker never
      // lets pumpAndSettle settle), at most 5 s of game frames.
      for (
        var i = 0;
        i < 25 && find.byType(AlertDialog).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('While you were away'), findsNothing);
      expect(_controllerIn(tester).pendingAwaySummaries, isEmpty);
    });

    testWidgets('two catch-ups before OK are combined', (tester) async {
      final store = MemorySaveStore(_savedNow(clock));
      clock.advance(const Duration(hours: 2));
      await _pumpApp(tester, store, clock);
      await tester.pump(const Duration(milliseconds: 300));

      _go(tester, _toBackground);
      await tester.pump();
      clock.advance(const Duration(hours: 1));
      _go(tester, _toForeground);
      await tester.pump(const Duration(milliseconds: 300));

      expect(_controllerIn(tester).pendingAwaySummaries, hasLength(2));
      expect(find.text('While you were away'), findsOneWidget);
      expect(find.textContaining('3h'), findsWidgets);
    });

    testWidgets('no dialog on a fresh start', (tester) async {
      await _pumpApp(tester, MemorySaveStore(), clock);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('While you were away'), findsNothing);
    });
  });

  group('a save that cannot be loaded', () {
    late List<String> clipboard;
    setUp(() => clipboard = []);

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('shows the broken-save screen, never a crash', (tester) async {
      final store = MemorySaveStore('garbage from an older build');
      await _pumpApp(tester, store, clock);

      expect(tester.takeException(), isNull);
      expect(find.byType(BrokenSaveScreen), findsOneWidget);
      expect(find.text("Your save couldn't be loaded"), findsOneWidget);
      expect(find.byType(Shell), findsNothing);
      expect(store.text, 'garbage from an older build');
    });

    testWidgets('Export copies the broken text', (tester) async {
      mockClipboard(tester);
      await _pumpApp(tester, MemorySaveStore('garbage'), clock);

      await tester.tap(find.text('Export'));
      await tester.pump();
      expect(clipboard, ['garbage']);
      expect(find.text('Copied the save text'), findsOneWidget);
    });

    testWidgets('Start new game replaces it and opens the game', (
      tester,
    ) async {
      final store = MemorySaveStore('garbage');
      await _pumpApp(tester, store, clock);

      await tester.tap(find.text('Start new game'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(Shell), findsOneWidget);
      expect(store.text, isNot('garbage'));
      expect(jsonDecode(store.text!), isA<Map<String, Object?>>());
    });
  });
}
