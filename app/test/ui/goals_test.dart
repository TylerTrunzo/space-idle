import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/guide.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/game/settings_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/goals/goal_strip.dart';
import 'package:space_idle/ui/goals/guide_scope.dart';
import 'package:space_idle/ui/settings_sheet.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/goal_strip_view.dart';
import 'package:space_idle/view/onboarding.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  late GameController c;
  late Guide guide;
  late MemorySettingsStore settings;
  late List<VoidCallback> fills;
  String? shown;

  GameController controller() => GameController(
    content: content,
    store: MemorySaveStore(),
    clock: FakeClock(DateTime.utc(2026, 11, 27)),
    newGameSeed: 1,
    scheduleFill: fills.add,
  );

  setUp(() async {
    fills = [];
    shown = null;
    settings = MemorySettingsStore();
    c = controller();
    guide = Guide(controller: c, store: settings);
    await guide.load();
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 1200),
    double textScale = 1,
    Widget? below,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
    }
    // As in the app: both scopes sit above the navigator, so a sheet's
    // route finds them too.
    await tester.pumpWidget(
      ControllerScope(
        controller: c,
        child: GuideScope(
          guide: guide,
          child: MaterialApp(
            theme: buildTheme(),
            home: ShellScope(
              selectedId: null,
              selectBody: (_) {},
              clearSelection: () {},
              showOnMap: (id) => shown = id,
              child: Scaffold(
                body: Column(children: [const GoalStrip(), ?below]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder inSlot(String slot, Finder f) =>
      find.descendant(of: _key('goal-$slot'), matching: f);

  testWidgets('a new game shows the guide\'s first step in Now', (
    tester,
  ) async {
    await pump(tester);
    expect(
      inSlot('now', find.textContaining(onboardingSteps[0].title)),
      findsOneWidget,
    );
    expect(inSlot('now', find.textContaining('Now  ')), findsOneWidget);
    expect(_key('goal-today'), findsOneWidget);
    expect(_key('goal-long'), findsOneWidget);
  });

  testWidgets('selling Steel moves on to step 2, and says it is done', (
    tester,
  ) async {
    await pump(tester);
    c.state.body('kora').stock['steel'] = BigNum.from(10);
    c.run(SellCommand(_p, 'kora', 'steel', BigNum.from(10)));
    await tester.pump();
    expect(
      inSlot('now', find.textContaining('Build a second Smelter')),
      findsOneWidget,
    );
    expect(find.text('Done: ${onboardingSteps[0].title}'), findsOneWidget);
  });

  testWidgets('a state with two smelters skips step 2', (tester) async {
    c.run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(100)));
    c.state.faction(_p).credits = BigNum.from(1e6);
    c.run(const BuildCommand(_p, 'kora', 'smelter'));
    await pump(tester);
    expect(find.textContaining('Build a second Smelter'), findsNothing);
    expect(
      inSlot('now', find.textContaining('Buy an upgrade')),
      findsOneWidget,
    );
  });

  testWidgets('Today shows a milestone, its bar at milestoneProgress', (
    tester,
  ) async {
    await pump(tester);
    final today = goalStripView(c).today;
    expect(inSlot('today', find.textContaining(today.title)), findsOneWidget);
    final m = content.milestones.firstWhere(
      (m) => milestoneGoalText(content, m) == today.title,
    );
    final p = milestoneProgress(c.state, content, _p, m);
    final bar = tester.widget<LinearProgressIndicator>(
      inSlot('today', find.byType(LinearProgressIndicator)),
    );
    expect(
      bar.value,
      closeTo((p.current.toDouble() / p.target.toDouble()).clamp(0, 1), 1e-9),
    );
  });

  testWidgets('tapping Now opens its body on the map', (tester) async {
    await pump(tester);
    await tester.tap(_key('goal-now'));
    await tester.pump();
    expect(shown, 'kora');
  });

  testWidgets('fold to the Now row and back; the fold is kept', (tester) async {
    await pump(tester);
    await tester.tap(_key('goals-fold'));
    await tester.pump();
    expect(_key('goal-today'), findsNothing);
    expect(_key('goal-now'), findsOneWidget);
    expect(guide.collapsed, isTrue);
    expect(settings.values[Guide.key], contains('"collapsed":true'));
    await tester.tap(_key('goals-fold'));
    await tester.pump();
    expect(_key('goal-today'), findsOneWidget);
  });

  testWidgets('with the guide skipped, Now finds the best upgrade in fills', (
    tester,
  ) async {
    for (final id in content.resources.keys) {
      c.run(SetAutoSellCommand(_p, 'kora', id, const BigNum.zero()));
    }
    c.tickSeconds(1);
    await guide.skip();
    await pump(tester);
    expect(
      inSlot('now', find.textContaining('Looking for the best upgrade')),
      findsOneWidget,
      reason: 'nothing worked out in the frame',
    );
    while (fills.isNotEmpty) {
      fills.removeAt(0)();
    }
    await tester.pump();
    expect(inSlot('now', find.textContaining('pays back in')), findsOneWidget);
  });

  testWidgets('Skip guide in the settings ends the guide', (tester) async {
    await pump(
      tester,
      below: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSettingsSheet(context),
          child: const Text('open settings'),
        ),
      ),
    );
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    await tester.tap(_key('skip-guide'));
    await tester.pumpAndSettle();
    expect(guide.ended, isTrue);
    expect(find.textContaining(onboardingSteps[0].title), findsNothing);
  });

  testWidgets('the guide\'s step survives an app restart, in the settings', (
    tester,
  ) async {
    final kept = MemorySettingsStore();
    Future<void> boot() async {
      await tester.pumpWidget(
        SpaceIdleApp(
          // A new save each time: only the settings carry the guide.
          store: MemorySaveStore(),
          clock: FakeClock(DateTime.utc(2026, 11, 27)),
          settings: kept,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await boot();
    final app = ControllerScope.of(tester.element(find.byType(GoalStrip)));
    app.state.body('kora').stock['steel'] = BigNum.from(10);
    app.run(SellCommand(_p, 'kora', 'steel', BigNum.from(10)));
    await tester.pump();
    expect(find.textContaining('Build a second Smelter'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await boot();
    expect(find.textContaining('Build a second Smelter'), findsOneWidget);
    expect(find.textContaining(onboardingSteps[0].title), findsNothing);
  });

  group('a launch the settings cannot hold up', () {
    Future<void> boot(WidgetTester tester, SettingsStore settings) async {
      await tester.pumpWidget(
        SpaceIdleApp(
          store: MemorySaveStore(),
          clock: FakeClock(DateTime.utc(2026, 11, 27)),
          settings: settings,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a read that never answers: the game shows anyway', (
      tester,
    ) async {
      await boot(tester, _SilentStore());
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(tester.takeException(), isA<TimeoutException>());
      expect(find.byType(Shell), findsOneWidget);
      expect(find.byKey(SpaceIdleApp.loadingKey), findsNothing);
    });

    testWidgets('a read that throws: the game shows, the guide starts fresh', (
      tester,
    ) async {
      await boot(tester, _ThrowingReads());
      expect(tester.takeException(), isA<StateError>(), reason: 'reported');
      expect(find.byType(Shell), findsOneWidget);
      expect(find.textContaining(onboardingSteps[0].title), findsOneWidget);
    });
  });

  testWidgets('the goal rows are buttons, and the bars say how far', (
    tester,
  ) async {
    await pump(tester);
    final now = tester.getSemantics(_key('goal-now'));
    expect(now.flagsCollection.isButton, isTrue);
    final today = goalStripView(c).today;
    final bar = tester.widget<LinearProgressIndicator>(
      inSlot('today', find.byType(LinearProgressIndicator)),
    );
    expect(bar.semanticsLabel, contains(today.title));
    expect(bar.semanticsValue, '${(today.progress! * 100).floor()}%');
  });

  testWidgets('the strip at 360x640 and 2x text: no overflow, open or '
      'folded', (tester) async {
    c.state.faction(_p).credits = BigNum.parse('1e40');
    await pump(tester, size: const Size(360, 640), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(_key('goals-fold'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

/// A settings store that never answers a read.
final class _SilentStore implements SettingsStore {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String value) async {}
}

/// A settings store whose reads throw, as a broken platform channel would.
final class _ThrowingReads implements SettingsStore {
  @override
  Future<String?> read(String key) async => throw StateError('no prefs');

  @override
  Future<void> write(String key, String value) async {}
}
