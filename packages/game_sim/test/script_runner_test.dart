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
    expect(bodies, isNotEmpty);
  });

  test('stock grows after building an extractor and advancing', () {
    final r = _runner();
    final body =
        (r.handle({'cmd': 'state'})['bodies']! as List).first
            as Map<String, Object?>;
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
    final stock =
        (r.handle({'cmd': 'state'})['bodies']! as List).first
            as Map<String, Object?>;
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
    });
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
