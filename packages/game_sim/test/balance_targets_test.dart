import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

/// Plays like [inner], noting what the faction has made at the start of
/// every 6 h check-in.
final class _Tally implements Bot {
  _Tally(this.inner);

  final Bot inner;

  /// Check-in index to the faction's lifetime production at its start.
  final Map<int, Map<String, BigNum>> made = {};

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    made.putIfAbsent(
      s.time ~/ 21600,
      () => Map.of(s.faction(factionId).lifetimeProduced),
    );
    return inner.decide(e, s, factionId);
  }

  /// Units of [id] made between check-ins [from] and `from + 1`.
  double between(int from, String id) =>
      ((made[from + 1]![id] ?? const BigNum.zero()) -
              (made[from]![id] ?? const BigNum.zero()))
          .toDouble();
}

void main() {
  final content =
      (Content.fromBundle(loadContentDir('../../content')) as ContentOk)
          .content;

  group('a 14-day balanced bot run', () {
    final tally = _Tally(BalancedBot());
    late GameState end;
    final report = runBotSession(
      GameEngine(content),
      tally,
      seed: 1,
      hours: 336,
      onFinished: (s) => end = s,
    );
    final day14 = report.days.last;

    test('earns most of day 14 from tier 2 and up', () {
      expect(day14.day, 14);
      final low = day14.share.entries
          .where((e) => content.resources[e.key]!.tier <= 1)
          .fold(0.0, (t, e) => t + e.value);
      expect(low, lessThanOrEqualTo(0.35), reason: '${day14.share}');
    });

    test('earns no more than 30% of day 14 from one resource', () {
      for (final MapEntry(:key, :value) in day14.share.entries) {
        expect(value, lessThanOrEqualTo(0.30), reason: key);
      }
    });

    test('makes kits, modules and ships by the tens per 6 h on day 2', () {
      // Each maker makes a fixed trickle (see the shipped-content tests);
      // later counts grow only with the number of makers built.
      for (final id in ['outpost_kit', 'habitat_module', 'cargo_ship']) {
        expect(tally.between(4, id), lessThanOrEqualTo(100), reason: id);
      }
    });

    test('grows its crew with habitats', () {
      expect(report.rejectedCommands, 0);
      expect(
        crewTotals(end, content, 'player').supported,
        greaterThan(5 * end.faction('player').baseCrew),
      );
    });
  });
}
