import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/map_transform.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

final Content content = loadEmbeddedContent();

void main() {
  late GameState state;

  setUp(() => state = GameEngine(content).newGame(1));

  group('MapTransform and hit testing', () {
    const size = Size(400, 300);

    test('toLogical is the inverse of toCanvas', () {
      final t = MapTransform.fit(size, 10);
      const p = Offset(3.25, -7.5);
      final back = t.toLogical(t.toCanvas(p));
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
      expect(t.toCanvas(Offset.zero), const Offset(200, 150));
      expect(t.scale, 15); // 300 / (2 x 10)
    });

    // Scale 15 px a unit: a 0.5 body is 7.5 px, a 3 body 45 px.
    final t = MapTransform.fit(size, 10);
    final small = _synthetic(radius: 0.5);
    final at = t.toCanvas(Offset.zero);

    test('the tap radius is at least 24 px', () {
      expect(
        hitTestMap(small, t, at + const Offset(20, 0)),
        const BodyHit('a'),
      );
      expect(
        hitTestMap(small, t, at + const Offset(0, 23)),
        const BodyHit('a'),
      );
      expect(hitTestMap(small, t, at + const Offset(30, 0)), isNull);
    });

    test('a big body is hit up to its radius plus 8 px', () {
      final big = _synthetic(radius: 3);
      expect(hitTestMap(big, t, at + const Offset(52, 0)), const BodyHit('a'));
      expect(hitTestMap(big, t, at + const Offset(54, 0)), isNull);
    });

    test('the radii are screen px: at zoom 0.5 they double in canvas px', () {
      expect(
        hitTestMap(small, t, at + const Offset(30, 0), zoom: 0.5),
        const BodyHit('a'),
      );
      expect(hitTestMap(small, t, at + const Offset(50, 0), zoom: 0.5), isNull);
    });

    test('the nearest of two overlapping targets wins', () {
      // Body b is two units (30 px) from body a.
      final two = _synthetic(radius: 0.5, second: const Offset(2, 0));
      expect(hitTestMap(two, t, at + const Offset(22, 0)), const BodyHit('b'));
      expect(hitTestMap(two, t, at + const Offset(8, 0)), const BodyHit('a'));
    });

    test('a tap on the signal marker hits the signal', () {
      final scene = buildStarMapScene(
        state,
        content,
        'player',
        buildFlowReport(state, content, 'player'),
      );
      final ft = MapTransform.fit(size, scene.extent);
      final marker = ft.toCanvas(scene.signals.single.position);
      expect(hitTestMap(scene, ft, marker), const SignalHit('veyra'));
    });
  });
}

/// A scene with body `a` at the star's place and, given [second], body `b`.
StarMapScene _synthetic({required double radius, Offset? second}) {
  MapBody body(String id, Offset at) => MapBody(
    id: id,
    name: id,
    position: at,
    radius: radius,
    color: BodyPalette.forType('rocky'),
    owned: true,
    bottleneck: false,
    projectProgress: null,
  );
  return StarMapScene(
    starRadius: 0,
    orbitRadii: const [],
    bodies: [body('a', Offset.zero), if (second != null) body('b', second)],
    routes: const [],
    shipments: const [],
    signals: const [],
    extent: 10,
  );
}
