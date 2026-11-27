import 'big_num.dart';

const _suffixes = [
  '',
  'K',
  'M',
  'B',
  'T',
  'Qa',
  'Qi',
  'Sx',
  'Sp',
  'Oc',
  'No',
  'Dc',
];

String _trim(String s) {
  if (!s.contains('.')) return s;
  var end = s.length;
  while (s[end - 1] == '0') {
    end--;
  }
  if (s[end - 1] == '.') end--;
  return s.substring(0, end);
}

/// How [formatNumber] rounds to three significant digits.
enum NumberRounding {
  /// To the nearest, halves away from zero.
  nearest,

  /// Toward zero: what is delivered or held, so it never reads as more.
  down,

  /// Away from zero: what is still owed, so it never reads as less.
  up,
}

/// Rounds [x] (not negative) to [d] decimals the [mode] way.
double _roundTo(double x, int d, NumberRounding mode) {
  final f = d == 0 ? 1.0 : (d == 1 ? 10.0 : 100.0);
  // The relative nudge absorbs mantissa*10^k error (9.995*100 = 999.4999...).
  return switch (mode) {
        NumberRounding.nearest => (x * f * (1 + 1e-12)).roundToDouble(),
        NumberRounding.down => (x * f * (1 + 1e-12)).floorToDouble(),
        NumberRounding.up => (x * f * (1 - 1e-12)).ceilToDouble(),
      } /
      f;
}

/// Rounds [x] (in `[0, 1000]`) to three significant digits the [mode] way.
double _round3(double x, NumberRounding mode) {
  var d = x < 10 ? 2 : (x < 100 ? 1 : 0);
  var r = _roundTo(x, d, mode);
  // Rounding can promote to the next digit band (9.996 -> 10.00).
  if (d > 0 && r >= (d == 2 ? 10 : 100)) {
    d--;
    r = _roundTo(x, d, mode);
  }
  return r;
}

/// Formats [v] for display: plain up to 999, suffixed (`K`..`Dc`) with three
/// significant digits up to 1e36, scientific notation beyond.
///
/// [rounding] picks how the digits are rounded: to the nearest by default;
/// [NumberRounding.down] for progress such as units delivered, so 29,999
/// of 30K reads "29.9K", not "30K"; [NumberRounding.up] for what is still
/// owed, so a part of a unit owed never reads as nothing. Either is applied
/// to the size, the sign kept.
String formatNumber(
  BigNum v, {
  NumberRounding rounding = NumberRounding.nearest,
}) {
  if (v.isZero) return '0';
  final sign = v.isNegative ? '-' : '';
  final abs = v.isNegative ? -v : v;

  if (abs.exponent < 3) {
    final r = _round3(abs.toDouble(), rounding);
    if (r < 1000) {
      final s = _trim(r.toStringAsFixed(r < 10 ? 2 : (r < 100 ? 1 : 0)));
      return s == '0' ? '0' : '$sign$s';
    }
    return '${sign}1K';
  }

  var group = abs.exponent ~/ 3;
  if (group < _suffixes.length) {
    var scaled = _round3(abs.mantissa * _pow10(abs.exponent % 3), rounding);
    if (scaled >= 1000) {
      scaled = 1;
      group++;
    }
    if (group < _suffixes.length) {
      final d = scaled < 10 ? 2 : (scaled < 100 ? 1 : 0);
      return '$sign${_trim(scaled.toStringAsFixed(d))}${_suffixes[group]}';
    }
    return '${sign}1e${group * 3}';
  }

  var m = double.parse(abs.mantissa.toStringAsFixed(2));
  var e = abs.exponent;
  if (m >= 10) {
    m = 1;
    e++;
  }
  return '$sign${_trim(m.toStringAsFixed(2))}e$e';
}

double _pow10(int n) => n == 0 ? 1 : (n == 1 ? 10 : 100);

/// [seconds] of game time for display, rounded up: `45s` and `30m 30s`
/// under an hour, whole minutes such as `1h 30m` from an hour up, and
/// whole hours such as `4d 2h` from a day up. Zero, negative or
/// non-finite input shows as `0s`.
String formatDuration(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '0s';
  final whole = seconds.ceil();
  if (whole < 3600) {
    final (m, s) = (whole ~/ 60, whole % 60);
    if (m == 0) return '${s}s';
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
  final minutes = (whole / 60).ceil();
  if (minutes < 1440) {
    final (h, m) = (minutes ~/ 60, minutes % 60);
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  final hours = (minutes / 60).ceil();
  final (d, h) = (hours ~/ 24, hours % 24);
  return h == 0 ? '${d}d' : '${d}d ${h}h';
}
