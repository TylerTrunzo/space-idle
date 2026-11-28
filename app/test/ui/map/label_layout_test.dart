import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/ui/map/label_layout.dart';

void main() {
  const canvas = Rect.fromLTWH(0, 0, 400, 400);
  const star = Rect.fromLTWH(190, 190, 20, 20);
  const label = Size(60, 20);

  test('a label goes below its body when nothing is in the way', () {
    final rects = placeLabels(
      bodies: const [LabelTarget(Offset(100, 100), 10, label)],
      star: star,
      canvas: canvas,
    );
    expect(rects.single, const Rect.fromLTWH(70, 100 + 10 + 4, 60, 20));
  });

  test('above when below would cover the star', () {
    final rects = placeLabels(
      bodies: const [LabelTarget(Offset(200, 160), 10, label)],
      star: star,
      canvas: canvas,
    );
    expect(rects.single.bottom, lessThanOrEqualTo(160 - 10));
    expect(rects.single.overlaps(star), isFalse);
  });

  test('outward when both below and above are taken', () {
    final rects = placeLabels(
      bodies: const [
        LabelTarget(Offset(300, 200), 10, label),
        // Bodies just above and below the first one block both spots.
        LabelTarget(Offset(300, 232), 8, Size.zero),
        LabelTarget(Offset(300, 168), 8, Size.zero),
      ],
      star: star,
      canvas: canvas,
    );
    // Away from the star, which is to the left: on the right.
    expect(rects.first.left, greaterThan(300));
  });

  test('a label below a body near the edge slides along to stay on', () {
    final rects = placeLabels(
      bodies: const [LabelTarget(Offset(10, 100), 6, label)],
      star: star,
      canvas: canvas,
    );
    expect(rects.single.left, 0);
    expect(rects.single.top, 100 + 6 + labelGap, reason: 'still below');
  });

  test('when every close spot collides, a label steps further down', () {
    // Near the left edge, beside the star: centred or slid, below and
    // above both cross the star or its neighbour's disc.
    const tight = Rect.fromLTWH(132, 459, 35, 35);
    final rects = placeLabels(
      bodies: const [
        LabelTarget(Offset(51, 466), 9, Size(140, 32)),
        LabelTarget(Offset(151, 422), 12, Size.zero),
      ],
      star: tight,
      canvas: const Rect.fromLTWH(0, 0, 412, 915),
    );
    final r = rects.first;
    expect(r.overlaps(tight), isFalse);
    expect(r.top, greaterThan(466), reason: 'below');
    expect(r.top - (466 + 9), lessThanOrEqualTo(labelGap + 32));
  });

  test('never over another label or off the canvas', () {
    final rects = placeLabels(
      bodies: const [
        LabelTarget(Offset(100, 380), 10, label), // near the bottom edge
        LabelTarget(Offset(110, 330), 10, label),
      ],
      star: star,
      canvas: canvas,
    );
    expect(canvas.expandToInclude(rects[0]), canvas);
    expect(rects[0].overlaps(rects[1]), isFalse);
  });
}
