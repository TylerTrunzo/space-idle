import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' hide formatDuration;
import 'package:space_idle/view/format.dart';

void main() {
  group('formatRate', () {
    test('signs and suffixes per-second rates', () {
      expect(formatRate(BigNum.from(1240)), '+1.24K/s');
      expect(formatRate(BigNum.from(-3)), '-3/s');
      expect(formatRate(const BigNum.zero()), '0/s');
      expect(formatRate(BigNum.from(2.5)), '+2.5/s');
    });

    test('goes scientific past the suffixes', () {
      expect(formatRate(BigNum.parse('1e40')), '+1e40/s');
      expect(formatRate(-BigNum.parse('2.5e45')), '-2.5e45/s');
    });

    test('keeps three significant figures below one a second', () {
      // formatNumber alone would show 0.0333 as "0.03" and 0.004 as "0".
      expect(formatRate(BigNum.from(1 / 30)), '+0.0333/s');
      expect(formatRate(BigNum.from(-0.004)), '-0.004/s');
      expect(formatRate(BigNum.from(0.4)), '+0.4/s');
    });
  });

  group('formatAmount', () {
    test('is formatNumber from one up, three figures below', () {
      expect(formatAmount(BigNum.from(1240)), '1.24K');
      expect(formatAmount(BigNum.from(0.4)), '0.4');
      expect(formatAmount(BigNum.from(1 / 30)), '0.0333');
      expect(formatAmount(const BigNum.zero()), '0');
      expect(formatAmount(BigNum.from(-0.25)), '-0.25');
    });
  });

  group('formatPercent', () {
    test('rounds a fraction to a whole percent', () {
      expect(formatPercent(0.5), '50%');
      expect(formatPercent(0), '0%');
      expect(formatPercent(1), '100%');
      expect(formatPercent(0.126), '13%');
    });

    test('never rounds a part up to 100% or down to 0%', () {
      expect(formatPercent(0.999), '99%');
      expect(formatPercent(0.001), '1%');
    });

    test('shows non-finite input as 0%', () {
      expect(formatPercent(double.nan), '0%');
    });
  });

  group('formatDuration', () {
    test('is game_core formatDuration', () {
      expect(formatDuration(45), '45s');
      expect(formatDuration(2 * 3600 + 14 * 60), '2h 14m');
      expect(formatDuration(3 * 86400 + 4 * 3600), '3d 4h');
      expect(formatDuration(1800), '30m');
      expect(formatDuration(-5), '0s');
    });
  });
}
