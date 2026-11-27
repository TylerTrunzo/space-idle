import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';

/// Where things sit on the star map, in logical map units centred on the
/// star (one unit is the gap between neighbouring orbits).
abstract final class MapLayout {
  /// Radius of orbit 0.
  static const double orbitBase = 1.5;

  /// Radius added per orbit index.
  static const double orbitGap = 1;

  /// Room left past the outermost visible orbit, for labels and signals.
  static const double margin = 1.8;

  /// How far past the outermost orbit a system's signal marker sits.
  static const double signalOffset = 1;

  /// The star's radius.
  static const double starRadius = 0.8;

  /// Angle in radians, `[0, 2π)`, at which [id] sits on its orbit.
  ///
  /// An FNV-1a hash of the id's code units, so it is the same on every
  /// launch and platform (`String.hashCode` is not). The multiply is split
  /// so every step stays exact in a web double.
  static double angleFor(String id) {
    var h = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      h ^= unit;
      // h × 16777619 = h × 2^24 + h × 403, mod 2^32.
      h = ((h & 0xff) * 0x1000000 + h * 403) & 0xffffffff;
    }
    return h / 0x100000000 * 2 * math.pi;
  }

  /// Radius of orbit [orbit]: `orbitBase + orbit × orbitGap`.
  static double orbitRadius(int orbit) => orbitBase + orbit * orbitGap;

  /// Least gap between two bodies' discs, in map units.
  static const double minClearance = 0.5;

  /// The golden angle: successive bodies stepped by it never bunch up.
  static const double _goldenAngle = 2.399963229728653;

  /// Nudge tried when a body would sit too close to one placed before it.
  static const double _nudge = math.pi / 36;

  /// Where each of [bodies] (one system's, hidden ones included) sits,
  /// by id, in content order.
  ///
  /// Inner orbits first, each body steps on by the golden angle from a
  /// base hashed from [systemId], so the system fills the circle round
  /// the star instead of one side. A body that would come within
  /// [minClearance] of one placed before it is nudged on until clear.
  /// Deterministic, and placed over every body of the system, so a
  /// survey that reveals one moves no other.
  static Map<String, Offset> placeSystem(
    String systemId,
    List<BodyState> bodies,
  ) {
    final order = [...bodies]..sort((a, b) => a.orbit.compareTo(b.orbit));
    final placed = <String, Offset>{};
    final radius = <String, double>{};
    var angle = angleFor(systemId);
    for (final b in order) {
      final r = bodyRadius(b.typeId);
      var at = Offset.fromDirection(angle, orbitRadius(b.orbit));
      for (
        var tries = 0;
        tries < 72 && _crowded(at, r, placed, radius);
        tries++
      ) {
        angle += _nudge;
        at = Offset.fromDirection(angle, orbitRadius(b.orbit));
      }
      placed[b.id] = at;
      radius[b.id] = r;
      angle += _goldenAngle;
    }
    return {for (final b in bodies) b.id: placed[b.id]!};
  }

  static bool _crowded(
    Offset at,
    double r,
    Map<String, Offset> placed,
    Map<String, double> radius,
  ) {
    for (final MapEntry(key: id, value: p) in placed.entries) {
      if ((p - at).distance < r + radius[id]! + minClearance) return true;
    }
    return false;
  }

  /// A body's drawn radius by type: gas giants largest, belts smallest.
  static double bodyRadius(String typeId) => switch (typeId) {
    'gas_giant' => 0.9,
    'rocky' => 0.6,
    'volcanic' => 0.55,
    'ice_moon' => 0.45,
    _ => 0.4,
  };
}

/// A route's bend: a quadratic curve from [from] to [to], bowed to the
/// left of its direction, so the way back bows the other way and both
/// directions of a pair of routes show.
@immutable
final class MapCurve {
  /// The curve between two points; its [control] is worked out once here.
  MapCurve.between(this.from, this.to) : control = _controlFor(from, to);

  /// Share of the chord length the curve bows out at its control point.
  static const double bend = 0.2;

  /// Start, in map units.
  final Offset from;

  /// End, in map units.
  final Offset to;

  /// The control point: the chord's midpoint pushed off to the left.
  final Offset control;

  static Offset _controlFor(Offset from, Offset to) {
    final d = to - from;
    return (from + to) / 2 + Offset(-d.dy, d.dx) * bend;
  }

  /// The point a fraction [t] (0 to 1) of the way along.
  Offset at(double t) {
    final mt = 1 - t;
    return from * (mt * mt) + control * (2 * mt * t) + to * (t * t);
  }

