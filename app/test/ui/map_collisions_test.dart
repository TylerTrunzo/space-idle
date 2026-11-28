import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/map/star_map_painter.dart';
import 'package:space_idle/ui/shell.dart';

/// The real app at [size], after start().
Future<GameController> _boot(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SpaceIdleApp(
      store: MemorySaveStore(),
      clock: FakeClock(DateTime.utc(2026, 11, 27)),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ControllerScope.of(tester.element(find.byType(Shell)));
}

/// Every overlap on the map as drawn: disc on disc, and a label on
/// another label, the star, a disc, a signal marker or off the map.
List<String> _collisions(WidgetTester tester) {
  final paint = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is StarMapPainter,
  );
  final painter = tester.widget<CustomPaint>(paint).painter! as StarMapPainter;
  final t = painter.transform;
  final origin = tester.getTopLeft(paint);
  final canvas = tester.getRect(paint);
  Rect circle(Offset at, double r) =>
      Rect.fromCircle(center: origin + t.toCanvas(at), radius: r * t.scale);
  final star = circle(Offset.zero, painter.scene.starRadius);
  final bodies = painter.scene.bodies;
  final labels = {
    for (final b in bodies)
      b.id: tester.getRect(find.byKey(ValueKey('label-${b.id}'))),
  };
  final signals = [
    for (final s in painter.scene.signals)
      Rect.fromCircle(center: origin + t.toCanvas(s.position), radius: 14),
  ];
  final out = <String>[];
  for (final (i, a) in bodies.indexed) {
    final label = labels[a.id]!;
    for (final b in bodies.skip(i + 1)) {
      final gap =
          (t.toCanvas(a.position) - t.toCanvas(b.position)).distance -
          (a.radius + b.radius) * t.scale;
      if (gap <= 0) out.add('disc ${a.id} on disc ${b.id}');
      if (label.overlaps(labels[b.id]!)) out.add('label ${a.id} on ${b.id}');
    }
    if (label.overlaps(star)) out.add('label ${a.id} on the star');
    if (canvas.expandToInclude(label) != canvas) {
      out.add('label ${a.id} off the map');
    }
    for (final o in bodies) {
      if (label.overlaps(circle(o.position, o.radius))) {
        out.add('label ${a.id} on disc ${o.id}');
      }
    }
    for (final s in signals) {
      if (label.overlaps(s)) out.add('label ${a.id} on a signal');
    }
  }
  return out;
}

void main() {
  for (final size in const [Size(412, 915), Size(1280, 800), Size(360, 640)]) {
    final at = '${size.width.round()}x${size.height.round()}';

    testWidgets('$at, new game (5 bodies and a signal): nothing collides', (
      tester,
    ) async {
      await _boot(tester, size);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is StarMapPainter,
                    ),
                  )
                  .painter!
              as StarMapPainter;
      expect(painter.scene.bodies, hasLength(5));
      expect(painter.scene.signals, hasLength(1));
      expect(_collisions(tester), isEmpty);
    });

    testWidgets('$at, every body surveyed: nothing collides', (tester) async {
      final c = await _boot(tester, size);
      c.state.body('tessaly').surveyed = true;
      c.state.body('dusk_cairn').surveyed = true;
      c.tickSeconds(1);
      await tester.pump();
      expect(_collisions(tester), isEmpty);
    });
  }
}
