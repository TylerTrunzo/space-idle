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

    test('each body sits on its orbit, the same on every call', () {
      final system = state.bodies.where((b) => b.systemId == 'veyra').toList();
      final first = MapLayout.placeSystem('veyra', system);
      final again = MapLayout.placeSystem('veyra', system);
      expect(first.keys, system.map((b) => b.id));
      for (final b in system) {
        expect(
          first[b.id]!.distance,
          closeTo(MapLayout.orbitRadius(b.orbit), 1e-9),
        );
        expect(again[b.id], first[b.id]);
      }
    });

    test('no two body discs intersect, hidden bodies included', () {
      final system = state.bodies.where((b) => b.systemId == 'veyra').toList();
      final at = MapLayout.placeSystem('veyra', system);
      for (final (i, a) in system.indexed) {
        for (final b in system.skip(i + 1)) {
          final gap =
              (at[a.id]! - at[b.id]!).distance -
              MapLayout.bodyRadius(a.typeId) -
              MapLayout.bodyRadius(b.typeId);
          expect(
            gap,
            greaterThanOrEqualTo(MapLayout.minClearance - 1e-9),
            reason: '${a.id} and ${b.id}',
          );
        }
      }
    });

    test('visible bodies spread around the star, not all in one half', () {
      final bodies = _scene(state).bodies.map((b) => b.position).toList();
      expect(bodies.any((p) => p.dy < 0), isTrue, reason: 'top half');
      expect(bodies.any((p) => p.dy > 0), isTrue, reason: 'bottom half');
      expect(bodies.any((p) => p.dx < 0), isTrue, reason: 'left half');
      expect(bodies.any((p) => p.dx > 0), isTrue, reason: 'right half');
    });

    test('revealing a hidden body moves no other body', () {
      final before = {for (final b in _scene(state).bodies) b.id: b.position};
      state.body('tessaly').surveyed = true;
      final after = {for (final b in _scene(state).bodies) b.id: b.position};
      for (final MapEntry(key: id, value: p) in before.entries) {
        expect(after[id], p, reason: id);
      }
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
      expect(BodyPalette.forType('kuiper'), const Color(0xFFA9B8D0));
      expect(BodyPalette.forType('no_such_type'), Palette.muted);
      expect(BodyPalette.star, const Color(0xFFFFD27A));
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
      final curve = MapCurve.between(Offset(0, 0), Offset(4, 0));
      expect(curve.at(0), const Offset(0, 0));
      expect(curve.at(1), const Offset(4, 0));
      expect(curve.at(0.5).dx, closeTo(2, 1e-9));
      expect(curve.at(0.5).dy.abs(), greaterThan(0.1));
      // The way back bends to the other side, so both directions show.
      final back = MapCurve.between(Offset(4, 0), Offset(0, 0));
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

    test('bounds hold the star, every disc and every signal marker', () {
      final scene = _scene(state);
      final b = scene.bounds;
      expect(b.contains(Offset.zero), isTrue);
      for (final body in scene.bodies) {
        final disc = Rect.fromCircle(
          center: body.position,
          radius: body.radius,
        );
        expect(b.expandToInclude(disc), b, reason: body.id);
      }
      for (final sig in scene.signals) {
        expect(b.contains(sig.position), isTrue);
      }
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
}
