import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

/// Per-frame motion between game ticks, the painter's `repaint` signal.
///
/// The map's ticker sets it every frame, so shipments glide and signal
/// markers pulse without rebuilding any widget. With animations disabled
/// it stays at zero: shipments step once a tick and markers hold still.
class MapMotion extends ChangeNotifier {
  /// Wall-clock seconds since the last game tick, 0 to 1.
  double get sinceTick => _sinceTick;
  double _sinceTick = 0;

  /// Signal pulse phase, 0 to 1.
  double get pulse => _pulse;
  double _pulse = 0;

  /// Sets both values and repaints.
  void update({required double sinceTick, required double pulse}) {
    _sinceTick = sinceTick;
    _pulse = pulse;
    notifyListeners();
  }
}

/// Draws a [StarMapScene]: orbits, the star, routes, bodies with their
/// rings, badges and project arcs, shipments, and signal pulses.
///
/// Dumb by design: it reads only the scene, the shared [transform] and
/// [motion]. Text (names, "Unclaimed", the signal's "?") is drawn by the
/// map's widget overlays, which also carry the semantics. Nothing is
/// allocated per element: paints and the route path are reused.
class StarMapPainter extends CustomPainter {
  /// Creates a painter.
  StarMapPainter({
    required this.scene,
    required this.transform,
    required this.motion,
    this.selectedId,
  }) : super(repaint: motion);

  /// What to draw.
  final StarMapScene scene;

  /// Map units to canvas pixels, shared with the hit test.
  final MapTransform transform;

  /// Motion since the last tick.
  final MapMotion motion;

  /// The selected body, drawn with an extra ring.
  final String? selectedId;

  static const double _ringGap = 3;
  static const double _selectedGap = 7;
  static const double _arcGap = 5;
  static const double _badgeRadius = 6;
  static const double _shipRadius = 3;
  static const double _signalRadius = 14;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final t = transform;
    _paintOrbits(canvas, t);
    _fill.color = BodyPalette.star;
    canvas.drawCircle(t.origin, scene.starRadius * t.scale, _fill);
    _paintRoutes(canvas, t);
    for (final b in scene.bodies) {
      _paintBody(canvas, t, b);
    }
    _paintShipments(canvas, t);
    _paintSignals(canvas, t);
  }

  void _paintOrbits(Canvas canvas, MapTransform t) {
    _stroke
      ..color = Palette.border
      ..strokeWidth = 1;
    for (final r in scene.orbitRadii) {
      canvas.drawCircle(t.origin, r * t.scale, _stroke);
    }
  }

  void _paintRoutes(Canvas canvas, MapTransform t) {
    _stroke
      ..color = Palette.cyan.withValues(alpha: 0.45)
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
    canvas.drawLine(at.translate(0, -3), at.translate(0, 0.6), _stroke);
    _fill.color = Palette.background;
    canvas.drawCircle(at.translate(0, 2.8), 1, _fill);
  }

  void _paintShipments(Canvas canvas, MapTransform t) {
    _fill.color = Palette.text;
    final since = motion.sinceTick;
    for (final s in scene.shipments) {
      final p = math.min(1.0, s.progress + s.progressPerSecond * since);
      canvas.drawCircle(t.toCanvas(s.curve.at(p)), _shipRadius, _fill);
    }
  }

  void _paintSignals(Canvas canvas, MapTransform t) {
    // Faint, slowly breathing: 0.2 to 0.5 alpha.
    final glow = 0.35 + 0.15 * math.sin(2 * math.pi * motion.pulse);
    _stroke
      ..color = Palette.cyan.withValues(alpha: glow)
      ..strokeWidth = 1.5;
    for (final s in scene.signals) {
      canvas.drawCircle(t.toCanvas(s.position), _signalRadius, _stroke);
    }
  }

  @override
  bool shouldRepaint(StarMapPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.transform != transform ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.motion != motion;
}
