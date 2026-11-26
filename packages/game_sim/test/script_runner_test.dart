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
    expect((kora['stock']! as Map).keys, ['iron_ore']);
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

  test('claim, demolish and route replies say what they took and gave', () {
    final r = _runner();
    r.state.faction('player').credits = BigNum.from(1e6);
    final claim = r.handle({
      'cmd': 'claimBody',
      'bodyId': 'brine',
      'sourceBodyId': 'kora',
    });
    expect(claim['ok'], isTrue);
    expect(claim['message'], 'Claimed Brine for 5K credits');
    expect((claim['spent']! as Map).keys, ['credits']);
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
}
