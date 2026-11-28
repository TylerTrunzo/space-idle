import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

/// The report's sample against real play for buildings fed by cargo.
void main() {
  final c = shippedContent();
  final e = GameEngine(c);

  // The casual bot's state at its 336 h check-in, seed 1 (played at
  // 6f6902f), in its Orbital Station stall: Vastmere's two Drone Works
  // need magnets, which one route brings from Hollow Reach at 40 a second,
  // and Vastmere's Reactor Works, a shallower recipe, use them first. Play
  // runs the Drone Works at 0%; the report's full-step share once read
  // them at 30%, with 16 drones a second made.
  GameState fixture() =>
      (SaveCodec.decode(
                File('test/fixtures/casual_s1_336h.json').readAsStringSync(),
                c,
              )
              as SaveOk)
          .state;

  test('a cargo-fed building another consumer starves first reads as 60 s '
      'real steps run it', () {
    final s = fixture();
    final drones = [
      for (final b in s.body('vastmere').buildings)
        if (b.defId == 'drone_works') b.id,
    ];
    expect(drones, hasLength(2));
    final report = buildFlowReport(s, c, 'player');
    final shown = {
      for (final st
          in report.bodies.singleWhere((b) => b.bodyId == 'vastmere').buildings)
        if (drones.contains(st.buildingId)) st.buildingId: st.runFraction!,
    };
    // Ten minutes of 60 s ticks: the Drone Works' run fraction each tick,
    // and the drones made.
    final played = s.copy();
    final ran = {for (final id in drones) id: <double>[]};
    final before = played.faction('player').lifetimeProduced['survey_drone']!;
    for (var i = 0; i < 10; i++) {
      e.tick(played, 60);
      for (final b in played.body('vastmere').buildings) {
        ran[b.id]?.add(b.lastRunFraction);
      }
    }
    final made =
        (played.faction('player').lifetimeProduced['survey_drone']! - before)
            .toDouble() /
        600;
    for (final id in drones) {
      final real = ran[id]!.reduce((a, b) => a + b) / ran[id]!.length;
      expect(shown[id], closeTo(real, 0.03), reason: '$id: $real in play');
    }
    // Drones a second, within a few percent of the Drone Works' full rate.
    final full = drones.fold(0.0, (t, id) {
      final b = s.body('vastmere').buildings.singleWhere((x) => x.id == id);
      return t +
          fullRateFlow(
            c,
            s.body('vastmere'),
            b,
            1,
            crewEfficiency(s, c, 'player'),
            bonuses: bonusesFor(s, c, 'player'),
          ).outputs['survey_drone']!.toDouble();
    });
    expect(
      report.producedPerSec('survey_drone').toDouble(),
      closeTo(made, full * 0.03),
      reason: '$made a second in play, of $full at full rate',
    );
  });
}
