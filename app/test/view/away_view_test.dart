import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' hide formatDuration;
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/away_view.dart';
import 'package:space_idle/view/format.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

/// A controller that comes back to [s] after [away], with its summary
/// pending.
Future<GameController> _back(GameState s, Duration away) async {
  final clock = FakeClock(DateTime.utc(2026, 11, 27, 12));
  final store = MemorySaveStore(
    jsonEncode({
      'savedAt': clock.now().millisecondsSinceEpoch,
      'save': SaveCodec.encode(s),
    }),
  );
  clock.advance(away);
  final c = GameController(content: content, store: store, clock: clock);
  await c.start();
  return c;
}

GameState _newGame() => GameEngine(content).newGame(1);

/// A summary made by hand, for the problem rules.
OfflineSummary _summary(
  GameController c, {
  List<Bottleneck> top = const [],
  BigNum? perSec,
  BigNum? gained,
}) {
  final crew = crewTotals(c.state, content, _p);
  return OfflineSummary(
    awayFrom: c.state.time - 3600,
    secondsSimulated: 3600,
    secondsAway: 3600,
    capSeconds: 43200,
    stockGained: const {},
    creditsGained: gained ?? BigNum.from(100),
    totalWasted: const BigNum.zero(),
    wastedValue: const BigNum.zero(),
    milestonesReached: const [],
    topBottlenecks: top,
    projectsCompleted: const [],
    housingBefore: crew,
    housingAfter: crew,
    creditsPerSecBefore: perSec ?? BigNum.from(1000),
    creditsPerSecAfter: perSec ?? BigNum.from(1000),
  );
}

Bottleneck _full(String body, String res, int lostPerHour) => Bottleneck(
  kind: BottleneckKind.storageFull,
  bodyId: body,
  buildingId: null,
  resourceId: res,
  runFraction: 0,
  lostCreditsPerHour: BigNum.from(lostPerHour),
);

