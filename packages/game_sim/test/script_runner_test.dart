import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:game_sim/src/script_runner.dart';
import 'package:test/test.dart';

ScriptRunner _runner() {
  final result = Content.fromBundle(loadContentDir('../../content'));
  final content = (result as ContentOk).content;
  final engine = GameEngine(content);
  return ScriptRunner(engine, engine.newGame(1));
}

/// Kora's entry in a `state` reply.
Map<String, Object?> _kora(Map<String, Object?> state) =>
    (state['bodies']! as List).cast<Map<String, Object?>>().singleWhere(
      (b) => b['id'] == 'kora',
    );

void main() {
  test('advance then state shows time passing and stock/credits', () {
    final r = _runner();
    final before = r.handle({'cmd': 'state'});
    expect(before['ok'], isTrue);
    expect(r.handle({'cmd': 'advance', 'seconds': 600})['ok'], isTrue);
    final after = r.handle({'cmd': 'state'});
    expect(after['time'], 600.0);
    final credits = after['credits']! as Map<String, Object?>;
    expect(credits['display'], isA<String>());
    expect(
      BigNum.fromJson(credits['value']! as String) >=
          BigNum.fromJson(
            (before['credits']! as Map<String, Object?>)['value']! as String,
          ),
      isTrue,
    );
    final bodies = after['bodies']! as List;
    expect(bodies, hasLength(5));
  });

  test('stock grows after building an extractor and advancing', () {
    final r = _runner();
    final body = _kora(r.handle({'cmd': 'state'}));
    final content = r.engine.content;
    final def = content.buildings.values.firstWhere(
      (d) => d.kind == BuildingKind.extractor,
    );
    final b = r.state.bodies.firstWhere((x) => x.id == body['id']);
    final dep = b.deposits
        .firstWhere((d) => def.extracts.contains(d.resourceId))
        .resourceId;
    final built = r.handle({
      'cmd': 'build',
      'bodyId': b.id,
      'defId': def.id,
      'depositResourceId': dep,
    });
    expect(built['ok'], isTrue, reason: '$built');
    r.handle({
      'cmd': 'assignCrew',
      'buildingId': built['createdId'],
      'crew': 1,
    });
    r.handle({'cmd': 'advance', 'seconds': 600});
    final stock = _kora(r.handle({'cmd': 'state'}));
    expect((stock['stock']! as Map), isNotEmpty);
    expect(r.handle({'cmd': 'report'})['ok'], isTrue);
    expect(r.handle({'cmd': 'costs'})['ok'], isTrue);
  });

  test('report and state carry rates, credits per second and crew', () {
    final r = _runner();
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'steel',
      'keepAtLeast': '0',
    });
    final rep = r.handle({'cmd': 'report'});
    expect((rep['creditsPerSec']! as Map)['display'], isA<String>());
    final mine =
        (((rep['bodies']! as List).first as Map)['buildings']! as List).first
            as Map;
    expect(mine['effectiveFraction'], 1.0);
    expect((mine['outputs']! as Map).keys, ['iron_ore']);
    expect(mine['inputs'], isEmpty);
    expect(r.handle({'cmd': 'state'})['crew'], {
      'base': 20,
      'supported': 20,
      'assigned': 3,
      'free': 17,
      'overAssigned': 0,
    });
  });

  test('crew free never goes negative; over-assigned crew is counted', () {
    final r = _runner();
    r.state.faction('player').baseCrew = 1;
    expect(r.handle({'cmd': 'state'})['crew'], {
      'base': 1,
      'supported': 1,
      'assigned': 3,
      'free': 0,
      'overAssigned': 2,
    });
  });

  test('state describes every body, owned or not', () {
    final st = _runner().handle({'cmd': 'state'});
    final bodies = (st['bodies']! as List).cast<Map<String, Object?>>();
    expect(bodies.map((b) => b['id']), [
      'cinder',
      'kora',
      'hollow_reach',
      'vastmere',
      'brine',
    ]);
    final kora = _kora(st);
    expect(kora['type'], 'Rocky World');
    expect(kora['owner'], 'player');
    expect(kora['deposits'], [
      {'resourceId': 'iron_ore', 'name': 'Iron Ore', 'richness': 1.0},
      {'resourceId': 'copper_ore', 'name': 'Copper Ore', 'richness': 0.8},
      {'resourceId': 'silicon', 'name': 'Silicon', 'richness': 0.7},
    ]);
    expect(kora['slots'], {'used': 3, 'total': 12});
    expect((kora['storageCap']! as Map)['display'], '1K');
    expect((kora['stock']! as Map).keys, ['iron_ore', 'cargo_ship']);
    final cinder = bodies.first;
    expect(cinder['owner'], isNull);
    expect(cinder['type'], 'Volcanic World');
    expect(cinder['slots'], {'used': 0, 'total': 6});
    expect(cinder.containsKey('stock'), isFalse);
  });

  test('state lists routes, milestones and prices of goods held', () {
    final r = _runner();
    r.state.body('hollow_reach').ownerId = 'player';
    r.state.body('kora').stock['cargo_ship'] = BigNum.from(2.6);
    final route = r.handle({
      'cmd': 'createRoute',
      'fromBodyId': 'kora',
      'toBodyId': 'hollow_reach',
      'resourceId': 'iron_ore',
      'ratePerSecond': '0.5',
      'cargoShips': 1,
    });
    r.handle({'cmd': 'advance', 'seconds': 600});
    final st = r.handle({'cmd': 'state'});
    expect(st['routes'], [
      {
        'id': route['createdId'],
        'from': 'kora',
        'to': 'hollow_reach',
        'resourceId': 'iron_ore',
        'ratePerSecond': {'value': '5e-1', 'display': '0.5'},
        'cargoShips': 1,
        'stopAtDestination': null,
        'paused': false,
        'inFlight': {'value': '0', 'display': '0'},
        'travelTime': '2m',
      },
    ]);
    expect(st['milestones'], [
      {'id': 'first_steel', 'name': 'First Foundry'},
      {'id': 'own_2_bodies', 'name': 'First Claim'},
    ]);
    final market = st['market']! as Map;
    expect(market.keys, containsAll(['iron_ore', 'steel', 'cargo_ship']));
    expect(market['steel'], {
      'price': {'value': '6e0', 'display': '6'},
      'saturation': 1.0,
    });
    // Cargo ships are whole units in state: 1.6 shows as 1.
    expect(
      ((_kora(st)['stock']! as Map)['cargo_ship']! as Map)['display'],
      '1',
    );
    expect(st['notes'], isNotEmpty);
  });

  test('state shows what each auto-sell rule keeps, and why', () {
    final r = _runner();
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'iron_ore',
      'keepAtLeast': '10',
    });
    final rule = r.state.faction('player').autoSell.single;
    final keep = autoSellKeep(r.state, r.engine.content, rule, 60);
    // Kora's smelter uses iron ore, so the rule keeps a minute of it too.
    expect(keep.localUse > const BigNum.zero(), isTrue);
    final rules = (r.handle({'cmd': 'state'})['autoSell']! as List)
        .cast<Map<String, Object?>>();
    expect(rules.single['bodyId'], 'kora');
    expect(rules.single['resourceId'], 'iron_ore');
    expect(
      (rules.single['keeps']! as Map)['display'],
      formatNumber(keep.keeps),
    );
    expect(
      rules.single['text'],
      'keeps ${formatNumber(keep.keeps)} (keepAtLeast 10 + '
      '${formatNumber(keep.localUse)} local use)',
    );
    final cap = storageCap(r.state, r.engine.content, r.state.body('kora'));
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'iron_ore',
      'keepAtLeast': (cap - BigNum.from(1)).toJson(),
    });
    final capped = (r.handle({'cmd': 'state'})['autoSell']! as List).single;
    expect(
      (capped as Map)['text'],
      endsWith('local use, cut to the storage cap)'),
    );
  });

  test('claim, demolish and route replies say what they took and gave', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    final claim = r.handle({
      'cmd': 'claimBody',
      'bodyId': 'brine',
      'sourceBodyId': 'kora',
    });
    expect(claim['ok'], isTrue);
    expect(
      claim['message'],
      'Started claiming Brine for 5K credits (no kits needed); done in 30m',
    );
    expect(claim['createdId'], startsWith('p'));
    expect((claim['spent']! as Map).keys, ['credits']);
    // A route needs Brine owned: the claim has to complete first.
    r.handle({'cmd': 'advance', 'seconds': 1860});
    final demolish = r.handle({'cmd': 'demolish', 'buildingId': 'b3'});
    expect(
      demolish['message'],
      'Demolished Smelter on Kora (b3); got back 75 credits',
    );
    expect(((demolish['gained']! as Map)['credits']! as Map)['display'], '75');
    r.state.body('kora').stock['cargo_ship'] = BigNum.from(1);
    final route = r.handle({
      'cmd': 'createRoute',
      'fromBodyId': 'kora',
      'toBodyId': 'brine',
      'resourceId': 'steel',
      'ratePerSecond': '0.2',
      'cargoShips': 1,
    });
    expect(
      route['message'],
      'Created route ${route['createdId']}: Steel from Kora to Brine at 0.2/s '
      'with 1 Cargo Ship',
    );
    expect(
      ((route['spent']! as Map)['kora/cargo_ship']! as Map)['display'],
      '1',
    );
  });

  test('routes take a stop level, can be changed, and ships can be moved', () {
    final r = _runner();
    r.state.body('hollow_reach').ownerId = 'player';
    r.state.body('kora').stock['cargo_ship'] = BigNum.from(5);
    final route = r.handle({
      'cmd': 'createRoute',
      'fromBodyId': 'kora',
      'toBodyId': 'hollow_reach',
      'resourceId': 'iron_ore',
      'ratePerSecond': '0.5',
      'cargoShips': 1,
      'stopAtDestination': '20',
    });
    final id = route['createdId'];
    expect(
      route['message'],
      'Created route $id: Iron Ore from Kora to Hollow Reach at 0.5/s with '
      '1 Cargo Ship, pausing while Hollow Reach holds 20',
    );
    final update = r.handle({
      'cmd': 'updateRoute',
      'routeId': id,
      'ratePerSecond': '2',
      'cargoShips': 2,
    });
    expect(
      update['message'],
      'Updated route $id: Iron Ore from Kora to Hollow Reach at 2/s with '
      '2 Cargo Ships, pausing while Hollow Reach holds 20',
    );
    expect(
      ((update['spent']! as Map)['kora/cargo_ship']! as Map)['display'],
      '1',
    );
    r.handle({'cmd': 'advance', 'seconds': 60});
    final routes = r.handle({'cmd': 'state'})['routes']! as List;
    expect((routes.single as Map)['stopAtDestination'], {
      'value': '2e1',
      'display': '20',
    });
    // Nothing on Hollow Reach uses iron ore, so all 20 in flight count
    // toward the stop: the route waits for them to land.
    expect((routes.single as Map)['paused'], isTrue);
    expect(((routes.single as Map)['inFlight']! as Map)['display'], '20');
    final reachCap = storageCap(
      r.state,
      r.engine.content,
      r.state.body('hollow_reach'),
    );
    final tooHigh = r.handle({
      'cmd': 'updateRoute',
      'routeId': id,
      'stopAtDestination': (reachCap * BigNum.from(10)).toJson(),
    });
    expect(
      tooHigh['message'],
      'Updated route $id: Iron Ore from Kora to Hollow Reach at 2/s with '
      '2 Cargo Ships, pausing while Hollow Reach holds '
      '${formatNumber(reachCap)}. The stop level was cut to Hollow Reach\'s '
      'storage cap: stock above it is wasted',
    );
    final off = r.handle({
      'cmd': 'updateRoute',
      'routeId': id,
      'removeStopAtDestination': true,
    });
    expect(
      off['message'],
      'Updated route $id: Iron Ore from Kora to Hollow Reach at 2/s with '
      '2 Cargo Ships',
    );
    final move = r.handle({
      'cmd': 'moveShips',
      'fromBodyId': 'kora',
      'toBodyId': 'hollow_reach',
      'count': 2,
    });
    expect(
      move['message'],
      'Sent 2 Cargo Ships from Kora to Hollow Reach; they land in 2m',
    );
    expect(move['createdId'], isA<String>());
    // Usable at the time the reply gave: 2 minutes on.
    r.handle({'cmd': 'advance', 'seconds': 120});
    final reuse = r.handle({
      'cmd': 'createRoute',
      'fromBodyId': 'hollow_reach',
      'toBodyId': 'kora',
      'resourceId': 'iron_ore',
      'ratePerSecond': '0.1',
      'cargoShips': 2,
    });
    expect(reuse['ok'], isTrue, reason: '${reuse['message']}');
    r.handle({'cmd': 'removeRoute', 'routeId': reuse['createdId']});
    final st = r.handle({'cmd': 'state'});
    final reach = (st['bodies']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((b) => b['id'] == 'hollow_reach');
    expect(((reach['stock']! as Map)['cargo_ship']! as Map)['display'], '2');
  });

  test('a build reply names the building and the crew it took', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    final yard = r.handle({
      'cmd': 'build',
      'bodyId': 'kora',
      'defId': 'shipyard',
    });
    expect(
      yard['message'],
      'Built Shipyard on Kora (${yard['createdId']}) with 2 of 2 crew',
    );
    final empty = r.handle({
      'cmd': 'build',
      'bodyId': 'kora',
      'defId': 'shipyard',
      'autoCrew': false,
    });
    expect(
      empty['message'],
      'Built Shipyard on Kora (${empty['createdId']}) with 0 of 2 crew',
    );
    r.state.body('kora').stock['steel'] = BigNum.from(50);
    final depot = r.handle({
      'cmd': 'build',
      'bodyId': 'kora',
      'defId': 'depot',
    });
    expect(depot['message'], 'Built Depot on Kora (${depot['createdId']})');
  });

  test('a claim after the first one says the kits it took', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    r.state.body('brine').ownerId = 'player';
    r.state.body('kora').stock['outpost_kit'] = BigNum.from(10);
    final claim = r.handle({
      'cmd': 'claimBody',
      'bodyId': 'cinder',
      'sourceBodyId': 'kora',
    });
    expect(
      claim['message'],
      'Started claiming Cinder for 40K credits and 10 Outpost Kit; done in 1h',
    );
  });

  test('an extra slot reply says when it arrives', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    final out = r.handle({'cmd': 'expandSlots', 'bodyId': 'kora'});
    expect(
      out['message'],
      'Started an extra build slot on Kora for 50K credits; done in 1h',
    );
    final again = r.handle({'cmd': 'expandSlots', 'bodyId': 'kora'});
    expect(again['error'], 'projectInProgress');
  });

  test('state lists running projects with time left, soonest first', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    final slot = r.handle({'cmd': 'expandSlots', 'bodyId': 'kora'});
    final claim = r.handle({
      'cmd': 'claimBody',
      'bodyId': 'brine',
      'sourceBodyId': 'kora',
    });
    r.handle({'cmd': 'advance', 'seconds': 600});
    expect(r.handle({'cmd': 'state'})['projects'], [
      {
        'id': claim['createdId'],
        'kind': 'claim',
        'targetId': 'brine',
        'name': 'Brine',
        'startedAt': 0.0,
        'finishAt': 1800.0,
        'secondsLeft': 1200.0,
        'timeLeft': '20m',
      },
      {
        'id': slot['createdId'],
        'kind': 'expandSlots',
        'targetId': 'kora',
        'name': 'Kora',
        'startedAt': 0.0,
        'finishAt': 3600.0,
        'secondsLeft': 3000.0,
        'timeLeft': '50m',
      },
    ]);
    r.handle({'cmd': 'advance', 'seconds': 3600});
    expect(r.handle({'cmd': 'state'})['projects'], isEmpty);
  });

  test('away lists the projects that completed', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    r.handle({'cmd': 'claimBody', 'bodyId': 'brine', 'sourceBodyId': 'kora'});
    final out = r.handle({'cmd': 'away', 'seconds': 3600});
    expect(out['projectsCompleted'], [
      {
        'kind': 'claim',
        'targetId': 'brine',
        'name': 'Brine',
        'message': 'Brine claimed',
      },
    ]);
  });

  test('away lists the contracts posted while away', () {
    final r = _runner();
    final out = r.handle({'cmd': 'away', 'seconds': 14400 * 2 + 60});
    final board = r.state.faction('player').contracts;
    expect(board, hasLength(3));
    final posted = (out['contractsPosted']! as List)
        .cast<Map<String, Object?>>();
    expect([for (final k in posted) k['id']], [for (final k in board) k.id]);
    expect(posted.first.keys, [
      'id',
      'resourceId',
      'resource',
      'quantity',
      'reward',
    ]);
  });

  test('a command on a body being claimed says it is still being claimed', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    r.handle({'cmd': 'claimBody', 'bodyId': 'brine', 'sourceBodyId': 'kora'});
    final out = r.handle({'cmd': 'expandSlots', 'bodyId': 'brine'});
    expect(out['error'], 'stillClaiming');
    expect(out['message'], 'Brine is still being claimed (30m left)');
  });

  test('costs show no claim once every body is owned', () {
    final r = _runner();
    expect((r.handle({'cmd': 'costs'})['claim']! as Map).keys, ['credits']);
    for (final b in r.state.bodies) {
      b.ownerId = 'player';
    }
    expect(r.handle({'cmd': 'costs'})['claim'], 'no bodies left to claim');
  });

  test('costs include the next extra build slot of each owned body', () {
    final costs = _runner().handle({'cmd': 'costs'});
    expect((costs['extraSlot']! as Map).keys, ['kora']);
    expect(
      (((costs['extraSlot']! as Map)['kora']! as Map)['credits']!
          as Map)['display'],
      '50K',
    );
  });

  /// Puts the goods for the next Orbital Station stage on Kora and enough
  /// credits in hand.
  ///
  /// [level], when given, picks the stage instead: the level it starts
  /// from.
  void stockStation(ScriptRunner r, {int? level}) {
    final c = r.engine.content;
    final station = c.megaprojects['orbital_station']!;
    level ??=
        r.state.faction('player').megaprojectLevels['orbital_station'] ?? 0;
    for (final MapEntry(:key, :value) in megaprojectCost(
      c,
      station,
      level,
    ).entries) {
      if (key != 'credits') r.state.body('kora').stock[key] = value;
    }
    r.state.faction('player').credits = BigNum.from(1e9);
  }

  test('a megaproject stage starts, shows in state and raises the level', () {
    final r = _runner();
    expect(r.handle({'cmd': 'state'})['megaprojects'], [
      {'id': 'orbital_station', 'name': 'Orbital Station', 'level': 0},
    ]);
    stockStation(r);
    final out = r.handle({
      'cmd': 'startMegaprojectStage',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
    });
    expect(out['ok'], isTrue, reason: '$out');
    expect(
      out['message'],
      'Started Orbital Station level 1 on Kora for 5M credits and '
      '200 Station Segment and 40 Survey Drone and 30 Reactor Core and '
      '1.5K Hull Plate; done in 2h',
    );
    final projects = r.handle({'cmd': 'state'})['projects']! as List;
    expect((projects.single as Map)['name'], 'Orbital Station');
    final again = r.handle({
      'cmd': 'startMegaprojectStage',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
    });
    // While it runs, a start pays for the next level, which Kora lacks.
    expect(again['error'], 'cannotAfford');

    final away = r.handle({'cmd': 'away', 'seconds': 7300});
    expect(away['projectsCompleted'], [
      {
        'kind': 'megaprojectStage',
        'targetId': 'orbital_station',
        'name': 'Orbital Station',
        'level': 1,
        'message': 'Orbital Station reached level 1',
      },
    ]);
    expect(away['headline'], endsWith('; Orbital Station reached level 1'));
    expect(r.handle({'cmd': 'state'})['megaprojects'], [
      {'id': 'orbital_station', 'name': 'Orbital Station', 'level': 1},
    ]);
  });

  test('deliveries to a megaproject add up and start its stage', () {
    final r = _runner();
    final c = r.engine.content;
    final station = c.megaprojects['orbital_station']!;
    final cost = megaprojectCost(c, station, 0);
    final plates = cost['hull_plate']!;
    r.state.body('kora').stock['hull_plate'] = plates;
    final part = r.handle({
      'cmd': 'deliverToMegaproject',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
      'amounts': {'hull_plate': plates.toJson()},
    });
    expect(part['ok'], isTrue, reason: '$part');
    expect(part['createdId'], isNull);
    expect(
      part['message'],
      allOf(
        startsWith(
          'Delivered ${formatNumber(plates)} Hull Plate to Orbital Station '
          'level 1; it still needs ',
        ),
        contains('credits'),
        isNot(contains('Hull Plate and')),
      ),
    );
    final shown =
        (r.handle({'cmd': 'state'})['megaprojects']! as List).single as Map;
    expect((shown['delivered'] as Map).keys, ['hull_plate']);
    expect((shown['stillNeeded'] as Map).keys, [
      for (final k in cost.keys)
        if (k != 'hull_plate') k,
    ]);

    stockStation(r);
    final rest = r.handle({
      'cmd': 'deliverToMegaproject',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
      'amounts': {
        for (final MapEntry(:key, :value) in cost.entries) key: value.toJson(),
      },
    });
    expect(rest['ok'], isTrue, reason: '$rest');
    expect(rest['createdId'], startsWith('p'));
    expect(rest['message'], endsWith('; level 1 started, done in 2h'));
    final after =
        (r.handle({'cmd': 'state'})['megaprojects']! as List).single as Map;
    expect(after.containsKey('delivered'), isFalse);
  });

  test('costs mark a track that cannot get better as maxed', () {
    final r = _runner();
    final smelter = r.state
        .body('kora')
        .buildings
        .firstWhere((b) => b.defId == 'smelter');
    smelter.levels[UpgradeTrack.efficiency] = 40;
    Map<String, Object?> tracks() =>
        ((r.handle({'cmd': 'costs'})['upgrades']! as List)
                    .cast<Map<String, Object?>>()
                    .singleWhere(
                      (u) => u['buildingId'] == smelter.id,
                    )['tracks']!
                as Map)
            .cast<String, Object?>();
    expect(tracks()['efficiency'], {
      'level': 40,
      'maxed': true,
      'reason': 'its inputs are at the 25% floor',
    });
    final speed = tracks()['speed']! as Map;
    expect(speed.containsKey('maxed'), isFalse);
    expect(speed['cost'], isA<Map<String, Object?>>());
  });

  test('costs explain the shared speed and capacity counter', () {
    expect(
      _runner().handle({'cmd': 'costs'})['upgradeNote'],
      'Speed and capacity on a building share one counter: each speed or '
      'capacity upgrade makes the next one 17% pricier. Efficiency counts '
      'on its own.',
    );
  });

  test("costs include each megaproject's next level", () {
    final r = _runner();
    final next =
        ((r.handle({'cmd': 'costs'})['megaprojects']!
                as Map)['orbital_station']!
            as Map);
    expect(next['nextLevel'], 1);
    expect(next['timeTaken'], '2h');
    expect(((next['cost']! as Map)['hull_plate']! as Map)['display'], '1.5K');
    r.state.faction('player').megaprojectLevels['orbital_station'] = 1;
    final later =
        ((r.handle({'cmd': 'costs'})['megaprojects']!
                as Map)['orbital_station']!
            as Map);
    expect(later['nextLevel'], 2);
    expect(((later['cost']! as Map)['hull_plate']! as Map)['display'], '4.5K');
    expect(later.containsKey('stillNeeded'), isFalse);
  });

  test('costs show what a part-paid level still needs', () {
    final r = _runner();
    r.state.body('kora').stock['hull_plate'] = BigNum.from(500);
    r.handle({
      'cmd': 'deliverToMegaproject',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
      'amounts': {'hull_plate': '500'},
    });
    final next =
        ((r.handle({'cmd': 'costs'})['megaprojects']!
                as Map)['orbital_station']!
            as Map);
    expect(((next['cost']! as Map)['hull_plate']! as Map)['display'], '1.5K');
    expect(
      ((next['stillNeeded']! as Map)['hull_plate']! as Map)['display'],
      '1K',
    );
  });

  test('costs mark what cannot be started now as busy', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e9);
    r.handle({'cmd': 'expandSlots', 'bodyId': 'kora'});
    r.handle({'cmd': 'claimBody', 'bodyId': 'brine', 'sourceBodyId': 'kora'});
    r.state.body('kora').stock['survey_drone'] = BigNum.from(6);
    r.handle({'cmd': 'survey', 'sourceBodyId': 'kora'});
    r.handle({'cmd': 'survey', 'sourceBodyId': 'kora'});
    stockStation(r);
    r.handle({
      'cmd': 'startMegaprojectStage',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
    });
    var costs = r.handle({'cmd': 'costs'});
    expect(
      (costs['extraSlot']! as Map)['kora'],
      'busy: an extra slot arrives in 1h',
    );
    expect(costs['survey'], 'busy: every unsurveyed signal is being surveyed');
    final running = (costs['megaprojects']! as Map)['orbital_station']! as Map;
    expect(running['nextLevel'], 2);
    expect(running['note'], startsWith('level 1 is under way (done in 2h)'));
    stockStation(r, level: 1);
    r.handle({
      'cmd': 'startMegaprojectStage',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
    });
    costs = r.handle({'cmd': 'costs'});
    expect(
      (costs['megaprojects']! as Map)['orbital_station'],
      'busy: level 2 is paid for and starts when level 1 is done, in 2h',
    );
  });

  test('a delivery while a stage runs says when the next one starts', () {
    final r = _runner();
    stockStation(r);
    r.handle({
      'cmd': 'startMegaprojectStage',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
    });
    stockStation(r, level: 1);
    final out = r.handle({
      'cmd': 'startMegaprojectStage',
      'megaprojectId': 'orbital_station',
      'bodyId': 'kora',
    });
    expect(out['ok'], isTrue, reason: '$out');
    expect(out['createdId'], isNull);
    expect(
      out['message'],
      allOf(
        startsWith('Paid for Orbital Station level 2 from Kora with '),
        endsWith('; it starts when level 1 is done, in 2h'),
      ),
    );
  });

  test('away catches up offline and summarizes it', () {
    final r = _runner();
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'copper_ore',
      'keepAtLeast': '0',
    });
    final out = r.handle({'cmd': 'away', 'seconds': 100000});
    expect(out['ok'], isTrue, reason: '$out');
    expect(out['secondsAway'], 100000.0);
    expect(out['secondsSimulated'], 43200.0);
    expect(out['capSeconds'], 43200.0);
    expect(out['capped'], isTrue);
    expect(
      out['headline'],
      'Away 1d 4h; 12h counted (cap); '
      '+${(out['creditsGained']! as Map)['display']} credits',
    );
    expect(out['time'], 43200.0);
    expect(r.state.time, 43200.0);
    final credits = out['creditsGained']! as Map;
    expect(
      BigNum.fromJson(credits['value']! as String),
      greaterThan(BigNum.zero()),
    );
    expect(credits['display'], isA<String>());
    expect((out['stockGained']! as Map)['steel'], isA<Map<String, Object?>>());
    expect((out['totalWasted']! as Map)['value'], isA<String>());
    expect(out['milestonesReached'], [
      {'id': 'first_steel', 'name': 'First Foundry'},
      {'id': 'credits_10k', 'name': 'Ten Thousand Credits'},
    ]);
    expect(out['topBottlenecks'], isA<List<Object?>>());
  });

  test('away marks bottlenecks that were there before it as ongoing', () {
    final r = _runner();
    r.handle({'cmd': 'assignCrew', 'buildingId': 'b1', 'crew': 0});
    r.handle({'cmd': 'advance', 'seconds': 7200});
    final out = r.handle({'cmd': 'away', 'seconds': 3600});
    final necks = (out['topBottlenecks']! as List).cast<Map<String, Object?>>();
    final idle = necks.singleWhere((n) => n['buildingId'] == 'b1');
    expect(idle['firstSeenAt'], 0.0);
    expect(idle['ongoing'], 'ongoing since 0.0h');
    expect(necks.every((n) => n.containsKey('lostCreditsPerHour')), isTrue);
  });

  test('away needs a number of seconds', () {
    final r = _runner();
    expect(r.handle({'cmd': 'away'})['error'], 'badCommand');
    expect(r.handle({'cmd': 'away', 'seconds': 'x'})['error'], 'badCommand');
    expect(r.state.time, 0);
  });

  test('invalid command returns ok:false with error name', () {
    final out = _runner().handle({
      'cmd': 'build',
      'bodyId': 'nope',
      'defId': 'x',
    });
    expect(out['ok'], isFalse);
    expect(out['error'], 'unknownBody');
    expect(out['message'], isA<String>());
  });

  test("unknown cmd returns ok:false error 'unknownCommand'", () {
    final out = _runner().handle({'cmd': 'dance'});
    expect(out['ok'], isFalse);
    expect(out['error'], 'unknownCommand');
  });

  test('bad fields give badCommand', () {
    final out = _runner().handle({'cmd': 'demolish'});
    expect(out['error'], 'badCommand');
  });

  test('save then load round trip', () {
    final dir = Directory.systemTemp.createTempSync('game_sim_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/save.json';
    final r = _runner();
    r.handle({'cmd': 'advance', 'seconds': 120});
    expect(r.handle({'cmd': 'save', 'path': path})['ok'], isTrue);
    final saved = SaveCodec.encode(r.state);
    r.handle({'cmd': 'advance', 'seconds': 500});
    expect(SaveCodec.encode(r.state), isNot(saved));
    expect(r.handle({'cmd': 'load', 'path': path})['ok'], isTrue);
    expect(SaveCodec.encode(r.state), saved);
    expect(
      r.handle({'cmd': 'load', 'path': '${dir.path}/missing.json'})['error'],
      'ioError',
    );
  });

  test(
    "malformed JSON line returns ok:false error 'badJson' and continues",
    () {
      final r = _runner();
      final bad = r.handleLine('{not json');
      expect(bad['ok'], isFalse);
      expect(bad['error'], 'badJson');
      expect(r.handleLine('[1]')['error'], 'badJson');
      expect(r.handleLine(jsonEncode({'cmd': 'state'}))['ok'], isTrue);
    },
  );

  group('contracts', () {
    test('state lists the board and when the next contract comes', () {
      final r = _runner();
      expect(r.handle({'cmd': 'state'})['contracts'], isEmpty);
      r.handle({'cmd': 'advance', 'seconds': 60});
      final state = r.handle({'cmd': 'state'});
      final k = r.state.faction('player').contracts.single;
      final name = r.engine.content.resources[k.resourceId]!.name;
      expect(state['contracts'], [
        {
          'id': k.id,
          'issuer': 'Veyra Exchange',
          'resourceId': k.resourceId,
          'resource': name,
          'quantity': {
            'value': k.quantity.toJson(),
            'display': formatNumber(k.quantity),
          },
          'delivered': {'value': '0', 'display': '0'},
          'reward': {
            'value': k.rewardCredits.toJson(),
            'display': formatNumber(k.rewardCredits),
          },
        },
      ]);
      expect(state['contractRefills'], [
        {'at': 14400.0, 'timeLeft': '3h 59m'},
        {'at': 28800.0, 'timeLeft': '7h 59m'},
      ]);
    });

    test('deliver and discard reply with what they did', () {
      final r = _runner();
      r.handle({'cmd': 'advance', 'seconds': 14400 * 2 + 60});
      final f = r.state.faction('player');
      final k = f.contracts.first;
      final name = r.engine.content.resources[k.resourceId]!.name;
      final half = k.quantity.mulDouble(0.5);
      r.state.body('kora').stock[k.resourceId] = k.quantity;

      final part = r.handle({
        'cmd': 'deliverContract',
        'contractId': k.id,
        'bodyId': 'kora',
        'amount': half.toJson(),
      });
      expect(part['ok'], isTrue, reason: '$part');
      expect(
        part['message'],
        'Delivered ${formatNumber(half)} $name from Kora to contract '
        '${k.id} (${formatNumber(half)} of ${formatNumber(k.quantity)})',
      );

      final rest = r.handle({
        'cmd': 'deliverContract',
        'contractId': k.id,
        'bodyId': 'kora',
        'amount': k.quantity.toJson(),
      });
      expect(rest['ok'], isTrue, reason: '$rest');
      expect(
        rest['message'],
        'Delivered ${formatNumber(half)} $name from Kora and completed '
        'contract ${k.id}; paid ${formatNumber(k.rewardCredits)} credits. '
        'A new contract arrives in 4h',
      );
      expect(
        (rest['gained']! as Map)['credits'],
        isNotNull,
        reason: 'the reward shows as gained',
      );

      final other = f.contracts.first;
      final otherName = r.engine.content.resources[other.resourceId]!.name;
      final gone = r.handle({'cmd': 'discardContract', 'contractId': other.id});
      expect(gone['ok'], isTrue, reason: '$gone');
      expect(
        gone['message'],
        'Discarded contract ${other.id} for '
        '${formatNumber(other.quantity)} $otherName; '
        // The soonest refill: the one the completed contract banked.
        'a new contract arrives in 4h',
      );
      expect(
        r.handle({'cmd': 'discardContract', 'contractId': other.id})['error'],
        'unknownContract',
      );
    });
  });

  group('surveys', () {
    ScriptRunner rich() {
      final r = _runner();
      r.state.faction('player').credits = BigNum.from(1e9);
      r.state.body('kora').stock['survey_drone'] = BigNum.from(3);
      return r;
    }

    List<String> bodyIds(Map<String, Object?> state) => [
      for (final b in (state['bodies']! as List).cast<Map<String, Object?>>())
        b['id']! as String,
    ];

    test('a hidden body is absent from state, costs and reports', () {
      final r = rich();
      expect(bodyIds(r.handle({'cmd': 'state'})), isNot(contains('tessaly')));
      expect(bodyIds(r.handle({'cmd': 'state'})), hasLength(5));
      final text = jsonEncode([
        r.handle({'cmd': 'state'}),
        r.handle({'cmd': 'costs'}),
        r.handle({'cmd': 'report'}),
      ]);
      for (final secret in ['tessaly', 'Tessaly', 'dusk_cairn', 'Dusk Cairn']) {
        expect(text, isNot(contains(secret)));
      }
      final claim = r.handle({
        'cmd': 'claimBody',
        'bodyId': 'tessaly',
        'sourceBodyId': 'kora',
      });
      expect(claim['error'], 'unknownBody');
    });

    test('state counts unsurveyed signals; a survey needs no body id', () {
      final r = rich();
      expect(r.handle({'cmd': 'state'})['unsurveyedSignals'], [
        {'systemId': 'veyra', 'name': 'Veyra', 'count': 2},
      ]);
      final started = r.handle({'cmd': 'survey', 'sourceBodyId': 'kora'});
      expect(started['ok'], isTrue, reason: '$started');
      expect(started['message'], endsWith('done in 3h'));
      r.handle({'cmd': 'advance', 'seconds': 10860});
      final after = r.handle({'cmd': 'state'});
      expect(bodyIds(after), contains('tessaly'));
      expect(after['unsurveyedSignals'], [
        {'systemId': 'veyra', 'name': 'Veyra', 'count': 1},
      ]);
    });

    test('costs list the survey price and time', () {
      final costs = rich().handle({'cmd': 'costs'});
      final survey = costs['survey']! as Map<String, Object?>;
      expect(survey['timeTaken'], '3h');
      expect((survey['cost']! as Map).keys, ['credits', 'survey_drone']);
    });

    test('a survey is a project that reveals the body when it ends', () {
      final r = rich();
      final started = r.handle({
        'cmd': 'survey',
        'bodyId': 'tessaly',
        'sourceBodyId': 'kora',
      });
      expect(started['ok'], isTrue, reason: '$started');
      expect(started['message'], startsWith('Started a survey for '));
      expect(started['message'], endsWith('done in 3h'));
      final shown = r.handle({'cmd': 'state'});
      final project = (shown['projects']! as List).single as Map;
      expect(project['kind'], 'survey');
      expect(project['name'], 'an unsurveyed body');
      expect(bodyIds(shown), hasLength(5));

      r.handle({'cmd': 'advance', 'seconds': 10860});
      final after = r.handle({'cmd': 'state'});
      expect(bodyIds(after), contains('tessaly'));
      expect(bodyIds(after), isNot(contains('dusk_cairn')));
    });
  });
}
