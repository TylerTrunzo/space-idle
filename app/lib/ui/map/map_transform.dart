import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

/// The one mapping between map units and canvas pixels, read by the
/// painters, the label and node overlays and the hit test; the map builds
/// it with [MapTransform.fitRect] from the scene's bounds.
@immutable
final class MapTransform {
  /// Creates a transform.
  const MapTransform(this.scale, this.origin);

  /// Pixels [fitRect] keeps clear on each side, for labels.
  static const double fitPadding = 32;

  /// Fits [bounds] (map units) into [size] less [fitPadding] a side: the
  /// limiting side decides the scale, so a tall phone uses its width and a
  /// wide window its height, and [bounds] is centred.
  factory MapTransform.fitRect(Size size, Rect bounds) {
    final w = math.max(1.0, size.width - 2 * fitPadding);
    final h = math.max(1.0, size.height - 2 * fitPadding);
    final scale = math.min(
      w / math.max(bounds.width, 1e-6),
      h / math.max(bounds.height, 1e-6),
    );
    return MapTransform(
      scale,
      size.center(Offset.zero) - bounds.center * scale,
    );
  }

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
