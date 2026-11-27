import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

/// The one mapping between map units and canvas pixels, read by both the
/// painter and the hit test: the star at the canvas centre, the scene's
/// extent fitted to the shorter side.
@immutable
final class MapTransform {
  /// Creates a transform.
  const MapTransform(this.scale, this.origin);

  /// Fits a circle of radius [extent] map units into [size].
  factory MapTransform.fit(Size size, double extent) => MapTransform(
    math.min(size.width, size.height) / (2 * extent),
    size.center(Offset.zero),
  );

  /// Pixels per map unit.
  final double scale;

  /// The star's place on the canvas, in pixels.
  final Offset origin;

  /// Map units to canvas pixels.
  Offset toCanvas(Offset p) => origin + p * scale;

  /// Canvas pixels to map units; the exact inverse of [toCanvas].
  Offset toLogical(Offset p) => (p - origin) / scale;

  @override
  bool operator ==(Object other) =>
      other is MapTransform && other.scale == scale && other.origin == origin;

  @override
  int get hashCode => Object.hash(scale, origin);
}

/// What a tap on the map lands on.
sealed class MapHit {
  const MapHit();
}

/// A tap on a body.
final class BodyHit extends MapHit {
  /// Creates a hit.
  const BodyHit(this.bodyId);

  /// The body tapped.
  final String bodyId;

  @override
  bool operator ==(Object other) => other is BodyHit && other.bodyId == bodyId;

  @override
  int get hashCode => bodyId.hashCode;
}

/// A tap on a system's signal marker.
final class SignalHit extends MapHit {
  /// Creates a hit.
  const SignalHit(this.systemId);

  /// The system whose marker was tapped.
  final String systemId;

  @override
  bool operator ==(Object other) =>
      other is SignalHit && other.systemId == systemId;

  @override
  int get hashCode => systemId.hashCode;
}

/// Smallest tap radius, in screen pixels.
const double minTapRadius = 24;

/// Tap slop past a body's edge, in screen pixels.
const double tapSlop = 8;

/// Tap radius for a body of [radiusPx] canvas pixels at [zoom]: at least
/// [minTapRadius] and the body plus [tapSlop], both in screen pixels.
double tapRadiusPx(double radiusPx, {double zoom = 1}) =>
    math.max(minTapRadius / zoom, radiusPx + tapSlop / zoom);

/// What a tap at [canvasPx] (canvas pixels, before the viewer's [zoom])
/// lands on: the nearest body or signal marker within its tap radius, or
/// null.
MapHit? hitTestMap(
  StarMapScene scene,
  MapTransform t,
  Offset canvasPx, {
  double zoom = 1,
}) {
  MapHit? best;
  var bestDistance = double.infinity;
  for (final b in scene.bodies) {
    final d = (canvasPx - t.toCanvas(b.position)).distance;
    if (d <= tapRadiusPx(b.radius * t.scale, zoom: zoom) && d < bestDistance) {
      best = BodyHit(b.id);
      bestDistance = d;
    }
  }
  for (final sig in scene.signals) {
    final d = (canvasPx - t.toCanvas(sig.position)).distance;
    if (d <= tapRadiusPx(0, zoom: zoom) && d < bestDistance) {
      best = SignalHit(sig.systemId);
      bestDistance = d;
    }
  }
  return best;
}
