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

  /// Check-in index to resource id to the buildings on the faction's
  /// bodies that make it, at the check-in's start.
  final Map<int, Map<String, int>> makers = {};

  @override
  String get name => inner.name;

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final i = s.time ~/ 21600;
    if (!made.containsKey(i)) {
      made[i] = Map.of(s.faction(factionId).lifetimeProduced);
      final count = makers[i] = {};
      for (final body in s.bodies.where((b) => b.ownerId == factionId)) {
        for (final b in body.buildings) {
          for (final id in e.content.buildings[b.defId]!.outputs.keys) {
            count[id] = (count[id] ?? 0) + 1;
          }
        }
      }
    }
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
    late _Tally tally;
    late GameState end;
    late BalanceReport report;
    late DayIncome day14;
    setUpAll(() {
      tally = _Tally(BalancedBot());
      report = runBotSession(
        GameEngine(content),
        tally,
        seed: 1,
        hours: 336,
        onFinished: (s) => end = s,
      );
      day14 = report.days.last;
    });

    test('earns most of day 14 from tier 2 and up', () {
      expect(day14.day, 14);
      final low = day14.share.entries
          .where((e) => content.resources[e.key]!.tier <= 1)
          .fold(0.0, (t, e) => t + e.value);
      expect(low, lessThanOrEqualTo(0.35), reason: '${day14.share}');
    });

    test('earns no more than 40% of day 14 from one resource', () {
      // The target is 30%. Since stage-1.5 Task 8, Orbital Station levels
      // take every magnet-based good (segments, drones, reactor cores) the
      // optimizer makes, so only hull plates, circuits and tier 1 goods
      // are sold, each at its market's cap: hull plates and circuits earn
      // about 36% each. See the Task 8 report for the numbers.
      for (final MapEntry(:key, :value) in day14.share.entries) {
        expect(value, lessThanOrEqualTo(0.40), reason: key);
      }
    });

    test('makes kits, modules and ships by the tens per 6 h on day 7', () {
      // Check-in 28 starts day 8, so 168 h to 174 h: each maker makes a
      // fixed trickle, and the bot builds no more makers than the market
      // for what they make can take.
      for (final id in ['outpost_kit', 'habitat_module', 'cargo_ship']) {
        final units = tally.between(28, id);
        final makers = tally.makers[28]![id] ?? 0;
        expect(units, lessThanOrEqualTo(200), reason: '$id: $units');
        if (makers > 0) {
          expect(units / makers, lessThanOrEqualTo(72), reason: id);
        }
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
