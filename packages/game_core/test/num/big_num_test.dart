import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes', () {
    final b = BigNum.from(12345);
    expect(b.mantissa, closeTo(1.2345, 1e-12));
    expect(b.exponent, 4);
  });
  test(
    'adds across exponents',
    () => expect((BigNum.parse('1e30') + BigNum.from(1)).toJson(), '1e30'),
  );
  test(
    'adds similar',
    () => expect(BigNum.from(950) + BigNum.from(50), BigNum.from(1000)),
  );
  test(
    'subtract to zero',
    () => expect((BigNum.from(5) - BigNum.from(5)).isZero, isTrue),
  );
  test('multiply beyond double', () {
    final b = BigNum.parse('1e300') * BigNum.parse('1e300');
    expect(b.exponent, 600);
    expect(b.toDouble(), double.infinity);
  });
  test(
    'divide',
    () => expect(BigNum.from(1) / BigNum.from(4), BigNum.from(0.25)),
  );
  test('powInt', () {
    expect(BigNum.from(1.15).powInt(100).toDouble(), closeTo(1174313.45, 1));
    expect(BigNum.from(7).powInt(0), BigNum.from(1));
  });
  test('compare', () {
    expect(BigNum.parse('1e40') > BigNum.parse('9e39'), isTrue);
    expect(BigNum.from(-1) < BigNum.zero(), isTrue);
    expect(BigNum.from(-1e5) < BigNum.from(-1e3), isTrue);
    expect(BigNum.from(2) <= BigNum.from(2), isTrue);
  });
  test('json round trip', () {
    for (final s in ['0', '1.5e3', '-2.25e-4', '7e1000']) {
      expect(BigNum.fromJson(BigNum.fromJson(s).toJson()), BigNum.fromJson(s));
    }
  });
  test('json format', () {
    expect(BigNum.zero().toJson(), '0');
    expect(BigNum.from(1500).toJson(), '1.5e3');
    expect(BigNum.from(-0.000225).toJson(), '-2.25e-4');
  });
  test('min max neg mulDouble', () {
    final a = BigNum.from(3), b = BigNum.from(5);
    expect(a.min(b), a);
    expect(a.max(b), b);
    expect(-a, BigNum.from(-3));
    expect(a.mulDouble(1.5), BigNum.from(4.5));
    expect(a.mulDouble(0).isZero, isTrue);
  });
  test('hashCode matches equality', () {
    expect(
      (BigNum.from(950) + BigNum.from(50)).hashCode,
      BigNum.from(1000).hashCode,
    );
  });
}
