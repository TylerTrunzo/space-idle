import 'package:game_core/game_core.dart';

// The app shows game time the way the CLI does: `45s`, `2h 14m`, `3d 4h`.
export 'package:game_core/game_core.dart' show formatDuration, formatNumber;

/// A per-second rate with its sign: `+1.24K/s`, `-3/s`, `0/s`, and
/// `+1e40/s` past the suffixes.
///
/// From one a second up it is [formatNumber]; below that it keeps three
/// significant figures (`+0.0333/s`), as the CLI does, since
/// [formatNumber]'s two decimals would show a slow trickle as `0`.
String formatRate(BigNum perSec) {
  if (perSec.isZero) return '0/s';
  final sign = perSec.isNegative ? '-' : '+';
  final size = perSec.isNegative ? -perSec : perSec;
  return '$sign${_digits(size)}/s';
}

/// An amount that may be a small fraction, such as a rate inside a
/// sentence: [formatNumber] from one up, three significant figures below
/// (`0.0333`), the sign kept.
String formatAmount(BigNum v) {
  if (v.isZero) return '0';
  return v.isNegative ? '-${_digits(-v)}' : _digits(v);
}

String _digits(BigNum size) {
  final d = size.toDouble();
  if (d >= 1) return formatNumber(size);
  final fixed = d.toStringAsPrecision(3);
  final e = fixed.indexOf('e');
  if (e < 0) return _trimZeros(fixed);
  return '${_trimZeros(fixed.substring(0, e))}${fixed.substring(e)}';
}

/// `0.400` as `0.4`, `2.50` as `2.5`, `3.00` as `3`.
String _trimZeros(String s) =>
    s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

/// A fraction as a whole percent: 0.5 as `50%`.
///
/// A part is never shown as all or nothing: anything strictly between 0
/// and 1 reads 1% to 99%, so a building at 99.9% does not look unhindered.
/// Non-finite input reads `0%`.
String formatPercent(double fraction) {
  if (!fraction.isFinite) return '0%';
  var pct = (fraction * 100).round();
  if (fraction > 0 && fraction < 1) pct = pct.clamp(1, 99);
  return '$pct%';
}
