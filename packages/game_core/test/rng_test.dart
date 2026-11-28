import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Produced on the Dart VM; also matches the canonical JS Mulberry32.
const goldenSeed42 = [
  2581720956,
  1925393290,
  3661312704,
  2876485805,
  750819978,
];

void main() {
  test('golden vector', () {
    final r = Rng(42);
    expect([for (var i = 0; i < 5; i++) r.nextUint32()], goldenSeed42);
  });
  test('state round trip', () {
    final a = Rng(7)..nextUint32();
    final b = Rng.fromState(a.state);
    expect(b.nextUint32(), a.nextUint32());
  });
  test('nextInt bounds', () {
    final r = Rng(1);
    for (var i = 0; i < 1000; i++) {
      expect(r.nextInt(6), inInclusiveRange(0, 5));
    }
  });
  test('nextDouble range', () {
    final r = Rng(3);
    for (var i = 0; i < 1000; i++) {
      expect(r.nextDouble(), allOf(greaterThanOrEqualTo(0), lessThan(1)));
    }
  });
}
