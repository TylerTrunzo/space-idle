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

void main() {
  testWidgets('hidden bodies have no node until surveyed', (tester) async {
    final handle = tester.ensureSemantics();
    final c = _controller();
    await tester.pumpWidget(_app(c));

    expect(find.bySemanticsLabel(RegExp('^Tessaly')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Dusk Cairn')), findsNothing);

    c.state.body('tessaly').surveyed = true;
    c.tickSeconds(1); // any change notifies the map
    await tester.pump();
    expect(find.bySemanticsLabel('Tessaly, unclaimed'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('all 5 visible bodies have labelled button nodes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
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
    handle.dispose();
  });

  testWidgets('tapping Kora calls onSelect(kora)', (tester) async {
    final handle = tester.ensureSemantics();
    final selected = <String>[];
    await tester.pumpWidget(_app(_controller(), selected: selected));

    await tester.tap(find.bySemanticsLabel('Kora, owned'));
    expect(selected, ['kora']);
    handle.dispose();
  });

  testWidgets('the semantics tap action selects the body too', (tester) async {
    final handle = tester.ensureSemantics();
    final selected = <String>[];
    await tester.pumpWidget(_app(_controller(), selected: selected));

    tester.semantics.tap(find.semantics.byLabel('Cinder, unclaimed'));
    expect(selected, ['cinder']);
    handle.dispose();
  });

  testWidgets('tapping the signal marker calls onSignalTap', (tester) async {
    final handle = tester.ensureSemantics();
    final signals = <String>[];
    await tester.pumpWidget(_app(_controller(), signals: signals));

    await tester.tap(find.bySemanticsLabel(RegExp('^Unsurveyed signal')));
    expect(signals, ['veyra']);
    handle.dispose();
  });

  testWidgets('a body stays where it was across two builds', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_controller()));
    final first = tester.getCenter(find.bySemanticsLabel('Kora, owned'));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(_controller()));
    final second = tester.getCenter(find.bySemanticsLabel('Kora, owned'));
    expect(second, first);
    handle.dispose();
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

  test('the painter paints a route, a shipment, a badge, an arc and a '
      'signal straight onto a canvas', () {
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
    final scene = buildStarMapScene(
      state,
      content,
      'player',
      buildFlowReport(state, content, 'player'),
    );
    expect(scene.shipments, isNotEmpty);
    expect(scene.bodies.any((b) => b.bottleneck), isTrue);
    const size = Size(360, 640);
    final motion = MapMotion()..update(sinceTick: 0.5, pulse: 0.3);
    final painter = StarMapPainter(
      scene: scene,
      transform: MapTransform.fit(size, scene.extent),
      motion: motion,
      selectedId: 'kora',
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    recorder.endRecording().dispose();

    expect(
      painter.shouldRepaint(
        StarMapPainter(
          scene: scene,
          transform: MapTransform.fit(size, scene.extent),
          motion: motion,
          selectedId: 'kora',
        ),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        StarMapPainter(
          scene: scene,
          transform: MapTransform.fit(size, scene.extent),
          motion: motion,
          selectedId: 'cinder',
        ),
      ),
      isTrue,
    );
  });
}
