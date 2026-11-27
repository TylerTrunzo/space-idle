import 'package:game_core/game_core.dart';
import 'package:game_sim/src/away_headline.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:test/test.dart';

BigNum n(num v) => BigNum.from(v);

void main() {
  final c = (Content.fromBundle(loadContentDir('../../content')) as ContentOk)
      .content;
  final e = GameEngine(c);

  OfflineSummary summary({
    required num gained,
    num? earned,
    Map<String, Map<String, BigNum>> autoDelivered = const {},
    double away = 60,
  }) => OfflineSummary(
    awayFrom: 0,
    secondsSimulated: away,
    secondsAway: away,
    capSeconds: 43200,
    stockGained: const {},
    creditsGained: n(gained),
    creditsEarned: earned == null ? null : n(earned),
    totalWasted: const BigNum.zero(),
    wastedValue: const BigNum.zero(),
    milestonesReached: const [],
    topBottlenecks: const [],
    projectsCompleted: const [],
    housingBefore: const CrewTotals(base: 3, supported: 3, assigned: 3),
    housingAfter: const CrewTotals(base: 3, supported: 3, assigned: 3),
    creditsPerSecBefore: const BigNum.zero(),
    creditsPerSecAfter: const BigNum.zero(),
    autoDelivered: autoDelivered,
  );

  test('rounds the net to whole credits, and float residue to 0', () {
    // Round-4 casual bug 5: "net +0.59", "net -0.3" credits.
    final paid = {
      'mass_driver': {'credits': n(2.11e9)},
    };
    String net(num gained) => awayHeadline(
      summary(gained: gained, earned: 2.67e9, autoDelivered: paid),
      c,
    ).split('net ').last;
    expect(net(0.59), '+0');
    expect(net(-0.3), '+0');
    expect(net(-0.99), '+0');
    expect(net(1.5), '+2');
    expect(net(-2.4), '-2');
    expect(net(560e6), '+560M');
    expect(awayHeadline(summary(gained: 0.05), c), 'Away 1m; +0 credits');
  });

  test('gives the change in credits, signed, when nothing was paid in', () {
    expect(
      awayHeadline(summary(gained: 36000, away: 3 * 3600), c),
      'Away 3h; +36K credits',
    );
    expect(
      awayHeadline(summary(gained: 0, away: 43200), c),
      'Away 12h; +0 credits',
    );
    expect(awayHeadline(summary(gained: -1500), c), 'Away 1m; -1.5K credits');
    // Goods alone going in change nothing.
    expect(
      awayHeadline(
        summary(
          gained: 500,
          autoDelivered: {
            'mass_driver': {'water': n(10)},
          },
        ),
        c,
      ),
      'Away 1m; +500 credits',
    );
  });

  test('names what was earned and where it went when credits were paid in '
      'on their own, so a fall does not read as a loss', () {
    final sum = summary(
      gained: -2.11e9,
      earned: 2.67e9,
      autoDelivered: {
        'orbital_station': {'credits': n(4.78e9)},
      },
      away: 3600,
    );
    expect(
      awayHeadline(sum, c),
      'Away 1h; earned 2.67B credits, 4.78B to Orbital Station, net -2.11B',
    );
    final both = summary(
      gained: 1e6,
      earned: 4e6,
      autoDelivered: {
        'orbital_station': {'hull_plate': n(5), 'credits': n(2e6)},
        'mass_driver': {'credits': n(1e6)},
      },
    );
    expect(
      awayHeadline(both, c),
      'Away 1m; earned 4M credits, 2M to Orbital Station and 1M to Mass '
      'Driver, net +1M',
    );
  });

  test('a megaproject the content does not have is named by its id', () {
    final sum = summary(
      gained: 1,
      earned: 3,
      autoDelivered: {
        'dyson': {'credits': n(2)},
      },
    );
    expect(
      awayHeadline(sum, c),
      'Away 1m; earned 3 credits, 2 to dyson, net +1',
    );
  });

  test('a catch-up paying credits in reads as earned and paid', () {
    final s = e.newGame(1);
    final f = s.faction('player');
    f.megaprojectLevels['orbital_station'] = 1;
    e.apply(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
    e.apply(
      s,
      const SetMegaprojectAutoCommand('player', 'mass_driver', credits: true),
    );
    f.credits = n(5000);
    final sum = e.catchUpOffline(s, 3600);
    expect(sum.creditsPaidIn > n(5000), isTrue);
    expect(
      awayHeadline(sum, c),
      'Away 1h; earned ${formatNumber(sum.creditsEarned)} credits, '
      '${formatNumber(sum.creditsPaidIn)} to Mass Driver, net '
      '${formatNumber(sum.creditsGained)}',
    );
    expect(sum.creditsGained.isNegative, isTrue);
  });
}
