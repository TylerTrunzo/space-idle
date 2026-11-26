import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final cases = <num, String>{
    0: '0',
    3: '3',
    3.14159: '3.14',
    12.34: '12.3',
    999: '999',
    999.5: '1K',
    1000: '1K',
    1240: '1.24K',
    12400: '12.4K',
    124000: '124K',
    999999: '1M',
    2.41e6: '2.41M',
    1e33: '1Dc',
    -1500: '-1.5K',
  };
  test('formats', () {
    cases.forEach(
      (v, s) => expect(formatNumber(BigNum.from(v)), s, reason: '$v'),
    );
  });
  test(
    'scientific after Dc',
    () => expect(formatNumber(BigNum.parse('1.24e36')), '1.24e36'),
  );
  test(
    'carry into scientific',
    () => expect(formatNumber(BigNum.parse('9.9996e35')), '1e36'),
  );

  test('durations show seconds, minutes, hours and from a day up days', () {
    final cases = <double, String>{
      0: '0s',
      -5: '0s',
      45: '45s',
      1830: '30m 30s',
      3600: '1h',
      5400: '1h 30m',
      43200: '12h',
      86399: '1d',
      86400: '1d',
      90000: '1d 1h',
      352800: '4d 2h',
      352801: '4d 3h',
    };
    cases.forEach((v, s) => expect(formatDuration(v), s, reason: '$v'));
  });
}
