import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/map_transform.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

/// Per-frame motion between game ticks, the moving layer's `repaint`
/// signal.
///
/// The map's ticker sets it every frame while shipments are in flight, so
/// they glide between ticks without rebuilding any widget or repainting
/// the static layer. With animations disabled it stays at zero and
/// shipments step once a tick.
class MapMotion extends ChangeNotifier {
  /// Wall-clock seconds since the last game tick, 0 to 1.
  double get sinceTick => _sinceTick;
  double _sinceTick = 0;

  /// Sets [sinceTick] and repaints.
  void update({required double sinceTick}) {
    _sinceTick = sinceTick;
    notifyListeners();
  }
}

/// Map colors the painters use, worked out once, never per paint.
abstract final class _MapColors {
  /// Routes: [Palette.cyan] at 45% alpha.
  static const Color route = Color(0x735FE1FF);

  /// The signal marker's faint ring: [Palette.cyan] at 40% alpha.
  static const Color signal = Color(0x665FE1FF);
}

/// Draws the parts of a [StarMapScene] that change only at a tick or less:
/// orbits, the star, routes and bodies with their rings, badges and
/// project arcs.
///
/// Dumb by design: it reads only the scene and the shared [transform]. It
/// has no `repaint` signal, so per-frame motion never repaints it, and
/// [shouldRepaint] ignores the shipments and signals [MapMotionPainter]
/// draws. Text (names, "Unclaimed", the signal's "?") is drawn by the
/// map's widget overlays, which also carry the semantics.
class StarMapPainter extends CustomPainter {
  /// Creates the static layer's painter.
  StarMapPainter({
    required this.scene,
    required this.transform,
    this.selectedId,
  });

  /// What to draw.
  final StarMapScene scene;

  /// Map units to canvas pixels, shared with the hit test.
  final MapTransform transform;

  /// The selected body, drawn with an extra ring.
  final String? selectedId;

  static const double _ringGap = 3;
  static const double _selectedGap = 7;
  static const double _arcGap = 5;
  static const double _badgeRadius = 6;
  static const Offset _badgeBarTop = Offset(0, -3);
  static const Offset _badgeBarBottom = Offset(0, 0.6);
  static const Offset _badgeDot = Offset(0, 2.8);
  static const double _signalRadius = 14;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final t = transform;
    _stroke
      ..color = Palette.border
      ..strokeWidth = 1;
    for (final r in scene.orbitRadii) {
      canvas.drawCircle(t.origin, r * t.scale, _stroke);
    }
    _fill.color = BodyPalette.star;
    canvas.drawCircle(t.origin, scene.starRadius * t.scale, _fill);
    _paintRoutes(canvas, t);
    for (final b in scene.bodies) {
      _paintBody(canvas, t, b);
    }
    // Signal markers are a still, faint ring (the "?" is a widget
    // overlay): nothing on the map moves but shipments.
    _stroke
      ..color = _MapColors.signal
      ..strokeWidth = 1.5;
    for (final s in scene.signals) {
      canvas.drawCircle(t.toCanvas(s.position), _signalRadius, _stroke);
    }
  }

  void _paintRoutes(Canvas canvas, MapTransform t) {
    _stroke
      ..color = _MapColors.route
      ..strokeWidth = 1.5;
    for (final r in scene.routes) {
      final from = t.toCanvas(r.curve.from);
      final control = t.toCanvas(r.curve.control);
      final to = t.toCanvas(r.curve.to);
      _path
        ..reset()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
      canvas.drawPath(_path, _stroke);
    }
  }

  void _paintBody(Canvas canvas, MapTransform t, MapBody b) {
    final c = t.toCanvas(b.position);
    final r = b.radius * t.scale;
    _fill.color = b.color;
    canvas.drawCircle(c, r, _fill);
    if (b.owned) {
      _stroke
        ..color = Palette.cyan
        ..strokeWidth = 2;
      canvas.drawCircle(c, r + _ringGap, _stroke);
    }
    if (b.id == selectedId) {
      _stroke
        ..color = Palette.text
        ..strokeWidth = 2;
      canvas.drawCircle(c, r + _selectedGap, _stroke);
    }
    if (b.projectProgress case final progress?) {
      _paintArc(canvas, c, r + _arcGap, progress);
    }
    if (b.bottleneck) {
      _paintBadge(canvas, c + Offset(r * 0.8, -r * 0.8));
    }
  }

  void _paintArc(Canvas canvas, Offset c, double radius, double progress) {
    _stroke
      ..color = Palette.border
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, radius, _stroke);
    _stroke.color = Palette.cyan;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      _stroke,
    );
  }

  /// An amber disc with a `!` cut out of it: a shape, not only a color.
  void _paintBadge(Canvas canvas, Offset at) {
    _fill.color = Palette.amber;
    canvas.drawCircle(at, _badgeRadius, _fill);
    _stroke
      ..color = Palette.background
      ..strokeWidth = 1.8;
    canvas.drawLine(at + _badgeBarTop, at + _badgeBarBottom, _stroke);
    _fill.color = Palette.background;
    canvas.drawCircle(at + _badgeDot, 1, _fill);
  }

  @override
  bool shouldRepaint(StarMapPainter oldDelegate) =>
      oldDelegate.transform != transform ||
      oldDelegate.selectedId != selectedId ||
      !scene.sameStaticLayer(oldDelegate.scene);
}

