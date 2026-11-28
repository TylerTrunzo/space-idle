import 'package:flutter_test/flutter_test.dart';
import 'package:space_idle/game/clock.dart';

void main() {
  test('FakeClock starts where told and moves only when advanced', () {
    final start = DateTime.utc(2026, 1, 1);
    final clock = FakeClock(start);
    expect(clock.now(), start);

    clock.advance(const Duration(hours: 2));
    expect(clock.now(), start.add(const Duration(hours: 2)));

    clock.advance(const Duration(hours: -3));
    expect(clock.now(), start.subtract(const Duration(hours: 1)));
  });

  test('SystemClock reads the wall clock', () {
    final before = DateTime.now();
    final now = const SystemClock().now();
    expect(now.isBefore(before), isFalse);
    expect(now.difference(before), lessThan(const Duration(seconds: 5)));
  });
}
