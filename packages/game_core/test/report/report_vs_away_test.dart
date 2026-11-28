import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

/// The fixtures' content ([fixtureBundle]) with the Mass Driver's sale
/// price at [factor] a level on tiers 1-2.
Content withDriverFactor(double factor) {
  final b = fixtureBundle();
  final driver = (b['megaprojects']! as List)
      .cast<Map<String, Object?>>()
      .firstWhere((m) => m['id'] == 'mass_driver');
  driver['bonusesPerLevel'] = [
    {
      'kind': 'salePriceMultiplier',
      'amount': factor,
      'appliesToMinTier': 1,
      'appliesToMaxTier': 2,
    },
  ];
  return (Content.fromBundle(b) as ContentOk).content;
}

void main() {
  // The balanced bot's state at the end of day 7, seed 1, played with the
  // Mass Driver at each factor (stage 1.7 task 3, fix round 2). At ×1.2
  // the Mass Driver finishes taking hull plates 13 minutes in, and the
  // plates, unsold for days, then sell far above their settled price for
  // a while: the report's short run caught that and read 26% high.
  for (final (factor, name) in [
    (1.05, 'md105'),
    (1.15, 'md115'),
    (1.2, 'md12'),
    (1.25, 'md125'),
  ]) {
    test('at a Mass Driver factor of $factor, credits a second are within 8% '
        'of what 2.5 h away earns', () {
      final c = withDriverFactor(factor);
      final s =
          (SaveCodec.decode(
                    File(
                      'test/fixtures/balanced_d7_$name.json',
                    ).readAsStringSync(),
                    c,
                  )
                  as SaveOk)
              .state;
      final shown = buildFlowReport(s, c, 'player').creditsPerSec.toDouble();
      final away = GameEngine(c).catchUpOffline(s, 9000, capSeconds: 9000);
      final earned = away.creditsEarned.toDouble() / 9000;
      expect(earned, greaterThan(0));
      expect(
        shown,
        closeTo(earned, earned * 0.08),
        reason: '$shown vs $earned',
      );
    });
  }

  // The casual bot's states at the 144 h and 180 h check-ins, seed 1,
  // played on the shipped content at bab81a2 (before contracts left the
  // goods of a fed megaproject alone). The Orbital Station is fed survey
  // drones near ready and a contract for drones holds every one. With the
  // board cleared, the report's short run once handed those drones to the
  // station, which then never happened in play, and read 52% and 58% low.
  for (final hours in [144, 180]) {
    test('with a contract holding a fed megaproject\'s goods, credits a '
        'second at $hours h are within 8% of what 2.5 h away earns', () {
      final c = shippedContent();
      final s =
          (SaveCodec.decode(
                    File(
                      'test/fixtures/casual_s1_${hours}h.json',
                    ).readAsStringSync(),
                    c,
                  )
                  as SaveOk)
              .state;
      final shown = buildFlowReport(s, c, 'player').creditsPerSec.toDouble();
      final away = GameEngine(c).catchUpOffline(s, 9000, capSeconds: 9000);
      final earned = away.creditsEarned.toDouble() / 9000;
      expect(earned, greaterThan(0));
      expect(
        shown,
        closeTo(earned, earned * 0.08),
        reason: '$shown vs $earned',
      );
    });
  }
}
