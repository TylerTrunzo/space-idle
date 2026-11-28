import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:game_core/src/sim/contracts.dart' show incomeBasis;
import 'package:test/test.dart';

import '../state/helpers.dart';

/// Plays [s] for [hours] in ticks of 1 to 30 minutes drawn from [rng],
/// posting each contract refill itself between ticks: it works out the
/// income basis ([incomeBasis]) on the state, then posts with
/// [stepContracts], which reads the same state, so each new contract is
/// checked against the basis at the moment it was posted. Every contract
/// but the first the faction is ever offered (which has no cap, as in the
/// engine) must pay at most `rewardCapIncomeSeconds` of that basis (or
/// `minRewardCredits`, the least any reward pays). Each new contract is
/// discarded once checked, as the board it starts with is, so its slots
/// refill. Returns the contracts checked.
int _checkRewards(GameEngine e, GameState s, Rng rng, {required double hours}) {
  final c = e.content;
  final f = s.faction('player');
  // The board as found goes, so its slots refill within the run.
  for (final k in [...f.contracts]) {
    expect(e.apply(s, DiscardContractCommand(f.id, k.id)), isA<CommandOk>());
  }
  final end = s.time + hours * 3600;
  var checked = 0;
  while (s.time < end) {
    // The engine posts a refill due within a tick from the state partway
    // through it; held back here, it is posted between ticks instead.
    final refills = [...f.contractRefillAt];
    f.contractRefillAt.clear();
    e.tick(s, 60.0 * (1 + rng.nextInt(30)));
    f.contractRefillAt.addAll(refills);
    if (!refills.any((t) => t <= s.time)) continue;
    final basis = incomeBasis(s, c, f.id, buildFlowReport(s, c, f.id));
    final before = {for (final k in f.contracts) k.id};
    // Contracts the faction had been offered before this call: the first
    // it is ever offered is the one with no cap.
    var posted = f.contractsPosted;
    stepContracts(s, c, s.time);
    for (final k in [...f.contracts]) {
      if (before.contains(k.id)) continue;
      if (posted++ > 0) {
        final t = c.contractTemplates[k.templateId]!;
        final cap = basis
            .mulDouble(t.rewardCapIncomeSeconds!)
            .max(t.minRewardCredits);
        expect(
          k.rewardCredits <= cap,
          isTrue,
          reason:
              '${k.resourceId} at ${s.time / 3600} h: ${k.rewardCredits} '
              'against a cap of $cap (basis $basis)',
        );
        checked++;
      }
      expect(e.apply(s, DiscardContractCommand(f.id, k.id)), isA<CommandOk>());
    }
  }
  return checked;
}

void main() {
  // The balance target "no reward above 1 h of income" (findings §4) is
  // the engine's cap. A bot session reads the basis hours after a refill
  // is posted, when it can have swung severalfold (it counts what surplus
  // goods would sell for), so the target is checked here, at posting.
  test('every contract after the first pays at most the reward cap of the '
      'income basis it was posted at, on new games of several seeds', () {
    final c = shippedContent();
    final e = GameEngine(c);
    var checked = 0;
    for (var seed = 1; seed <= 6; seed++) {
      final s = e.newGame(seed);
      for (final id in ['iron_ore', 'copper_ore', 'steel']) {
        expect(
          e.apply(s, SetAutoSellCommand('player', 'kora', id, BigNum.from(0))),
          isA<CommandOk>(),
        );
      }
      checked += _checkRewards(e, s, Rng(seed), hours: 48);
    }
    expect(checked, greaterThan(30));
  });

  test('and on the saved mid-game states, over 24 h each', () {
    // The content those states were played with.
    final c = fixtureContent();
    final e = GameEngine(c);
    var checked = 0;
    var i = 0;
    for (final name in [
      'balanced_d7_md105',
      'balanced_day14_fed',
      'optimizer_r4_d11',
      'review_balanced_day14',
    ]) {
      final s =
          (SaveCodec.decode(
                    File('test/fixtures/$name.json').readAsStringSync(),
                    c,
                  )
                  as SaveOk)
              .state;
      checked += _checkRewards(e, s, Rng(++i), hours: 24);
    }
    expect(checked, greaterThan(20));
  });
}