  @override
  bool operator ==(Object other) =>
      other is MapCurve && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// One visible body as the map draws it.
@immutable
final class MapBody {
  /// Creates a body.
  const MapBody({
    required this.id,
    required this.name,
    required this.position,
    required this.radius,
    required this.color,
    required this.owned,
    required this.bottleneck,
    required this.projectProgress,
    this.projectKind,
  });

  /// Body id.
  final String id;

  /// Display name.
  final String name;

  /// Centre, in map units.
  final Offset position;

  /// Drawn radius, in map units.
  final double radius;

  /// Fill: its type's color, dimmed when the player does not own it.
  final Color color;

  /// Whether the player owns it.
  final bool owned;

  /// Whether a player bottleneck names it (the amber `!` badge).
  final bool bottleneck;

  /// How far a claim or slot expansion on it has come, 0 to 1; null when
  /// none is under way.
  final double? projectProgress;

  /// Which project [projectProgress] is for.
  final ProjectKind? projectKind;

  @override
  bool operator ==(Object other) =>
      other is MapBody &&
      other.id == id &&
      other.name == name &&
      other.position == position &&
      other.radius == radius &&
      other.color == color &&
      other.owned == owned &&
      other.bottleneck == bottleneck &&
      other.projectProgress == projectProgress &&
      other.projectKind == projectKind;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    position,
    radius,
    color,
    owned,
    bottleneck,
    projectProgress,
    projectKind,
  );
}

/// A player route, drawn as a curve.
@immutable
final class MapRoute {
  /// Creates a route.
  const MapRoute(this.curve);

  /// Its path on the map.
  final MapCurve curve;

  @override
  bool operator ==(Object other) => other is MapRoute && other.curve == curve;

  @override
  int get hashCode => curve.hashCode;
}

/// A player shipment in flight: a dot along its route's curve.
@immutable
final class MapShipment {
  /// Creates a shipment.
  const MapShipment(this.curve, this.progress, this.progressPerSecond);

  /// The curve it travels.
  final MapCurve curve;

  /// Fraction of the trip done at the state's time, 0 to 1.
  final double progress;

  /// Fraction of the trip a game second covers, so the painter can move it
  /// on between ticks.
  final double progressPerSecond;

  @override
  bool operator ==(Object other) =>
      other is MapShipment &&
      other.curve == curve &&
      other.progress == progress &&
      other.progressPerSecond == progressPerSecond;

  @override
  int get hashCode => Object.hash(curve, progress, progressPerSecond);
}

/// A system's unsurveyed-signal marker, near its edge.
@immutable
final class MapSignal {
  /// Creates a marker.
  const MapSignal(this.systemId, this.position, this.count);

  /// System id.
  final String systemId;

  /// Centre, in map units.
  final Offset position;

  /// Unsurveyed signals there, above zero.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is MapSignal &&
      other.systemId == systemId &&
      other.position == position &&
      other.count == count;

  @override
  int get hashCode => Object.hash(systemId, position, count);
}

/// Everything the star map draws, in map units: the painter's whole input.
@immutable
final class StarMapScene {
  /// Creates a scene; the lists are kept as given.
  const StarMapScene({
    required this.starRadius,
    required this.orbitRadii,
    required this.bodies,
    required this.routes,
    required this.shipments,
    required this.signals,
    required this.extent,
  });

  /// The star's radius, at the origin.
  final double starRadius;

  /// Radii of the visible bodies' orbits, inner first, for faint rings.
  final List<double> orbitRadii;

  /// Visible bodies, in body order.
  final List<MapBody> bodies;

  /// Player routes between visible bodies.
  final List<MapRoute> routes;

  /// Player shipments in flight between visible bodies.
  final List<MapShipment> shipments;

  /// Signal markers, one per system with unsurveyed signals.
  final List<MapSignal> signals;

  /// Radius around the star the map fits to the screen.
  final double extent;

  /// Radius around a signal marker the map keeps in view, in map units.
  static const double signalMargin = 0.6;

  /// What the map draws, in map units: the star, every body's disc and
  /// every signal marker. The map is fitted to it, labels getting their
  /// room from the fit's padding.
  Rect get bounds {
    var r = Rect.fromCircle(center: Offset.zero, radius: starRadius);
    for (final b in bodies) {
      r = r.expandToInclude(
        Rect.fromCircle(center: b.position, radius: b.radius),
      );
    }
    for (final s in signals) {
      r = r.expandToInclude(
        Rect.fromCircle(center: s.position, radius: signalMargin),
      );
    }
    return r;
  }

  /// Whether [other] draws the same static layer: star, orbits, bodies,
  /// routes, signal markers and extent, whatever its shipments.
  bool sameStaticLayer(StarMapScene other) =>
      other.starRadius == starRadius &&
      other.extent == extent &&
      listEquals(other.orbitRadii, orbitRadii) &&
      listEquals(other.bodies, bodies) &&
      listEquals(other.routes, routes) &&
      listEquals(other.signals, signals);

