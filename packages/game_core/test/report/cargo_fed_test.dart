import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../sim/economy_fixture.dart' as fx;
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

  /// Each building in [s] that uses a resource one of `player`'s routes
  /// brings to its body, with the report's run fraction and its mean over
  /// ten 60 s ticks of play from [s].
  List<(String, double, double)> cargoFed(GameState s) {
    final fed = <String>{};
    for (final r in s.routes) {
      if (r.ownerId != 'player') continue;
      for (final b in s.body(r.toBodyId).buildings) {
        if (c.buildings[b.defId]!.inputs.containsKey(r.resourceId)) {
          fed.add(b.id);
        }
      }
    }
    final report = buildFlowReport(s, c, 'player');
    final played = s.copy();
    final ran = <String, double>{};
    for (var i = 0; i < 10; i++) {
      e.tick(played, 60);
      for (final b in played.bodies) {
        for (final x in b.buildings) {
          ran[x.id] = (ran[x.id] ?? 0) + x.lastRunFraction / 10;
        }
      }
    }
    return [
      for (final body in report.bodies)
        for (final st in body.buildings)
          if (fed.contains(st.buildingId) && st.runFraction != null)
            (
              '${body.bodyId} ${st.buildingId}',
              st.runFraction!,
              ran[st.buildingId]!,
            ),
    ];
  }

  // Two states where a shallower consumer of a short store gets more of
  // it in play than its part of the store's use: Vastmere's Reactor Works
  // (b63) on the 336 h fixture, which play runs at 0.57, and Cinder's
  // Station Docks on the balanced bot's day-14 state, seed 1 (played on the
  // shipped content at aaee5f6), which play runs at 1.00. The report's
  // proportional share once read them at 0.30 and 0.48.
  for (final name in ['casual_s1_336h', 'balanced_s1_d14']) {
    test('on $name, every cargo-fed building reads within 0.05 of ten 60 s '
        'ticks of play', () {
      final s =
          (SaveCodec.decode(
                    File('test/fixtures/$name.json').readAsStringSync(),
                    c,
                  )
                  as SaveOk)
              .state;
      final fed = cargoFed(s);
      expect(fed, isNotEmpty);
      for (final (id, shown, real) in fed) {
        expect(shown, closeTo(real, 0.05), reason: '$id: $real in play');
      }
    });
  }

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

  group('a short store fed by lots bigger than a minute of its use', () {
    // On b, a press (0.5 ore a second, depth 1) and a forge (0.5 ore and
    // 0.5 plate a second, depth 2, so it runs after the press). b's store
    // holds at most [cap] of each good. Ore comes from a, a trip of 120 s
    // away, on a route the cap holds to one lot a trip; plate comes
    // steadily. A real 60 s tick as a lot lands runs the press on its 30
    // and leaves the forge the rest; the next tick has nothing. One step
    // of the average supply, [cap] over two minutes, gave the press all of
    // it and the forge none.
    final content = () {
      final base = fx.pressContent(baseStorageCap: 45);
      return Content(
        rules: base.rules,
        resources: {
          ...base.resources,
          'bar': ResourceDef(
            id: 'bar',
            name: 'Bar',
            tier: 2,
            basePrice: fx.n(1),
          ),
        },
        buildings: {
          ...base.buildings,
          'forge': BuildingDef(
            id: 'forge',
            name: 'Forge',
            kind: BuildingKind.factory,
            cycleSeconds: 2,
            inputs: const {'ore': 1, 'plate': 1},
            outputs: const {'bar': 1},
            crewSlots: 1,
            buildCost: const {},
          ),
        },
        bodyTypes: base.bodyTypes,
        galaxy: base.galaxy,
        milestones: base.milestones,
      );
    }();
    final play = GameEngine(content);

    GameState game() {
      final t = play.newGame(1);
      t.body('b')
        ..ownerId = 'p'
        ..buildings.addAll([
          BuildingState(id: 'press', defId: 'press', crew: 1),
          BuildingState(id: 'forge', defId: 'forge', crew: 1),
        ]);
      for (final (id, res, stop) in [('r1', 'ore', 1), ('r2', 'plate', null)]) {
        t.routes.add(
          RouteState(
            id: id,
            ownerId: 'p',
            fromBodyId: 'a',
            toBodyId: 'b',
            resourceId: res,
            ratePerSecond: fx.n(2),
            cargoShips: 1,
            stopAtDestination: stop == null ? null : fx.n(stop),
          ),
        );
      }
      void stock() => t.body('a').stock
        ..['ore'] = fx.n(1e7)
        ..['plate'] = fx.n(1e7);
      stock();
      play.advance(t, 1200);
      stock();
      return t;
    }

    // Both phases: a lot just landed, and one a minute out.
    for (final offset in [0, 1]) {
      test('reads as 60 s real steps run it, $offset min after a landing '
          'step', () {
        final s = game();
        play.advance(s, 60.0 * offset);
        final shown = {
          for (final st in buildFlowReport(
            s,
            content,
            'p',
          ).bodies.singleWhere((b) => b.bodyId == 'b').buildings)
            st.buildingId: st.runFraction!,
        };
        final played = s.copy();
        final ran = <String, double>{};
        for (var i = 0; i < 10; i++) {
          play.tick(played, 60);
          for (final b in played.body('b').buildings) {
            ran[b.id] = (ran[b.id] ?? 0) + b.lastRunFraction / 10;
          }
        }
        // Play: the press runs every other tick, the forge on the rest of
        // those lots: 0.5 and 0.25.
        expect(ran['press'], closeTo(0.5, 1e-9));
        expect(ran['forge'], closeTo(0.25, 1e-9));
        for (final id in ['press', 'forge']) {
          expect(shown[id], closeTo(ran[id]!, 0.05), reason: id);
        }
      });
    }
  });
}
