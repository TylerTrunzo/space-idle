import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final content = shippedContent();

  test('new game owns only home body', () {
    final s = newGameState(content, 1);
    expect(s.body('kora').ownerId, 'player');
    expect(s.bodies.where((b) => b.ownerId != null).map((b) => b.id), ['kora']);
  });

  test('new game has starting buildings and crew', () {
    final s = newGameState(content, 1);
    final f = content.galaxy.factions.first;
    final kora = s.body('kora');
    expect(kora.buildings.map((b) => b.defId), [
      for (final b in f.buildings) b.defId,
    ]);
    expect(kora.buildings.map((b) => b.depositResourceId), [
      for (final b in f.buildings) b.depositResourceId,
    ]);
    expect(kora.buildings.map((b) => b.crew), [
      for (final b in f.buildings) b.crew,
    ]);
    expect(kora.buildings.map((b) => b.id).toSet().length, f.buildings.length);
    expect(s.faction('player').baseCrew, f.baseCrew);
    expect(s.faction('player').credits.toJson(), f.credits.toJson());
    expect(kora.stock['iron_ore']!.toJson(), f.stock['iron_ore']!.toJson());
    expect(kora.buildings.first.levels.keys.toList(), UpgradeTrack.values);
  });

  test('json round trip is identical', () {
    final s = newGameState(content, 7)
      ..time = 12.5
      ..routes.add(
        RouteState(
          id: 'r1',
          ownerId: 'player',
          fromBodyId: 'kora',
          toBodyId: 'brine',
          resourceId: 'iron_ore',
          ratePerSecond: BigNum.parse('2.5'),
          cargoShips: 2,
        ),
      )
      ..shipments.add(
        Shipment(
          routeId: 'r1',
          fromBodyId: 'kora',
          toBodyId: 'brine',
          ownerId: 'player',
          resourceId: 'iron_ore',
          amount: BigNum.parse('5'),
          departAt: 2.25,
          arriveAt: 20.25,
        ),
      );
    s.market.saturation['iron_ore'] = 0.75;
    s.faction('player').reachedMilestones.addAll(['b', 'a']);
    s
        .faction('player')
        .autoSell
        .add(
          AutoSellRule(
            bodyId: 'kora',
            resourceId: 'iron_ore',
            keepAtLeast: BigNum.parse('10'),
          ),
        );
    final b = s.body('kora').buildings.first
      ..lastRunFraction = 0.5
      ..lastLimitReason = 'crew';
    b.levels[UpgradeTrack.speed] = 3;
    final once = jsonEncode(s.toJson());
    final back = GameState.fromJson(jsonDecode(once) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), once);
    expect(back.body('kora').buildings.first.lastLimitReason, 'crew');
    expect(back.body('kora').buildings.first.levels[UpgradeTrack.speed], 3);
  });

  test('lifetime credits and produced round trip and copy deeply', () {
    final s = newGameState(content, 3);
    s.faction('player')
      ..lifetimeCredits = BigNum.parse('1.5e6')
      ..lifetimeProduced['steel'] = BigNum.parse('42')
      ..lifetimeProduced['iron_ore'] = BigNum.parse('7');
    final once = jsonEncode(s.toJson());
    final back = GameState.fromJson(jsonDecode(once) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), once);
    expect(back.faction('player').lifetimeCredits, BigNum.parse('1.5e6'));
    expect(back.faction('player').lifetimeProduced.keys, ['steel', 'iron_ore']);
    final t = s.copy();
    t.faction('player')
      ..lifetimeCredits = BigNum.zero()
      ..lifetimeProduced['steel'] = BigNum.zero();
    expect(jsonEncode(s.toJson()), once);
  });

  test('seen bottlenecks round trip and copy deeply', () {
    final s = newGameState(content, 3)..time = 100;
    s.faction('player').seenBottlenecks.addAll([
      SeenBottleneck(
        kind: 'noCrew',
        bodyId: 'kora',
        buildingId: 'b1',
        firstSeenAt: 60,
      ),
      SeenBottleneck(kind: 'crewShortage', firstSeenAt: 0),
    ]);
    final once = jsonEncode(s.toJson());
    final back = GameState.fromJson(jsonDecode(once) as Map<String, Object?>);
    expect(jsonEncode(back.toJson()), once);
    final t = s.copy();
    t.faction('player').seenBottlenecks.clear();
    expect(jsonEncode(s.toJson()), once);
    expect(SaveCodec.decode(once, content), isA<SaveOk>());
  });

  test('copy is a deep copy equal to a save round trip', () {
    final s = newGameState(content, 3)
      ..routes.add(
        RouteState(
          id: 'r1',
          ownerId: 'player',
          fromBodyId: 'kora',
          toBodyId: 'brine',
          resourceId: 'iron_ore',
          ratePerSecond: BigNum.parse('2.5'),
          cargoShips: 2,
        ),
      )
      ..shipments.add(
        Shipment(
          routeId: 'r1',
          fromBodyId: 'kora',
          toBodyId: 'brine',
          ownerId: 'player',
          resourceId: 'iron_ore',
          amount: BigNum.parse('5'),
          departAt: 1,
          arriveAt: 20,
        ),
      )
      ..time = 12.5;
    s.market.saturation['iron_ore'] = 0.75;
    s.faction('player')
      ..reachedMilestones.add('a')
      ..autoSell.add(
        AutoSellRule(
          bodyId: 'kora',
          resourceId: 'iron_ore',
          keepAtLeast: BigNum.parse('10'),
        ),
      );
    s.body('kora').buildings.first
      ..lastRunFraction = 0.5
      ..lastLimitReason = 'input:iron_ore';
    final once = jsonEncode(s.toJson());

    final t = s.copy();
    expect(jsonEncode(t.toJson()), once);

    // Changing every mutable part of the copy leaves the original alone.
    t
      ..time = 99
      ..rngState = 1
      ..nextId = 999;
    t.newId('x');
    t.market.saturation['iron_ore'] = 0.2;
    t.faction('player')
      ..credits = BigNum.zero()
      ..baseCrew = 0
      ..reachedMilestones.add('b')
      ..autoSell.first.keepAtLeast = BigNum.zero();
    final kora = t.body('kora')
      ..ownerId = null
      ..stock['iron_ore'] = BigNum.zero();
    kora.buildings.first
      ..crew = 0
      ..levels[UpgradeTrack.speed] = 7;
    kora.buildings.removeLast();
    kora.deposits.clear();
    t.routes.first
      ..ratePerSecond = BigNum.zero()
      ..cargoShips = 9;
    t.shipments.first.amount = BigNum.zero();
    t.routes.clear();
    t.shipments.clear();
    t.factions.first.autoSell.clear();
    expect(jsonEncode(s.toJson()), once);
  });

  test('newId is deterministic', () {
    final a = newGameState(content, 42);
    final b = newGameState(content, 42);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect(a.newId('x'), b.newId('x'));
    expect(a.newId('x'), isNot('x${a.nextId}'));
  });

  test('rngState comes from the seed', () {
    expect(newGameState(content, 5).rngState, Rng(5).state);
  });
}
