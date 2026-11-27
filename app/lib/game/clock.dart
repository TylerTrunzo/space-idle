/// The wall clock, injected so offline catch-up and save times are testable.
///
/// Game time never comes from here: it is `GameState.time`. This only
/// measures how long the player was away and stamps saves.
abstract interface class Clock {
  /// The current wall-clock time.
  DateTime now();
}

/// The device clock. It can jump backwards when the user changes the time;
/// callers clamp negative gaps to zero.
final class SystemClock implements Clock {
  /// Creates the device clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// A clock for tests that moves only when [advance]d.
final class FakeClock implements Clock {
  /// Creates a clock reading [start].
  FakeClock(DateTime start) : _now = start;

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves the clock by [by]; a negative duration sets it back.
  void advance(Duration by) => _now = _now.add(by);
}