/// Draws what moves every frame: shipment dots along their routes.
///
/// Repainted by [motion] alone, in its own layer, so a frame repaints only
/// these few marks. The shipments' curves are mapped to canvas pixels once,
/// when the painter is made (once a tick); a frame then does scalar maths
/// and one draw per mark.
class MapMotionPainter extends CustomPainter {
  /// Creates the moving layer's painter.
  MapMotionPainter({
    required this.scene,
    required this.transform,
    required this.motion,
  }) : _ships = _shipsInCanvas(scene, transform),
       super(repaint: motion);

  /// The scene whose shipments are drawn.
  final StarMapScene scene;

  /// Map units to canvas pixels, shared with the hit test.
  final MapTransform transform;

  /// Motion since the last tick.
  final MapMotion motion;

  static const double _shipRadius = 3;

  /// Per shipment: x0, y0, cx, cy, x1, y1 (canvas px), progress, rate.
  static const int _stride = 8;

  final Float64List _ships;

  final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..color = Palette.text;

  static Float64List _shipsInCanvas(StarMapScene scene, MapTransform t) {
    final out = Float64List(scene.shipments.length * _stride);
    var i = 0;
    for (final s in scene.shipments) {
      final from = t.toCanvas(s.curve.from);
      final control = t.toCanvas(s.curve.control);
      final to = t.toCanvas(s.curve.to);
      out
        ..[i] = from.dx
        ..[i + 1] = from.dy
        ..[i + 2] = control.dx
        ..[i + 3] = control.dy
        ..[i + 4] = to.dx
        ..[i + 5] = to.dy
        ..[i + 6] = s.progress
        ..[i + 7] = s.progressPerSecond;
      i += _stride;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final since = motion.sinceTick;
    final s = _ships;
    for (var i = 0; i < s.length; i += _stride) {
      final p = math.min(1.0, s[i + 6] + s[i + 7] * since);
      final mt = 1 - p;
      final a = mt * mt, b = 2 * mt * p, c = p * p;
      canvas.drawCircle(
        Offset(
          a * s[i] + b * s[i + 2] + c * s[i + 4],
          a * s[i + 1] + b * s[i + 3] + c * s[i + 5],
        ),
        _shipRadius,
        _fill,
      );
    }
  }

  @override
  bool shouldRepaint(MapMotionPainter oldDelegate) =>
      oldDelegate.transform != transform ||
      oldDelegate.motion != motion ||
      !listEquals(oldDelegate.scene.shipments, scene.shipments);
}
