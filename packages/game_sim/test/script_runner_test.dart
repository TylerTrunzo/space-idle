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

/// The id, name and level of each megaproject in a `state` reply.
List<Map<String, Object?>> _levels(Map<String, Object?> state) => [
  for (final m in (state['megaprojects']! as List).cast<Map<String, Object?>>())
    {'id': m['id'], 'name': m['name'], 'level': m['level']},
];

/// Kora's entry in a `state` reply.
Map<String, Object?> _kora(Map<String, Object?> state) =>
    (state['bodies']! as List).cast<Map<String, Object?>>().singleWhere(
      (b) => b['id'] == 'kora',
    );

/// [v] as a reply writes a number: its value and its display.
Map<String, String> _numJson(double v) {
  final b = BigNum.from(v);
  return {'value': b.toJson(), 'display': formatNumber(b)};
}

void main() {
  test('a capacity upgrade says when free crew filled its new slot', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    final up = r.handle({
      'cmd': 'upgrade',
      'buildingId': 'b1',
      'track': 'capacity',
    });
    expect(up['ok'], isTrue, reason: '$up');
    expect(up['crewAdded'], 1);
    expect(
      up['message'],
      'Mine on Kora (b1) is at capacity level 1; 1 free crew moved into '
      'its new slot (2 of 2 crew)',
    );
    r.state.faction('player').baseCrew = 0;
    final empty = r.handle({
      'cmd': 'upgrade',
      'buildingId': 'b1',
      'track': 'capacity',
    });
    expect(empty['crewAdded'], isNull);
    expect(
      empty['message'],
      'Mine on Kora (b1) is at capacity level 2; its new slot is empty '
      '(no free crew; 2 of 3 crew)',
    );
    // Speed says nothing beyond what it spent.
    final speed = r.handle({
      'cmd': 'upgrade',
      'buildingId': 'b1',
      'track': 'speed',
    });
    expect(speed['message'], isNull);
  });

  test('buyUpgrades buys cheapest first and says what it bought', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1000);
    final none = r.handle({'cmd': 'buyUpgrades', 'budget': '49'});
    expect(none['ok'], isTrue, reason: '$none');
    expect(none['upgrades'], isEmpty);
    expect(none['stop'], 'budget');
    expect(none['nextCost'], _numJson(50));
    expect(
      none['message'],
      'Bought no upgrades: the cheapest costs 50 credits, more than the '
      'budget allows',
    );
    final buy = r.handle({'cmd': 'buyUpgrades', 'budget': '200'});
    expect(buy['ok'], isTrue, reason: '$buy');
    // The two mines' first speed levels at 50, then the first mine's
    // second at 58.5 (the smelter's first is 75); the second mine's
    // second, 58.5 more, would pass 200.
    expect(buy['spent'], {'credits': _numJson(158.5)});
    expect(buy['upgrades'], [
      {
        'buildingId': 'b1',
        'bodyId': 'kora',
        'track': 'speed',
        'levels': 2,
        'level': 2,
        'cost': _numJson(108.5),
      },
      {
        'buildingId': 'b2',
        'bodyId': 'kora',
        'track': 'speed',
        'levels': 1,
        'level': 1,
        'cost': _numJson(50),
      },
    ]);
    String f(double v) => formatNumber(BigNum.from(v));
    expect(
      buy['message'],
      'Bought 3 upgrade levels on 2 buildings for ${f(158.5)} credits; the '
      'next costs ${f(58.5)} credits, more than the budget allows',
    );
    r.state.faction('player').credits = BigNum.from(1e9);
    final capped = r.handle({
      'cmd': 'buyUpgrades',
      'budget': '1e9',
      'maxPurchases': 2,
    });
    expect(capped['stop'], 'maxPurchases');
    expect(
      capped['message'],
      'Bought 2 upgrade levels on 2 buildings for ${f(58.5 + 68.445)} '
      'credits; stopped at 2 levels, the most this command buys',
    );
  });

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
    final throughput = _numJson(
      routeThroughput(
        r.state,
        r.engine.content,
        route['createdId']! as String,
      ).perSec,
    );
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
        // The smelter uses all the ore Kora mines: what it holds is all it
        // has to send.
        'throughput': throughput,
        'limitedBy': 'sourceStock',
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

  test('state shows what an auto-sell rule holds back for open contracts', () {
    final r = _runner();
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'steel',
      'keepAtLeast': '0',
    });
    final f = r.state.faction('player');
    f.contracts
      ..clear()
      ..add(
        ContractState(
          id: r.state.newId('c'),
          templateId: r.engine.content.contractTemplates.keys.first,
          resourceId: 'steel',
          quantity: BigNum.from(300),
          delivered: BigNum.from(100),
          rewardCredits: BigNum.from(1000),
          postedAt: r.state.time,
        ),
      );
    f.contractRefillAt
      ..clear()
      ..addAll([1e9, 1e9]);
    final rule = (r.handle({'cmd': 'state'})['autoSell']! as List)
        .cast<Map<String, Object?>>()
        .single;
    expect((rule['contractHold']! as Map)['display'], '200');
    expect((rule['keeps']! as Map)['display'], '200');
    expect(
      rule['text'],
      'keeps 200 (keepAtLeast 0 + 0 local use + 200 for open contracts)',
    );
  });

  test('a new game posts what contracts it can at once and shows no refill '
      'due in 0s', () {
    final r = _runner();
    final st = r.handle({'cmd': 'state'});
    // Nothing made yet: the first refill waits for something to ask for.
    expect(st['contracts'], isEmpty);
    final refills = (st['contractRefills']! as List)
        .cast<Map<String, Object?>>();
    expect(refills.map((x) => x['timeLeft']), isNot(contains('0s')));
    expect(refills, hasLength(2));
    expect(st['contractsDue'], {
      'count': 1,
      'note': 'Posted as soon as you make something a contract can ask for',
    });
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
    expect(((routes.single as Map)['stopTarget']! as Map)['display'], '20');
    // The stop level's 20 a trip of 2 minutes, below Hollow Reach's cap.
    expect((routes.single as Map)['limitedBy'], 'stopLevel');
    expect(
      double.parse(
        ((routes.single as Map)['throughput']! as Map)['value']! as String,
      ),
      closeTo(20 / 120, 0.01),
    );
    expect((routes.single as Map)['stopSharedWith'], isEmpty);
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
      'Built Shipyard on Kora (${yard['createdId']}) with 2 of 2 crew. At '
      'full crew it uses 0.0333 Steel and 0.0133 Circuit a second and makes '
      '0.00333 Cargo Ship a second',
    );
    expect(yard['inputsPerSec'], {
      'steel': {'value': '3.3333333333333335e-2', 'display': '0.0333'},
      'circuit': {'value': '1.3333333333333335e-2', 'display': '0.0133'},
    });
    final empty = r.handle({
      'cmd': 'build',
      'bodyId': 'kora',
      'defId': 'shipyard',
      'autoCrew': false,
    });
    expect(
      empty['message'],
      startsWith(
        'Built Shipyard on Kora (${empty['createdId']}) with 0 of 2 crew. ',
      ),
    );
    r.state.body('kora').stock['steel'] = BigNum.from(50);
    final depot = r.handle({
      'cmd': 'build',
      'bodyId': 'kora',
      'defId': 'depot',
    });
    expect(depot['message'], 'Built Depot on Kora (${depot['createdId']})');
  });

  test('catalog lists every building type and where it can go now', () {
    final r = _runner();
    final out = r.handle({'cmd': 'catalog'});
    expect(out['ok'], isTrue);
    final defs = (out['buildings']! as List).cast<Map<String, Object?>>();
    final c = r.engine.content;
    expect(defs.map((d) => d['id']), c.buildings.keys);
    final yard = defs.singleWhere((d) => d['id'] == 'shipyard');
    expect(yard['name'], 'Shipyard');
    expect(yard['kind'], 'factory');
    expect(yard['cost'], {
      'credits': {'value': '1e3', 'display': '1K'},
    });
    expect(yard['crewSlots'], 2);
    expect(
      ((yard['inputsPerSec']! as Map)['steel']! as Map)['display'],
      '0.0333',
    );
    expect(
      ((yard['outputsPerSec']! as Map)['cargo_ship']! as Map)['display'],
      '0.00333',
    );
    expect(yard['canBuildOn'], [
      {'bodyId': 'kora', 'name': 'Kora'},
    ]);
    // An extractor lists the deposits it can mine on each body, with the
    // rate there.
    final mine = defs.singleWhere((d) => d['id'] == 'mine');
    final kora = (mine['canBuildOn']! as List).single as Map;
    expect(kora['bodyId'], 'kora');
    final deposits = (kora['deposits']! as List).cast<Map<String, Object?>>();
    expect(deposits.map((d) => d['resourceId']), contains('iron_ore'));
    final iron = deposits.singleWhere((d) => d['resourceId'] == 'iron_ore');
    expect((iron['outputPerSec']! as Map)['display'], '0.4');
    // No ice on Kora, so no ice drill there.
    final drill = defs.singleWhere((d) => d['id'] == 'ice_drill');
    expect(drill['canBuildOn'], isEmpty);
    // A full body hosts nothing.
    final k = r.state.body('kora');
    while (k.buildings.length < buildSlots(c, k)) {
      k.buildings.add(
        BuildingState(id: r.state.newId('b'), defId: 'depot', crew: 0),
      );
    }
    final full = r.handle({'cmd': 'catalog'})['buildings']! as List;
    expect(
      full.every((d) => ((d as Map)['canBuildOn']! as List).isEmpty),
      isTrue,
    );
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

  test('setMegaprojectAuto says how the megaproject is fed', () {
    final r = _runner();
    final reserve = r.handle({'cmd': 'setAutoPayReserve', 'credits': '5e6'});
    expect(reserve['ok'], isTrue, reason: '$reserve');
    expect(
      reserve['message'],
      'Auto-pay now keeps 5M credits; the credits above it are shared out '
      'each game minute among the megaprojects taking credits on their own',
    );
    expect(
      r.handle({'cmd': 'setAutoPayReserve', 'credits': '-1'})['error'],
      'invalidAmount',
    );
    final on = r.handle({
      'cmd': 'setMegaprojectAuto',
      'megaprojectId': 'orbital_station',
      'goods': true,
      'credits': true,
    });
    expect(on['ok'], isTrue, reason: '$on');
    expect(
      on['message'],
      'Orbital Station now takes goods from every body each game minute, '
      'above what each keeps for its own use and open contracts, and a '
      'share of the credits above the auto-pay reserve (5M)',
    );
    expect(
      r.handle({
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'mass_driver',
        'goods': true,
      })['message'],
      endsWith('and no credits'),
    );
    expect(
      r.handle({
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'orbital_station',
        'goods': false,
        'credits': true,
      })['message'],
      'Orbital Station now takes a share of the credits above the auto-pay '
      'reserve (5M) each game minute, and no goods',
    );
    expect(
      r.handle({
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'orbital_station',
        'goods': false,
      })['message'],
      'Orbital Station is fed by hand only',
    );
    expect(
      r.handle({
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'orbital_station',
        'goods': 'nearReady',
        'credits': true,
        'creditWeight': 3,
      })['message'],
      'Orbital Station now takes goods from every body each game minute '
      'once a stage is near ready (its credits due within 12h), above what '
      'each keeps for its own use and open contracts, and a share, at '
      'weight 3, of the credits above the auto-pay reserve (5M)',
    );
    expect(
      r.handle({
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'orbital_station',
        'goods': 'off',
        'credits': true,
        'creditWeight': 0,
      })['message'],
      'Orbital Station now takes the credits above the auto-pay reserve '
      '(5M) only when nothing else takes them (weight 0) each game minute, '
      'and no goods',
    );
    expect(
      r.handle({
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'orbital_station',
        'credits': true,
        'creditWeight': 11,
      })['error'],
      'invalidAmount',
    );
    final bad = r.handle({
      'cmd': 'setMegaprojectAuto',
      'megaprojectId': 'orbital_station',
      'goods': 'sometimes',
    });
    expect(bad['error'], 'badCommand');
  });

  test('state words each megaproject\'s bonuses, lock and auto-delivery', () {
    final r = _runner();
    final f = r.state.faction('player');
    f.megaprojectLevels['orbital_station'] = 3;
    Map<String, Object?> entry(String id) =>
        (r.handle({'cmd': 'state'})['megaprojects']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((m) => m['id'] == id);
    final station = entry('orbital_station');
    expect(
      station['bonuses'],
      'level 3: storage +30%, housing +15%, offline cap +3h, market depth '
      '×1.95',
    );
    expect(
      station['nextLevel'],
      'level 4: storage +40%, housing +20%, offline cap +4h, market depth '
      '×2.44',
    );
    expect(station.containsKey('locked'), isFalse);
    expect(station.containsKey('auto'), isFalse);
    f.megaprojectLevels['orbital_station'] = 0;
    final driver = entry('mass_driver');
    expect(driver['bonuses'], 'level 0: no bonus yet');
    expect(driver['nextLevel'], 'level 1: sale price ×1.05 (tiers 1-2)');
    expect(driver['locked'], 'opens at Orbital Station level 1 (now 0)');
    r.handle({'cmd': 'setAutoPayReserve', 'credits': '1e6'});
    r.handle({
      'cmd': 'setMegaprojectAuto',
      'megaprojectId': 'mass_driver',
      'goods': true,
      'credits': true,
    });
    expect(entry('mass_driver')['auto'], {
      'goods': 'always',
      'credits': true,
      'creditWeight': 1,
      'text':
          'goods from every body, and a share of the credits above the '
          'auto-pay reserve (1M)',
    });
    r.handle({
      'cmd': 'setMegaprojectAuto',
      'megaprojectId': 'mass_driver',
      'goods': 'nearReady',
      'credits': true,
      'creditWeight': 2,
    });
    expect(entry('mass_driver')['auto'], {
      'goods': 'nearReady',
      'credits': true,
      'creditWeight': 2,
      'goodsFedNow': false,
      'text':
          'goods from every body once a stage is near ready (its credits '
          'due within 12h), not fed yet, and a share, at weight 2, of the '
          'credits above the auto-pay reserve (1M)',
    });
    expect(r.handle({'cmd': 'state'})['autoPayReserve'], {
      'value': '1e6',
      'display': '1M',
    });
    expect(
      (r.handle({'cmd': 'costs'})['megaprojects']! as Map)['mass_driver'],
      'locked: opens at Orbital Station level 1 (now 0)',
    );
  });

  test('auto-delivery shows in auto-sell keeps, the report and away', () {
    final r = _runner();
    final f = r.state.faction('player');
    f.megaprojectLevels['orbital_station'] = 2;
    f.credits = BigNum.from(5000);
    // A wire mill on Kora, which mines copper ore: the Mass Driver takes
    // copper wire.
    r.state
        .body('kora')
        .buildings
        .add(BuildingState(id: 'wm', defId: 'wire_mill', crew: 1));
    for (final cmd in [
      {'cmd': 'setAutoPayReserve', 'credits': '1000'},
      {
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'mass_driver',
        'goods': true,
        'credits': true,
      },
      {
        'cmd': 'setAutoSell',
        'bodyId': 'kora',
        'resourceId': 'copper_wire',
        'keepAtLeast': '0',
      },
      {
        'cmd': 'setAutoSell',
        'bodyId': 'kora',
        'resourceId': 'steel',
        'keepAtLeast': '0',
      },
    ]) {
      expect(r.handle(cmd)['ok'], isTrue);
    }
    final rule = (r.handle({'cmd': 'state'})['autoSell']! as List)
        .cast<Map<String, Object?>>()
        .first;
    expect(rule['megaprojectHold'], isA<Map<String, Object?>>());
    expect(
      rule['text'],
      'keeps 1.2K (keepAtLeast 0 + 0 local use + 20K for megaprojects, cut to '
      'the storage cap)',
    );
    final rep = r.handle({'cmd': 'report'});
    final per = (rep['autoDeliveredPerSec']! as Map)['mass_driver']! as Map;
    expect(per.keys, containsAll(['copper_wire', 'credits']));
    expect(rep['autoDeliveredValuePerSec'], isA<Map<String, Object?>>());
    final away = r.handle({'cmd': 'away', 'seconds': 3600});
    final fed = (away['autoDelivered']! as List).single as Map;
    expect(fed['id'], 'mass_driver');
    expect(
      fed['message'],
      allOf(
        startsWith('Mass Driver got '),
        contains('Copper Wire'),
        contains('credits'),
      ),
    );
  });

  test('a megaproject stage starts, shows in state and raises the level', () {
    final r = _runner();
    expect(_levels(r.handle({'cmd': 'state'})), [
      {'id': 'orbital_station', 'name': 'Orbital Station', 'level': 0},
      {'id': 'mass_driver', 'name': 'Mass Driver', 'level': 0},
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
    expect(_levels(r.handle({'cmd': 'state'})), [
      {'id': 'orbital_station', 'name': 'Orbital Station', 'level': 1},
      {'id': 'mass_driver', 'name': 'Mass Driver', 'level': 0},
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
        (r.handle({'cmd': 'state'})['megaprojects']! as List).first as Map;
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
        (r.handle({'cmd': 'state'})['megaprojects']! as List).first as Map;
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
    expect(((later['cost']! as Map)['hull_plate']! as Map)['display'], '3.75K');
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

  test('costs say the last stage is under way, not that it is at its '
      'highest level', () {
    final r = _runner();
    const max = SaveCodec.maxMegaprojectLevel;
    r.state.faction('player').megaprojectLevels['orbital_station'] = max - 1;
    startProject(
      r.state,
      'player',
      ProjectKind.megaprojectStage,
      'orbital_station',
      3600,
    );
    final costs = r.handle({'cmd': 'costs'});
    expect(
      (costs['megaprojects']! as Map)['orbital_station'],
      'busy: level $max, its highest, is under way, done in 1h',
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

  test('contract progress never reads as done while a unit is owed', () {
    // Round-4 casual bug 4: "(30K of 30K)" while 1 unit was owed.
    final r = _runner();
    final f = r.state.faction('player');
    f.contracts
      ..clear()
      ..add(
        ContractState(
          id: 'c99',
          templateId: r.engine.content.contractTemplates.keys.first,
          resourceId: 'iron_ore',
          quantity: BigNum.from(30000),
          rewardCredits: BigNum.from(5),
          postedAt: 0,
        ),
      );
    r.state.body('kora').stock['iron_ore'] = BigNum.from(29999);
    final out = r.handle({
      'cmd': 'deliverContract',
      'contractId': 'c99',
      'bodyId': 'kora',
      'amount': '29999',
    });
    expect(out['ok'], isTrue, reason: '$out');
    expect(out['message'], endsWith('(29.9K of 30K, 1 still owed)'));
  });

  test('a group of buildings reads as one line, with its count', () {
    // Round-4 casual bug 2: one row per dock filled the summary.
    final r = _runner();
    r.state.faction('player').baseCrew = 40;
    for (var i = 0; i < 17; i++) {
      r.state
          .body('kora')
          .buildings
          .add(
            BuildingState(
              id: r.state.newId('b'),
              defId: 'plate_press',
              crew: 1,
            ),
          );
    }
    for (final id in ['hull_plate', 'copper_ore']) {
      r.handle({
        'cmd': 'setAutoSell',
        'bodyId': 'kora',
        'resourceId': id,
        'keepAtLeast': '0',
      });
    }
    final out = r.handle({'cmd': 'away', 'seconds': 3600});
    final necks = (out['topBottlenecks']! as List).cast<Map<String, Object?>>();
    final presses = necks.singleWhere((n) => n['resourceId'] == 'steel');
    expect(presses['count'], 17);
    expect(presses['buildingIds'], hasLength(17));
    expect(presses['buildingId'], isNull);
    expect(
      presses['message'],
      matches(
        r'^17 Plate Presses on Kora are running as low as \d+%: '
        r'not enough Steel$',
      ),
    );
    final report = r.handle({'cmd': 'report'});
    final grouped = (report['bottlenecks']! as List)
        .cast<Map<String, Object?>>()
        .where((n) => n['resourceId'] == 'steel');
    expect(grouped.single['count'], 17);
  });

  test('a group of several building types reads as buildings', () {
    final r = _runner();
    r.state.faction('player').baseCrew = 40;
    final kora = r.state.body('kora');
    for (final def in ['plate_press', 'plate_press', 'shipyard']) {
      kora.buildings.add(
        BuildingState(id: r.state.newId('b'), defId: def, crew: 1),
      );
    }
    kora.stock['circuit'] = BigNum.from(1000);
    final out = r.handle({'cmd': 'report'});
    final steel = (out['bottlenecks']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((n) => n['resourceId'] == 'steel');
    expect(steel['count'], 3);
    expect(
      steel['message'],
      matches(
        r'^3 buildings on Kora are running as low as \d+%: '
        r'not enough Steel$',
      ),
    );
  });

  group('a shortage a route cannot carry enough for', () {
    // Round-4 casual hidden rule: Cinder stores 1K and is 2 minutes from
    // Kora, so a stop-level route carries at most 1K a trip, 8.33 a
    // second, for two fast smelters there that use 8.67 each.
    ScriptRunner fed({int smelters = 2}) {
      final r = _runner();
      r.state.faction('player').baseCrew = 40;
      final kora = r.state.body('kora');
      kora.stock['iron_ore'] = BigNum.from(1e7);
      kora.stock['cargo_ship'] = BigNum.from(20);
      final cinder = r.state.body('cinder')..ownerId = 'player';
      for (var i = 0; i < smelters; i++) {
        cinder.buildings.add(
          BuildingState(id: r.state.newId('b'), defId: 'smelter', crew: 1)
            ..levels[UpgradeTrack.speed] = 25,
        );
      }
      r.handle({
        'cmd': 'setAutoSell',
        'bodyId': 'cinder',
        'resourceId': 'steel',
        'keepAtLeast': '0',
      });
      final route = r.handle({
        'cmd': 'createRoute',
        'fromBodyId': 'kora',
        'toBodyId': 'cinder',
        'resourceId': 'iron_ore',
        'ratePerSecond': '100',
        'cargoShips': 20,
        'stopAtDestination': '1000',
      });
      expect(route['ok'], isTrue, reason: '$route');
      r.handle({'cmd': 'advance', 'seconds': 1200});
      return r;
    }

    test('names the route, its limit and what raises it', () {
      final r = fed();
      final neck = (r.handle({'cmd': 'report'})['bottlenecks']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((n) => n['resourceId'] == 'iron_ore');
      expect(neck['kind'], 'routeLimited');
      expect(neck['count'], 2);
      expect(neck['binding'], 'destinationRoom');
      expect(neck['routeId'], r.state.routes.single.id);
      expect((neck['routePerSec']! as Map)['display'], '8.33');
      expect(
        neck['message'],
        matches(
          r'^2 Smelters on Cinder are running as low as \d+%: Iron Ore into '
          r"Cinder is limited by Cinder's storage \(8\.33/s\); a Depot "
          r'raises it$',
        ),
      );
    });

    test('says so for one building, and in the away summary', () {
      final r = fed(smelters: 1);
      final out = r.handle({'cmd': 'away', 'seconds': 3600});
      final neck = (out['topBottlenecks']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((n) => n['resourceId'] == 'iron_ore');
      expect(
        neck['message'],
        matches(
          r'^Smelter on Cinder is running at \d+%: Iron Ore into Cinder is '
          r"limited by Cinder's storage \(8\.33/s\); a Depot raises it$",
        ),
      );
    });

    test('says what each other limit is and what raises it', () {
      final r = fed(smelters: 1);
      final c = r.engine.content;
      final route = r.state.routes.single;
      String text(RouteLimit binding, double perSec) => r.bottleneckText(
        Bottleneck(
          kind: BottleneckKind.routeLimited,
          bodyId: 'cinder',
          buildingId: r.state.body('cinder').buildings.single.id,
          resourceId: 'iron_ore',
          runFraction: 0.5,
          buildingIds: [r.state.body('cinder').buildings.single.id],
          routeId: route.id,
          binding: binding,
          routePerSec: perSec,
        ),
      );
      expect(c.buildings['smelter']!.name, 'Smelter');
      final who = 'Smelter on Cinder is running at 50%: Iron Ore into Cinder';
      expect(
        text(RouteLimit.rate, 100),
        "$who is limited by route ${route.id}'s rate (100/s); raise its rate",
      );
      expect(
        text(RouteLimit.ships, 200),
        "$who is limited by route ${route.id}'s 20 Cargo Ships (200/s); "
        'assign more ships',
      );
      expect(
        text(RouteLimit.stopLevel, 5),
        "$who is limited by route ${route.id}'s stop level (5/s); raise its "
        'stop level',
      );
      expect(
        text(RouteLimit.sourceStock, 2),
        '$who is limited by what Kora has to send (2/s)',
      );
    });
  });

  test('away says what the storage cap cut while away', () {
    final r = _runner();
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'copper_ore',
      'keepAtLeast': '0',
    });
    r.state.shipments.add(
      Shipment(
        routeId: 'move',
        fromBodyId: 'brine',
        toBodyId: 'kora',
        ownerId: 'player',
        resourceId: 'hull_plate',
        amount: BigNum.from(1e5),
        departAt: 0,
        arriveAt: 600,
      ),
    );
    final out = r.handle({'cmd': 'away', 'seconds': 3600});
    final cut = (out['topBottlenecks']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((n) => n['kind'] == 'storageFull');
    expect(
      cut['message'],
      'Kora storage filled up with Hull Plate while you were away: output '
      'was wasted',
    );
  });

  test('building names take their plurals', () {
    expect(
      [
        for (final name in [
          'Reactor Works',
          'Magnet Works',
          'Fuel Refinery',
          'Station Dock',
          'Plate Press',
          'Ice Drill',
          'Gas Skimmer',
        ])
          ScriptRunner.plural(name),
      ],
      [
        'Reactor Works',
        'Magnet Works',
        'Fuel Refineries',
        'Station Docks',
        'Plate Presses',
        'Ice Drills',
        'Gas Skimmers',
      ],
    );
  });

  test('away names what a keepAtLeast holds back from a megaproject', () {
    // Round-4 casual bug 3: 469 reactor cores owed, 1K held under keep
    // 1,000, and nothing said why auto-delivery left them.
    final r = _runner();
    final c = r.engine.content;
    final station = c.megaprojects['orbital_station']!;
    final f = r.state.faction('player')
      ..megaprojectProgress['orbital_station'] = {
        'reactor_core':
            megaprojectCost(c, station, 0)['reactor_core']! - BigNum.from(469),
      };
    r.state.body('kora').stock['reactor_core'] = BigNum.from(1000);
    for (final cmd in [
      {
        'cmd': 'setAutoSell',
        'bodyId': 'kora',
        'resourceId': 'reactor_core',
        'keepAtLeast': '1000',
      },
      {
        'cmd': 'setAutoSell',
        'bodyId': 'kora',
        'resourceId': 'copper_ore',
        'keepAtLeast': '0',
      },
      {
        'cmd': 'setMegaprojectAuto',
        'megaprojectId': 'orbital_station',
        'goods': true,
        'credits': false,
      },
    ]) {
      expect(r.handle(cmd)['ok'], isTrue, reason: '$cmd');
    }
    expect(f.megaprojectAuto, contains('orbital_station'));
    final out = r.handle({'cmd': 'report'});
    final held = (out['bottlenecks']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((n) => n['kind'] == 'keepBlocksDelivery');
    expect(
      held['message'],
      'Orbital Station still needs Reactor Core, but Kora keeps 469 of it '
      'back for its auto-sell keepAtLeast 1K',
    );
    expect((held['heldByKeep']! as Map)['display'], '469');
  });

  test('away marks bottlenecks that were there before it as ongoing', () {
    final r = _runner();
    r.handle({'cmd': 'assignCrew', 'buildingId': 'b1', 'crew': 0});
    // A rule that sells nothing keeps noSales out of the top three.
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'steel',
      'keepAtLeast': '1e9',
    });
    r.handle({'cmd': 'advance', 'seconds': 7200});
    final out = r.handle({'cmd': 'away', 'seconds': 3600 + 600});
    final necks = (out['topBottlenecks']! as List).cast<Map<String, Object?>>();
    final idle = necks.singleWhere((n) => n['buildingId'] == 'b1');
    expect(idle['firstSeenAt'], 0.0);
    // How long it has gone on, not a game-time stamp that reads like one.
    expect(idle['ongoing'], 'for 3h 10m');
    expect(necks.every((n) => n.containsKey('lostCreditsPerHour')), isTrue);
  });

  test('away shows housing, income, waste in credits and worse ongoing '
      'bottlenecks', () {
    final r = _runner();
    final kora = r.state.body('kora');
    // Round-3 casual bug 2: housing below the crew assigned.
    r.state.faction('player').baseCrew = 2;
    r.handle({'cmd': 'assignCrew', 'buildingId': 'b1', 'crew': 0});
    r.handle({
      'cmd': 'setAutoSell',
      'bodyId': 'kora',
      'resourceId': 'steel',
      'keepAtLeast': '0',
    });
    kora.stock['iron_ore'] = BigNum.zero();
    kora.stock['copper_ore'] = storageCap(r.state, r.engine.content, kora);
    r.handle({'cmd': 'advance', 'seconds': 60});
    kora.stock['iron_ore'] = BigNum.from(0.2);
    final out = r.handle({'cmd': 'away', 'seconds': 3600});
    expect(out['housingBefore'], {'base': 2, 'supported': 2, 'assigned': 2});
    expect(out['housingAfter'], {'base': 2, 'supported': 2, 'assigned': 2});
    expect((out['creditsPerSecBefore']! as Map)['display'], isA<String>());
    expect((out['creditsPerSecAfter']! as Map)['display'], isA<String>());
    final waste = out['wastedValue']! as Map;
    expect(BigNum.fromJson(waste['value']! as String) > BigNum.zero(), isTrue);
    final necks = (out['topBottlenecks']! as List).cast<Map<String, Object?>>();
    final smelter = necks.singleWhere((n) => n['buildingId'] == 'b3');
    expect(smelter['since'], 0.0);
    expect(smelter['worseThanBefore'], isTrue);
    expect(smelter['ongoing'], 'for 1h 1m, and worse than before');
  });

  test('away names a crew shortage in its headline', () {
    final r = _runner();
    r.state.faction('player').baseCrew = 2;
    final out = r.handle({'cmd': 'away', 'seconds': 3600});
    expect(out['headline'], endsWith('; Crew short: 2 housed for 3 assigned'));
    final first = (out['topBottlenecks']! as List).first as Map;
    expect(first['kind'], 'crewShortage');
  });

  test('away gives one next goal', () {
    final r = _runner();
    final out = r.handle({'cmd': 'away', 'seconds': 60});
    expect(out['nextGoal'], {
      'kind': 'milestone',
      'id': 'first_steel',
      'name': 'First Foundry',
      'etaSeconds': closeTo(90, 1e-6),
      'message': 'Next: First Foundry (Make 30 Steel), 12 of 30, in 1m 30s',
    });
    final f = r.state.faction('player');
    f.reachedMilestones.addAll([
      for (final m in r.engine.content.milestones) m.id,
    ]);
    final station = r.handle({'cmd': 'away', 'seconds': 60});
    expect(station['nextGoal'], {
      'kind': 'megaproject',
      'id': 'orbital_station',
      'name': 'Orbital Station',
      'level': 1,
      'etaSeconds': null,
      'message': startsWith(
        'Next: Orbital Station level 1 still needs 5M credits and 200 '
        'Station Segment and ',
      ),
    });
    expect(
      (station['nextGoal']! as Map)['message'],
      endsWith('; not in reach at the current rates'),
    );
    // Once the player turns its auto-delivery on without credits, and
    // pays none by hand, it is not the next goal.
    r.handle({
      'cmd': 'setMegaprojectAuto',
      'megaprojectId': 'orbital_station',
      'goods': true,
      'credits': false,
    });
    expect(r.handle({'cmd': 'away', 'seconds': 60})['nextGoal'], isNull);
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

    test('a delivery with no body takes from every body in one command', () {
      final r = _runner();
      r.handle({'cmd': 'advance', 'seconds': 14400 * 2 + 60});
      final k = r.state.faction('player').contracts.first;
      final id = k.resourceId;
      final name = r.engine.content.resources[id]!.name;
      // Kora holds the most, so it gives first; Brine the rest.
      final fromKora = k.quantity.mulDouble(0.7).floor();
      final fromBrine = k.quantity - fromKora;
      r.state.body('kora').stock[id] = fromKora;
      r.state.body('brine')
        ..ownerId = 'player'
        ..stock[id] = k.quantity.mulDouble(0.5).floor();
      final out = r.handle({
        'cmd': 'deliverContract',
        'contractId': k.id,
        'amount': k.quantity.toJson(),
      });
      expect(out['ok'], isTrue, reason: '$out');
      expect(
        out['message'],
        'Delivered ${formatNumber(k.quantity)} $name '
        '(${formatNumber(fromKora)} from Kora, ${formatNumber(fromBrine)} '
        'from Brine) and completed contract ${k.id}; paid '
        '${formatNumber(k.rewardCredits)} credits. A new contract arrives in '
        '4h',
      );
      expect((out['spent']! as Map).keys, ['kora/$id', 'brine/$id']);
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
        '${k.id} (${formatNumber(half)} of ${formatNumber(k.quantity)}, '
        '${formatNumber(k.quantity - half)} still owed)',
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
      final during = r.handle({'cmd': 'state'});
      // The signal under survey no longer counts, and the project does not
      // name the hidden body it targets.
      expect(during['unsurveyedSignals'], [
        {'systemId': 'veyra', 'name': 'Veyra', 'count': 1},
      ]);
      final project = (during['projects']! as List).single as Map;
      expect(project['name'], 'an unsurveyed body');
      expect(project.containsKey('targetId'), isFalse);
      expect(jsonEncode(during), isNot(contains('tessaly')));
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
