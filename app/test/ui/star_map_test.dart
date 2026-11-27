import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/star_map.dart';
import 'package:space_idle/ui/map/star_map_painter.dart';
import 'package:space_idle/ui/map/map_transform.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

import 'map/map_fixtures.dart';

final Content content = loadEmbeddedContent();

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

/// The map in an app shell; taps and signal taps are recorded.
Widget _app(
  GameController c, {
  List<String>? selected,
  List<String>? signals,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: buildTheme(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: disableAnimations),
      child: Scaffold(
        body: StarMap(
          controller: c,
          onSelect: (id) => selected?.add(id),
          onSignalTap: (id) => signals?.add(id),
        ),
      ),
    ),
  ),
);

/// Where the map currently draws the first shipment: its trip fraction at
/// the last tick plus the in-between motion since, as the painter computes.
double _shipmentProgress(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter is MapMotionPainter &&
          (w.painter! as MapMotionPainter).scene.shipments.isNotEmpty,
    ),
  );
  final painter = paint.painter! as MapMotionPainter;
  final ship = painter.scene.shipments.first;
  return ship.progress + ship.progressPerSecond * painter.motion.sinceTick;
}

void main() {
  testWidgets('hidden bodies have no node until surveyed', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_app(c));

    expect(find.bySemanticsLabel(RegExp('^Tessaly')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Dusk Cairn')), findsNothing);

    c.state.body('tessaly').surveyed = true;
    c.tickSeconds(1); // any change notifies the map
    await tester.pump();
    expect(find.bySemanticsLabel('Tessaly, unclaimed'), findsOneWidget);
  });

  testWidgets('all 5 visible bodies have labelled button nodes', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_controller()));

    for (final label in [
      'Cinder, unclaimed',
      'Kora, owned',
      'Hollow Reach, unclaimed',
      'Vastmere, unclaimed',
      'Brine, unclaimed',
    ]) {
      final node = find.bySemanticsLabel(label);
      expect(node, findsOneWidget, reason: label);
      expect(
        tester.getSemantics(node).flagsCollection.isButton,
        isTrue,
        reason: label,
      );
    }
    // The visible labels say so too, not only the ring color.
    expect(find.text('Unclaimed'), findsNWidgets(4));
  });

  testWidgets('tapping Kora calls onSelect(kora)', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_app(_controller(), selected: selected));

    await tester.tap(find.bySemanticsLabel('Kora, owned'));
    expect(selected, ['kora']);
  });

  testWidgets('the semantics tap action selects the body too', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(_app(_controller(), selected: selected));

    tester.semantics.tap(find.semantics.byLabel('Cinder, unclaimed'));
    expect(selected, ['cinder']);
  });

  testWidgets('tapping the signal marker calls onSignalTap', (tester) async {
    final signals = <String>[];
    await tester.pumpWidget(_app(_controller(), signals: signals));

    await tester.tap(find.bySemanticsLabel(RegExp('^Unsurveyed signal')));
    expect(signals, ['veyra']);
  });

  testWidgets('a body stays where it was across two builds', (tester) async {
    await tester.pumpWidget(_app(_controller()));
    final first = tester.getCenter(find.bySemanticsLabel('Kora, owned'));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(_controller()));
    final second = tester.getCenter(find.bySemanticsLabel('Kora, owned'));
    expect(second, first);
  });

  testWidgets('paints a route and a moving shipment without errors', (
    tester,
  ) async {
    final c = _controller();
    addRouteAndShipment(c.state, departIn: -25, tripSeconds: 100);
    c.tickSeconds(1);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    // Shipments move between ticks: the ticker keeps frames coming.
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('a command between ticks does not pull a shipment back', (
    tester,
  ) async {
    final c = _controller();
    addRouteAndShipment(c.state, departIn: -25, tripSeconds: 100);
    await tester.pumpWidget(_app(c));
    c.tickSeconds(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final before = _shipmentProgress(tester);
    expect(before, greaterThan(0.26 + 0.004), reason: 'moved since the tick');

    // A failed command notifies but does not advance game time.
    c.run(const BuildCommand('player', 'kora', 'fusion_refinery'));
    expect(c.lastError, isNotNull);
    await tester.pump();
    expect(_shipmentProgress(tester), greaterThanOrEqualTo(before));
  });

  testWidgets('an idle map schedules no frames', (tester) async {
    // No shipments, every body surveyed (no signal), no project running.
    final c = _controller();
    c.state.body('tessaly').surveyed = true;
    c.state.body('dusk_cairn').surveyed = true;
    expect(c.state.shipments, isEmpty);
    expect(c.state.projects, isEmpty);

    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('turning animations off while running stops the ticker', (
    tester,
  ) async {
    final c = _controller();
    addRouteAndShipment(c.state, departIn: -25, tripSeconds: 100);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(_app(c, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('with animations off nothing moves between ticks', (
    tester,
  ) async {
    final c = _controller();
    addRouteAndShipment(c.state, departIn: -25, tripSeconds: 100);
    await tester.pumpWidget(_app(c, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('renders on a 360x640 phone at 2.0 text scale without errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final selected = <String>[];

    await tester.pumpWidget(_app(_controller(), selected: selected));
    expect(tester.takeException(), isNull);
    await tester.tap(find.bySemanticsLabel('Kora, owned'));
    expect(selected, ['kora']);
  });

  testWidgets('the map is in a zoomable viewer from 0.5 to 3', (tester) async {
    await tester.pumpWidget(_app(_controller()));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 0.5);
    expect(viewer.maxScale, 3);
  });

  testWidgets('a pinch zooms out to 0.5x, where a tap still selects', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(_app(_controller(), selected: selected));
    final viewer = find.byType(InteractiveViewer);
    final zoom = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;

    final center = tester.getCenter(viewer);
    final a = await tester.startGesture(center + const Offset(-200, 0));
    final b = await tester.startGesture(
      center + const Offset(200, 0),
      pointer: 2,
    );
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(center + Offset(-200 + 18.0 * i, 0));
      await b.moveTo(center + Offset(200 - 18.0 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 1));

    expect(zoom.value.getMaxScaleOnAxis(), closeTo(0.5, 0.01));

    // Kora's node moved with the zoom; a tap on it still selects Kora. The
    // node takes no pointer events itself (the canvas gesture does), hence
    // warnIfMissed: false.
    await tester.tap(find.bySemanticsLabel('Kora, owned'), warnIfMissed: false);
    expect(selected, ['kora']);
  });

  group('painters', () {
    const size = Size(360, 640);
    late StarMapScene scene;
    late MapTransform t;

    StarMapScene build(GameState state) => buildStarMapScene(
      state,
      content,
      'player',
      buildFlowReport(state, content, 'player'),
    );

    setUp(() {
      final state = GameEngine(content).newGame(1);
      // An hour in, Kora's stores are full: a bottleneck badge.
      GameEngine(content).advance(state, 3600);
      addRouteAndShipment(state, departIn: -25, tripSeconds: 100);
      state.projects.add(
        ProjectState(
          id: 'p1',
          factionId: 'player',
          kind: ProjectKind.claim,
          targetId: 'cinder',
          startedAt: state.time - 10,
          finishAt: state.time + 10,
        ),
      );
      scene = build(state);
      t = MapTransform.fit(size, scene.extent);
    });

    test('both layers paint a route, a shipment, a badge, an arc and a '
        'signal straight onto a canvas', () {
      expect(scene.shipments, isNotEmpty);
      expect(scene.signals, isNotEmpty);
      expect(scene.bodies.any((b) => b.bottleneck), isTrue);
      final motion = MapMotion()..update(sinceTick: 0.5, pulse: 0.3);
      addTearDown(motion.dispose);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      StarMapPainter(
        scene: scene,
        transform: t,
        selectedId: 'kora',
      ).paint(canvas, size);
      MapMotionPainter(
        scene: scene,
        transform: t,
        motion: motion,
      ).paint(canvas, size);
      recorder.endRecording().dispose();
    });

    test(
      'the static layer repaints on a new selection, not on equal input',
      () {
        final painter = StarMapPainter(
          scene: scene,
          transform: t,
          selectedId: 'kora',
        );
        expect(
          painter.shouldRepaint(
            StarMapPainter(scene: scene, transform: t, selectedId: 'kora'),
          ),
          isFalse,
        );
        expect(
          painter.shouldRepaint(
            StarMapPainter(scene: scene, transform: t, selectedId: 'cinder'),
          ),
          isTrue,
        );
      },
    );

    test('shipments moving on repaint only the moving layer', () {
      final moved = StarMapScene(
        starRadius: scene.starRadius,
        orbitRadii: scene.orbitRadii,
        bodies: scene.bodies,
        routes: scene.routes,
        shipments: [
          for (final s in scene.shipments)
            MapShipment(s.curve, s.progress + 0.01, s.progressPerSecond),
        ],
        signals: scene.signals,
        extent: scene.extent,
      );
      expect(
        StarMapPainter(
          scene: scene,
          transform: t,
        ).shouldRepaint(StarMapPainter(scene: moved, transform: t)),
        isFalse,
      );
      final motion = MapMotion();
      addTearDown(motion.dispose);
      expect(
        MapMotionPainter(
          scene: scene,
          transform: t,
          motion: motion,
        ).shouldRepaint(
          MapMotionPainter(scene: moved, transform: t, motion: motion),
        ),
        isTrue,
      );
    });
  });

  testWidgets('the static and moving layers each have a RepaintBoundary', (
    tester,
  ) async {
    final c = _controller();
    addRouteAndShipment(c.state, departIn: -25, tripSeconds: 100);
    await tester.pumpWidget(_app(c));

    Finder layer<T>() =>
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is T);
    RepaintBoundary boundaryOf(Finder f) => tester.widget<RepaintBoundary>(
      find.ancestor(of: f, matching: find.byType(RepaintBoundary)).first,
    );
    expect(layer<StarMapPainter>(), findsOneWidget);
    expect(layer<MapMotionPainter>(), findsOneWidget);
    expect(
      identical(
        boundaryOf(layer<StarMapPainter>()),
        boundaryOf(layer<MapMotionPainter>()),
      ),
      isFalse,
    );
  });
}
