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

/// Where each body's label goes, in [bodies]' order: below the body, else
/// above it, else on its side away from the [star], else the star's side,
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
    for (final c in _candidates(b, star.center)) {
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

/// Below, above, outward (away from the star), then inward.
List<Rect> _candidates(LabelTarget b, Offset star) {
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
  return [
    Rect.fromLTWH(c.dx - width / 2, c.dy + reach, width, height),
    Rect.fromLTWH(c.dx - width / 2, c.dy - reach - height, width, height),
    if (outwardRight) right else left,
    if (outwardRight) left else right,
  ];
}

bool _inside(Rect canvas, Rect r) =>
    r.left >= canvas.left &&
    r.top >= canvas.top &&
    r.right <= canvas.right &&
    r.bottom <= canvas.bottom;