void main() {
  test('2 h away: the time, the headline, the net credits', () async {
    final c = await _back(_newGame(), const Duration(hours: 2));
    final v = awayView(c, c.pendingAwaySummaries);
    expect(v.timeLine, 'Away 2h');
    expect(v.capped, isFalse);
    expect(v.headline, startsWith('Away 2h; '));
    expect(v.headline, contains('credits'));
    expect(v.net, startsWith('+'));
    expect(v.net, endsWith(' credits'));
  });

  test('30 h away: the capped line is never hidden', () async {
    final c = await _back(_newGame(), const Duration(hours: 30));
    final v = awayView(c, c.pendingAwaySummaries);
    expect(v.capped, isTrue);
    expect(
      v.timeLine,
      'Away ${formatDuration(30 * 3600)}, ${formatDuration(12 * 3600)} '
      'counted',
    );
    expect(v.headline, contains('counted (cap)'));
  });

  test('a claim started before a 2 h absence is among what finished, '
      'with its milestone', () async {
    final s = _newGame();
    final e = GameEngine(content);
    s.faction(_p).credits = BigNum.from(1e6);
    expect(
      e.apply(s, const ClaimBodyCommand(_p, 'brine', 'kora')),
      isA<CommandOk>(),
    );
    final c = await _back(s, const Duration(hours: 2));
    final v = awayView(c, c.pendingAwaySummaries);
    expect(v.finished, contains('Claimed Brine'));
    expect(v.milestones, contains('First Claim'));
  });

  test('two catch-ups are combined', () async {
    final c = await _back(_newGame(), const Duration(hours: 2));
    await c.resume();
    final one = c.pendingAwaySummaries.first;
    final both = awayView(c, [one, one]);
    expect(both.timeLine, 'Away ${formatDuration(one.secondsAway * 2)}');
  });

  group('problems', () {
    late GameController c;
    setUp(() async => c = await _back(_newGame(), const Duration(minutes: 1)));

    test('those under 0.1% of income are hidden', () {
      // 1K a second is 3.6M an hour: 0.1% is 3.6K an hour.
      final v = awayView(c, [
        _summary(
          c,
          top: [_full('kora', 'steel', 2000), _full('kora', 'iron_ore', 50000)],
        ),
      ]);
      expect(v.problems, hasLength(1));
      expect(v.problems.single.text, contains('Iron Ore'));
      expect(v.problems.single.text, contains('about 50K credits an hour'));
      expect(v.problems.single.go, const AwayGoBody('kora'));
    });

    test('at most three, in the summary\'s order', () {
      final v = awayView(c, [
        _summary(
          c,
          top: [
            for (final r in ['steel', 'iron_ore', 'copper_ore', 'water'])
              _full('kora', r, 90000),
          ],
        ),
      ]);
      expect(v.problems, hasLength(3));
    });

    test('a diversion goes to its megaproject', () {
      final v = awayView(c, [
        _summary(
          c,
          top: [
            Bottleneck(
              kind: BottleneckKind.megaprojectDiversion,
              bodyId: null,
              buildingId: null,
              resourceId: 'hull_plate',
              runFraction: 0.6,
              megaprojectId: 'orbital_station',
              shareOfSales: 0.4,
              lostCreditsPerHour: BigNum.from(1200000),
            ),
          ],
        ),
      ]);
      expect(v.problems.single.text, contains('Orbital Station takes 40%'));
      expect(v.problems.single.go, const AwayGoMegaproject('orbital_station'));
    });

    test(
      'a contract holding goods is its own "needs your attention" line',
      () async {
        // On return: the station fed goods on its own, and a contract
        // holding Hull Plate it owes.
        final back = await _back(_newGame(), const Duration(minutes: 1));
        back.run(
          const SetMegaprojectAutoCommand(
            _p,
            'orbital_station',
            goods: GoodsFeedMode.always,
          ),
        );
        back.state
            .faction(_p)
            .contracts
            .add(
              ContractState(
                id: 'c_hull',
                templateId: 'veyra_bulk',
                resourceId: 'hull_plate',
                quantity: BigNum.from(100),
                rewardCredits: BigNum.from(900),
                postedAt: back.state.time,
              ),
            );
        back.state.body('kora').stock['hull_plate'] = BigNum.from(60);
        back.tickSeconds(1);
        final v = awayView(back, [_summary(back)]);
        final line = v.attention.single;
        expect(line.text, contains('Contract #c_hull holds'));
        expect(line.go, const AwayGoContract('c_hull'));
        expect(v.problems.where((p) => p.text.contains('Contract #')), isEmpty);
      },
    );
  });

  group('the rest of the summary', () {
    test('gains by source: earned and paid into megaprojects', () async {
      final c = await _back(_newGame(), const Duration(minutes: 1));
      final crew = crewTotals(c.state, content, _p);
      final v = awayView(c, [
        OfflineSummary(
          awayFrom: 0,
          secondsSimulated: 3600,
          secondsAway: 3600,
          capSeconds: 43200,
          stockGained: {
            'steel': BigNum.from(500),
            'iron_ore': BigNum.from(-200),
          },
          creditsGained: BigNum.from(700),
          creditsEarned: BigNum.from(1000),
          totalWasted: BigNum.from(1200),
          wastedValue: BigNum.from(3000),
          milestonesReached: const ['credits_10k'],
          topBottlenecks: const [],
          projectsCompleted: const [
            CompletedProject(
              kind: ProjectKind.megaprojectStage,
              targetId: 'orbital_station',
              name: 'Orbital Station',
              level: 3,
            ),
            CompletedProject(
              kind: ProjectKind.survey,
              targetId: 'tessaly',
              name: 'Tessaly',
            ),
          ],
          housingBefore: crew,
          housingAfter: crew,
          creditsPerSecBefore: BigNum.from(1),
          creditsPerSecAfter: BigNum.from(1),
          autoDelivered: {
            'orbital_station': {creditsKey: BigNum.from(300)},
          },
        ),
      ]);
      expect(v.net, '+700 credits');
      expect(v.gains, [
        'Earned 1K credits from sales and contracts',
        '300 credits went into the Orbital Station',
      ]);
      expect(v.finished, [
        'Orbital Station reached level 3',
        'Surveyed Tessaly',
      ]);
      expect(v.headline, contains('Orbital Station reached level 3'));
      expect(v.milestones, ['Ten Thousand Credits']);
      expect(v.stock.map((l) => (l.name, l.amount, l.gain)), [
        ('Steel', '+500', true),
        ('Iron Ore', '-200', false),
      ]);
      expect(v.waste, 'Wasted 1.2K units, worth about 3K credits');
    });

    test('under one credit either way shows +0', () async {
      final c = await _back(_newGame(), const Duration(minutes: 1));
      final v = awayView(c, [_summary(c, gained: BigNum.from(-0.4))]);
      expect(v.net, '+0 credits');
    });

    test('a claim that became affordable while away', () async {
      final s = _newGame();
      // 4K now; the first claim costs 5K.
      s.faction(_p).credits = BigNum.from(4000);
      final c = await _back(s, const Duration(minutes: 1));
      c.state.faction(_p).credits = BigNum.from(6000);
      final v = awayView(c, [_summary(c, gained: BigNum.from(2000))]);
      expect(v.afford, 'You can now afford to claim Cinder');
    });

    test('nothing newly affordable: no line', () async {
      final c = await _back(_newGame(), const Duration(minutes: 1));
      c.state.faction(_p).credits = BigNum.from(6000);
      final v = awayView(c, [_summary(c, gained: BigNum.from(1))]);
      expect(v.afford, isNull);
    });
  });
}
