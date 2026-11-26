import 'dart:math' as math;

/// Arbitrary-magnitude number stored as a normalized `double` mantissa and
/// an `int` base-10 exponent.
///
/// The mantissa is `0` or has absolute value in `[1, 10)`; the sign lives on
/// the mantissa. Precision is that of a `double` (about 15 digits).
final class BigNum implements Comparable<BigNum> {
  /// The value zero.
  const BigNum.zero() : mantissa = 0, exponent = 0;

  /// Creates a [BigNum] from a finite [v].
  factory BigNum.from(num v) => BigNum._normalized(v.toDouble(), 0);

  /// Parses `"<mantissa>e<exponent>"` or a plain decimal such as `"12.5"`.
  ///
  /// Throws [FormatException] on malformed input.
  factory BigNum.parse(String s) {
    final t = s.trim();
    final i = t.indexOf(RegExp('[eE]'));
    final m = double.tryParse(i < 0 ? t : t.substring(0, i));
    final e = i < 0 ? 0 : int.tryParse(t.substring(i + 1));
    if (m == null || e == null || !m.isFinite) {
      throw FormatException('Invalid BigNum', s);
    }
    return BigNum._normalized(m, e);
  }

  /// Restores a value written by [toJson].
  static BigNum fromJson(String s) => BigNum.parse(s);

  const BigNum._(this.mantissa, this.exponent);

  factory BigNum._normalized(double m, int e) {
    if (m == 0) return const BigNum.zero();
    if (!m.isFinite) throw ArgumentError.value(m, 'm', 'must be finite');
    var mm = m;
    var ee = e;
    final a = mm.abs();
    if (a >= 10 || a < 1) {
      final shift = (math.log(a) / math.ln10).floor();
      if (ee + shift < _minExponent) return const BigNum.zero();
      mm = shift >= 0 ? mm / _pow10(shift) : mm * _pow10(-shift);
      ee += shift;
    }
    while (mm.abs() >= 10) {
      mm /= 10;
      ee++;
    }
    while (mm.abs() < 1) {
      mm *= 10;
      ee--;
    }
    if (ee < _minExponent) return const BigNum.zero();
    return BigNum._(mm, ee);
  }

  /// Values with a smaller exponent are treated as zero.
  static const _minExponent = -300;

  static double _pow10(int n) => math.pow(10.0, n).toDouble();

  /// Signed mantissa: `0` or with absolute value in `[1, 10)`.
  final double mantissa;

  /// Base-10 exponent.
  final int exponent;

  /// Whether this is zero.
  bool get isZero => mantissa == 0;

  /// Whether this is below zero.
  bool get isNegative => mantissa < 0;

  /// Sum of this and [o].
  BigNum operator +(BigNum o) {
    if (isZero) return o;
    if (o.isZero) return this;
    final BigNum hi, lo;
    if (exponent >= o.exponent) {
      hi = this;
      lo = o;
    } else {
      hi = o;
      lo = this;
    }
    final gap = hi.exponent - lo.exponent;
    if (gap > 17) return hi;
    return BigNum._normalized(
      hi.mantissa + lo.mantissa / _pow10(gap),
      hi.exponent,
    );
  }

  /// Difference of this and [o].
  BigNum operator -(BigNum o) => this + (-o);

  /// Negation.
  BigNum operator -() => isZero ? this : BigNum._(-mantissa, exponent);

  /// Product of this and [o].
  BigNum operator *(BigNum o) {
    if (isZero || o.isZero) return const BigNum.zero();
    return BigNum._normalized(mantissa * o.mantissa, exponent + o.exponent);
  }

  /// Quotient of this and [o]; throws [ArgumentError] when [o] is zero.
  BigNum operator /(BigNum o) {
    if (o.isZero) throw ArgumentError.value(o, 'o', 'division by zero');
    if (isZero) return this;
    return BigNum._normalized(mantissa / o.mantissa, exponent - o.exponent);
  }

  /// Whether this is less than [o].
  bool operator <(BigNum o) => compareTo(o) < 0;

  /// Whether this is less than or equal to [o].
  bool operator <=(BigNum o) => compareTo(o) <= 0;

  /// Whether this is greater than [o].
  bool operator >(BigNum o) => compareTo(o) > 0;

  /// Whether this is greater than or equal to [o].
  bool operator >=(BigNum o) => compareTo(o) >= 0;

  /// Multiplies by the plain double factor [f].
  BigNum mulDouble(double f) => f == 0 || isZero
      ? const BigNum.zero()
      : BigNum._normalized(mantissa * f, exponent);

  /// Raises to the non-negative integer power [n].
  BigNum powInt(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'must be >= 0');
    var result = BigNum._normalized(1, 0);
    var base = this;
    var k = n;
    while (k > 0) {
      if (k.isOdd) result = result * base;
      k >>= 1;
      if (k > 0) base = base * base;
    }
    return result;
  }

  /// The smaller of this and [o].
  BigNum min(BigNum o) => this <= o ? this : o;

  /// The larger of this and [o].
  BigNum max(BigNum o) => this >= o ? this : o;

  /// Converts to `double`; yields signed infinity above exponent 308.
  double toDouble() {
    if (isZero) return 0;
    if (exponent > 308) {
      return isNegative ? double.negativeInfinity : double.infinity;
    }
    if (exponent < -330) return 0;
    return mantissa * math.pow(10.0, exponent).toDouble();
  }

  /// Serializes as `"<mantissa>e<exponent>"`; zero is `"0"`.
  String toJson() {
    if (isZero) return '0';
    var m = mantissa.toString();
    if (m.endsWith('.0')) m = m.substring(0, m.length - 2);
    return '${m}e$exponent';
  }

  // Mantissa rounded to 12 significant digits, as a scaled integer, plus the
  // exponent adjusted for any carry.
  (int, int) get _key {
    var r = (mantissa * 1e11).round();
    var e = exponent;
    if (r.abs() >= 1000000000000) {
      r = (r / 10).round();
      e++;
    }
    return (r, e);
  }

  @override
  int compareTo(BigNum other) {
    if (this == other) return 0;
    if (isZero) return other.isNegative ? 1 : -1;
    if (other.isZero) return isNegative ? -1 : 1;
    if (isNegative != other.isNegative) return isNegative ? -1 : 1;
    final sign = isNegative ? -1 : 1;
    if (exponent != other.exponent) {
      return exponent < other.exponent ? -sign : sign;
    }
    return mantissa < other.mantissa ? -1 : 1;
  }

  @override
  bool operator ==(Object other) {
    if (other is! BigNum) return false;
    if (isZero || other.isZero) return isZero && other.isZero;
    return _key == other._key;
  }

  @override
  int get hashCode => isZero ? 0 : Object.hash(_key.$1, _key.$2);

  @override
  String toString() => toJson();
}
