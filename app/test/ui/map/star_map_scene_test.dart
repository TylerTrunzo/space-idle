import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

import 'map_fixtures.dart';

final Content content = loadEmbeddedContent();

StarMapScene _scene(GameState s) => buildStarMapScene(
  s,
  content,
  'player',
  buildFlowReport(s, content, 'player'),
);

MapBody _body(StarMapScene scene, String id) =>
    scene.bodies.singleWhere((b) => b.id == id);

void main() {
  late GameEngine engine;
  late GameState state;

  setUp(() {
    engine = GameEngine(content);
    state = engine.newGame(1);
  });

  group('MapLayout', () {
    test('angles come from an FNV-1a hash of the id, stable across runs', () {
      // Worked out independently: FNV-1a 32 of the code units, as a
      // fraction of a turn. String.hashCode is not stable across platforms.
      expect(MapLayout.angleFor('kora'), closeTo(4.543214234194602, 1e-12));
      expect(MapLayout.angleFor('cinder'), closeTo(4.807198933896955, 1e-12));
      expect(MapLayout.angleFor('kora'), MapLayout.angleFor('kora'));
    });

    test('orbit radius is base + orbit x gap', () {
      expect(
        MapLayout.orbitRadius(3) - MapLayout.orbitRadius(2),
        closeTo(MapLayout.orbitGap, 1e-12),
      );
      expect(MapLayout.orbitRadius(0), closeTo(MapLayout.orbitBase, 1e-12));
    });

    test('a body sits on its orbit at its angle', () {
      final p = MapLayout.positionFor('kora', 2);
      expect(p.distance, closeTo(MapLayout.orbitRadius(2), 1e-9));
      expect(p.direction, closeTo(_wrap(MapLayout.angleFor('kora')), 1e-9));
    });
  });

  group('buildStarMapScene', () {
    test('has the visible bodies only, in body order', () {
      expect(_scene(state).bodies.map((b) => b.id), [
        'cinder',
        'kora',
        'hollow_reach',
        'vastmere',
        'brine',
      ]);
    });

    test('a surveyed hidden body appears', () {
      state.body('tessaly').surveyed = true;
      expect(_scene(state).bodies.map((b) => b.id), contains('tessaly'));
    });

    test('marks ownership and colors by body type', () {
      final scene = _scene(state);
      expect(_body(scene, 'kora').owned, isTrue);
      expect(_body(scene, 'cinder').owned, isFalse);
      expect(_body(scene, 'kora').color, BodyPalette.forType('rocky'));
      expect(BodyPalette.forType('rocky'), const Color(0xFFB08968));
      expect(BodyPalette.forType('asteroid_belt'), const Color(0xFF8A7A6A));
      expect(BodyPalette.forType('ice_moon'), const Color(0xFF9FE8FF));
      expect(BodyPalette.forType('gas_giant'), const Color(0xFFC56CFF));
      expect(BodyPalette.forType('volcanic'), const Color(0xFFFF8A5B));
      // Unowned bodies are dimmed.
      expect(
        _body(scene, 'cinder').color.a,
        lessThan(BodyPalette.forType('volcanic').a),
      );
      expect(
        _body(scene, 'vastmere').radius,
        greaterThan(_body(scene, 'hollow_reach').radius),
      );
    });

    test('flags a body that appears in a grouped bottleneck', () {
      engine.advance(state, 3600);
      final flow = buildFlowReport(state, content, 'player');
      final badged = {
        for (final b in flow.groupedBottlenecks)
          if (b.bodyId != null) b.bodyId!,
      };
      expect(badged, isNotEmpty, reason: 'fixture should hold a body back');

      final scene = buildStarMapScene(state, content, 'player', flow);
      for (final b in scene.bodies) {
        expect(b.bottleneck, badged.contains(b.id), reason: b.id);
      }
    });

    test('draws routes and places shipments by elapsed fraction', () {
      addRouteAndShipment(state, departIn: -25, tripSeconds: 100);
      final scene = _scene(state);

      expect(scene.routes, hasLength(1));
      final route = scene.routes.single;
      expect(route.curve.from, _body(scene, 'kora').position);
      expect(route.curve.to, _body(scene, 'hollow_reach').position);
      final ship = scene.shipments.single;
      expect(ship.progress, closeTo(0.25, 1e-9));
      expect(ship.progressPerSecond, closeTo(0.01, 1e-12));
      expect(ship.curve, route.curve);
    });

    test('a shipment past its arrival is clamped to the destination', () {
      addRouteAndShipment(state, departIn: -150, tripSeconds: 100);
      expect(_scene(state).shipments.single.progress, 1);
    });

    test('a route curve bends off the straight line, and back again', () {
      const curve = MapCurve.between(Offset(0, 0), Offset(4, 0));
      expect(curve.at(0), const Offset(0, 0));
      expect(curve.at(1), const Offset(4, 0));
      expect(curve.at(0.5).dx, closeTo(2, 1e-9));
      expect(curve.at(0.5).dy.abs(), greaterThan(0.1));
      // The way back bends to the other side, so both directions show.
      const back = MapCurve.between(Offset(4, 0), Offset(0, 0));
      expect(back.at(0.5).dy.sign, -curve.at(0.5).dy.sign);
    });

    test('shows a progress arc for a running claim', () {
      state.projects.add(
        ProjectState(
          id: 'p1',
          factionId: 'player',
          kind: ProjectKind.claim,
          targetId: 'cinder',
          startedAt: state.time - 300,
          finishAt: state.time + 900,
        ),
      );
      final scene = _scene(state);
      expect(_body(scene, 'cinder').projectProgress, closeTo(0.25, 1e-9));
      expect(_body(scene, 'kora').projectProgress, isNull);
    });

    test('has one signal per system with unsurveyed signals', () {
      final scene = _scene(state);
      final expected = unsurveyedSignals(state, content, 'player', 'veyra');
      expect(expected, greaterThan(0));
      expect(scene.signals.single.systemId, 'veyra');
      expect(scene.signals.single.count, expected);
      // Outside every visible orbit, inside the fitted extent.
      final outer = scene.bodies
          .map((b) => b.position.distance)
          .reduce(math.max);
      expect(scene.signals.single.position.distance, greaterThan(outer));
      expect(scene.signals.single.position.distance, lessThan(scene.extent));
    });

    test('no signal once every hidden body is surveyed', () {
      state.body('tessaly').surveyed = true;
      state.body('dusk_cairn').surveyed = true;
      expect(_scene(state).signals, isEmpty);
    });

    test('equal states give equal scenes', () {
      expect(_scene(state), _scene(state));
      expect(_scene(state).hashCode, _scene(state).hashCode);
    });
  });

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
      final scene = _scene(state);
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

double _wrap(double a) {
  final w = a % (2 * math.pi);
  return w > math.pi ? w - 2 * math.pi : w;
}
