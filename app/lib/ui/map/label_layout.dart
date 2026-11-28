import 'package:material_ui/material_ui.dart';

/// A body whose label needs a place: its centre and radius on the canvas,
/// and its label's measured size, all in canvas pixels.
@immutable
final class LabelTarget {
  /// Creates a target.
  const LabelTarget(this.center, this.radius, this.size);

  /// The body's centre.
  final Offset center;

  /// The body's drawn radius.
  final double radius;

  /// Its label's size.
  final Size size;
}

/// Pixels between a body's edge and its label.
const double labelGap = 4;

/// How far further from its body, in [_step] px steps, a label may move
/// down or up when every close spot collides.
const double _reachMore = 32;
const double _step = 4;

/// Where each body's label goes, in [bodies]' order: below the body, else
/// above it (both slid sideways to stay on the canvas if need be), else on
/// its side away from the [star], else the star's side, else below or
/// above a little further away,
/// whichever comes first that stays inside [canvas] and clear of the star,
/// every body's disc and every label placed before it. When none is clear,
/// the one that collides least.
List<Rect> placeLabels({
  required List<LabelTarget> bodies,
  required Rect star,
  required Rect canvas,
}) {
  final discs = [
    for (final b in bodies) Rect.fromCircle(center: b.center, radius: b.radius),
  ];
  final placed = <Rect>[];
  for (final b in bodies) {
    Rect? best;
    var fewest = 1 << 30;
    for (final c in _candidates(b, star.center, canvas)) {
      var hits = 0;
      if (!_inside(canvas, c)) hits++;
      if (c.overlaps(star)) hits++;
      hits += discs.where(c.overlaps).length;
      hits += placed.where(c.overlaps).length;
      if (hits < fewest) {
        best = c;
        fewest = hits;
      }
      if (hits == 0) break;
    }
    placed.add(best!);
  }
  return placed;
}

/// Below, above, outward (away from the star), then inward; then below
/// and above stepped further away, up to [_reachMore]. Below and above
/// slide sideways to stay on [canvas], for a body near its edge.
List<Rect> _candidates(LabelTarget b, Offset star, Rect canvas) {
  final Size(:width, :height) = b.size;
  final c = b.center;
  final reach = b.radius + labelGap;
  final outwardRight = c.dx >= star.dx;
  final right = Rect.fromLTWH(c.dx + reach, c.dy - height / 2, width, height);
  final left = Rect.fromLTWH(
    c.dx - reach - width,
    c.dy - height / 2,
    width,
    height,
  );
  final x = (c.dx - width / 2).clamp(
    canvas.left,
    canvas.right - width < canvas.left ? canvas.left : canvas.right - width,
  );
  return [
    Rect.fromLTWH(x, c.dy + reach, width, height),
    Rect.fromLTWH(x, c.dy - reach - height, width, height),
    if (outwardRight) right else left,
    if (outwardRight) left else right,
    for (var more = _step; more <= _reachMore; more += _step) ...[
      Rect.fromLTWH(x, c.dy + reach + more, width, height),
      Rect.fromLTWH(x, c.dy - reach - more - height, width, height),
    ],
  ];
}

bool _inside(Rect canvas, Rect r) =>
    r.left >= canvas.left &&
    r.top >= canvas.top &&
    r.right <= canvas.right &&
    r.bottom <= canvas.bottom;
