import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final content = shippedContent();
  Map<String, Object?> fresh() => newGameState(content, 3).toJson();

  SaveError err(SaveResult r) => r as SaveError;

  test('encode then decode round trips', () {
    final s = newGameState(content, 3);
    final text = SaveCodec.encode(s);
    final r = SaveCodec.decode(text, content);
    expect(r, isA<SaveOk>());
    expect(SaveCodec.encode((r as SaveOk).state), text);
  });

  test('decode rejects garbage', () {
    expect(
      err(SaveCodec.decode('not json', content)).kind,
      SaveErrorKind.notJson,
    );
    expect(err(SaveCodec.decode('[1]', content)).kind, SaveErrorKind.notJson);
  });

  test('decode rejects unknown version', () {
    expect(
      err(SaveCodec.decode('{"saveVersion": 99}', content)).kind,
      SaveErrorKind.unknownVersion,
    );
  });

  test('decode rejects unknown content ids', () {
    final m = fresh();
    ((m['bodies']! as List).first as Map)['typeId'] = 'nope';
    expect(
      err(SaveCodec.decode(jsonEncode(m), content)).kind,
      SaveErrorKind.unknownContentId,
    );
    final m2 = fresh();
    final kora = (m2['bodies']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((b) => b['id'] == 'kora');
    ((kora['buildings']! as List).first as Map)['defId'] = 'nope';
    expect(
      err(SaveCodec.decode(jsonEncode(m2), content)).kind,
      SaveErrorKind.unknownContentId,
    );
    final m3 = fresh();
    ((m3['bodies']! as List).cast<Map<String, Object?>>().firstWhere(
              (b) => b['id'] == 'kora',
            )['stock']
            as Map)['nope'] =
        '1';
    expect(
      err(SaveCodec.decode(jsonEncode(m3), content)).kind,
      SaveErrorKind.unknownContentId,
    );
  });

  test('decode rejects bad route resource', () {
    final s = newGameState(content, 3)
      ..routes.add(
        RouteState(
          id: 'r1',
          ownerId: 'player',
          fromBodyId: 'kora',
          toBodyId: 'brine',
          resourceId: 'nope',
          ratePerSecond: BigNum.parse('1'),
          cargoShips: 1,
        ),
      );
    expect(
      err(SaveCodec.decode(SaveCodec.encode(s), content)).kind,
      SaveErrorKind.unknownContentId,
    );
  });

  test('decode rejects missing fields', () {
    final m = fresh()..remove('bodies');
    expect(
      err(SaveCodec.decode(jsonEncode(m), content)).kind,
      SaveErrorKind.missingField,
    );
    final m2 = fresh()..remove('time');
    expect(
      err(SaveCodec.decode(jsonEncode(m2), content)).kind,
      SaveErrorKind.missingField,
    );
    expect(
      err(SaveCodec.decode('{}', content)).kind,
      SaveErrorKind.missingField,
    );
  });

  test('migration runs', () {
    final m = fresh()
      ..remove('time')
      ..['saveVersion'] = 0
      ..['clock'] = 42.5;
    final r = SaveCodec.decode(
      jsonEncode(m),
      content,
      migrations: {
        0: (m) => {...m, 'saveVersion': 1, 'time': m['clock']},
      },
    );
    expect(r, isA<SaveOk>());
    expect((r as SaveOk).state.time, 42.5);
    expect(r.state.saveVersion, 1);
  });

  test('missing migration for old version is unknownVersion', () {
    final m = fresh()..['saveVersion'] = 0;
    expect(
      err(SaveCodec.decode(jsonEncode(m), content)).kind,
      SaveErrorKind.unknownVersion,
    );
  });
}
