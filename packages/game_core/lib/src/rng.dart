/// Deterministic Mulberry32 generator that gives identical results on the
/// Dart VM and in JavaScript.
///
/// Only operations that stay exact below 2^53 are used, so no platform-specific
/// integer behavior leaks in.
final class Rng {
  /// Creates a generator from any integer [seed] (reduced to 32 bits).
  Rng(int seed) : _state = seed & _mask;

  /// Restores a generator from a [state] previously read from [state].
  Rng.fromState(int state) : _state = state & _mask;

  static const _mask = 0xFFFFFFFF;

  int _state;

  /// The full generator state: a non-negative integer below 2^32.
  int get state => _state;

  /// Next uniformly distributed unsigned 32-bit integer.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    final a = _state;
    var t = _imul(a ^ (a >> 15), 1 | a);
    t = ((t + _imul(t ^ (t >> 7), 61 | t)) & _mask) ^ t;
    return (t ^ (t >> 14)) & _mask;
  }

  /// Next double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296;

  /// Next integer in `[0, maxExclusive)`.
  int nextInt(int maxExclusive) => (nextDouble() * maxExclusive).floor();

  // 32-bit multiply with every intermediate below 2^53.
  static int _imul(int a, int b) {
    final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
    return ((((ah * bl + al * bh) & 0xFFFF) << 16) + al * bl) & _mask;
  }
}