  @override
  bool operator ==(Object other) =>
      other is StarMapScene &&
      other.starRadius == starRadius &&
      other.extent == extent &&
      listEquals(other.orbitRadii, orbitRadii) &&
      listEquals(other.bodies, bodies) &&
      listEquals(other.routes, routes) &&
      listEquals(other.shipments, shipments) &&
      listEquals(other.signals, signals);

  @override
  int get hashCode => Object.hash(
    starRadius,
    extent,
    Object.hashAll(orbitRadii),
    Object.hashAll(bodies),
    Object.hashAll(routes),
    Object.hashAll(shipments),
    Object.hashAll(signals),
  );
}

/// Alpha an unowned body's color keeps.
const double _unownedAlpha = 0.45;

/// Projects drawn as an arc around their target body.
const Set<ProjectKind> _bodyProjects = {
  ProjectKind.claim,
  ProjectKind.expandSlots,
};

/// Builds the map of [playerId]'s home system from [s], read-only.
///
/// Only bodies the player can see are included; [flow]'s grouped
/// bottlenecks decide the badges.
StarMapScene buildStarMapScene(
  GameState s,
  Content c,
  String playerId,
  FlowReport flow,
) {
  final homeId = c.galaxy.factions
      .firstWhere((f) => f.id == playerId)
      .homeBodyId;
  final systemId = s.body(homeId).systemId;
  final visible = [
    for (final b in s.bodies)
      if (b.systemId == systemId && isVisible(s, b, playerId)) b,
  ];
  final badged = {for (final b in flow.groupedBottlenecks) ?b.bodyId};
  // Soonest to finish first, so a body shows its nearest project.
  final projects = <String, ProjectState>{};
  for (final p in runningProjects(s, playerId)) {
    if (_bodyProjects.contains(p.kind)) {
      projects.putIfAbsent(p.targetId, () => p);
    }
  }

  // Placed over the whole system, hidden bodies too, so revealing one
  // moves nothing.
  final placed = MapLayout.placeSystem(systemId, [
    for (final b in s.bodies)
      if (b.systemId == systemId) b,
  ]);
  final positions = <String, Offset>{};
  final bodies = <MapBody>[];
  for (final b in visible) {
    final at = positions[b.id] = placed[b.id]!;
    final owned = b.ownerId == playerId;
    final base = BodyPalette.forType(b.typeId);
    final project = projects[b.id];
    bodies.add(
      MapBody(
        id: b.id,
        name: b.name,
        position: at,
        radius: MapLayout.bodyRadius(b.typeId),
        color: owned ? base : base.withValues(alpha: _unownedAlpha),
        owned: owned,
        bottleneck: badged.contains(b.id),
        projectProgress: project == null ? null : _fraction(s.time, project),
        projectKind: project?.kind,
      ),
    );
  }

  final orbits = {for (final b in visible) b.orbit}.toList()..sort();
  final outer = orbits.isEmpty ? 0.0 : MapLayout.orbitRadius(orbits.last);

  final routes = [
    for (final r in s.routes)
      if (r.ownerId == playerId)
        if ((positions[r.fromBodyId], positions[r.toBodyId]) case (
          final from?,
          final to?,
        ))
          MapRoute(MapCurve.between(from, to)),
  ];
  final shipments = [
    for (final sh in s.shipments)
      if (sh.ownerId == playerId)
        if ((positions[sh.fromBodyId], positions[sh.toBodyId]) case (
          final from?,
          final to?,
        ))
          _shipment(s.time, sh, MapCurve.between(from, to)),
  ];

  final count = unsurveyedSignals(s, c, playerId, systemId);
  final signals = [
    if (count > 0)
      MapSignal(
        systemId,
        Offset.fromDirection(
          MapLayout.angleFor(systemId),
          outer + MapLayout.signalOffset,
        ),
        count,
      ),
  ];

  return StarMapScene(
    starRadius: MapLayout.starRadius,
    orbitRadii: [for (final o in orbits) MapLayout.orbitRadius(o)],
    bodies: bodies,
    routes: routes,
    shipments: shipments,
    signals: signals,
    extent: outer + MapLayout.margin,
  );
}

double _fraction(double now, ProjectState p) {
  final span = p.finishAt - p.startedAt;
  if (span <= 0) return 1;
  return ((now - p.startedAt) / span).clamp(0.0, 1.0);
}

MapShipment _shipment(double now, Shipment sh, MapCurve curve) {
  final trip = sh.arriveAt - sh.departAt;
  if (trip <= 0) return MapShipment(curve, 1, 0);
  return MapShipment(
    curve,
    ((now - sh.departAt) / trip).clamp(0.0, 1.0),
    1 / trip,
  );
}
