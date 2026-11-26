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

  group('decode rejects unknown ids in', () {
    void expectUnknown(void Function(GameState s) corrupt) {
      final s = newGameState(content, 3);
      corrupt(s);
      expect(
        err(SaveCodec.decode(SaveCodec.encode(s), content)).kind,
        SaveErrorKind.unknownContentId,
      );
    }

    RouteState route({String from = 'kora', String to = 'brine'}) => RouteState(
      id: 'r1',
      ownerId: 'player',
      fromBodyId: from,
      toBodyId: to,
      resourceId: 'iron_ore',
      ratePerSecond: BigNum.parse('1'),
      cargoShips: 1,
    );

    Shipment shipment({String to = 'brine', String resource = 'iron_ore'}) =>
        Shipment(
          routeId: 'r1',
          toBodyId: to,
          resourceId: resource,
          amount: BigNum.parse('1'),
          arriveAt: 5,
        );

    AutoSellRule rule({String body = 'kora', String resource = 'iron_ore'}) =>
        AutoSellRule(
          bodyId: body,
          resourceId: resource,
          keepAtLeast: BigNum.parse('1'),
        );

    test('building deposit', () {
      expectUnknown(
        (s) => s
            .body('kora')
            .buildings
            .add(
              BuildingState(
                id: 'b99',
                defId: 'mine',
                depositResourceId: 'nope',
                crew: 0,
              ),
            ),
      );
    });

    test('body deposits', () {
      expectUnknown(
        (s) => s
            .body('kora')
            .deposits
            .add(const DepositDef(resourceId: 'nope', richness: 1)),
      );
    });

    test('auto-sell resource', () {
      expectUnknown(
        (s) => s.faction('player').autoSell.add(rule(resource: 'nope')),
      );
    });

    test('auto-sell body', () {
      expectUnknown(
        (s) => s.faction('player').autoSell.add(rule(body: 'nope')),
      );
    });

    test('route from-body', () {
      expectUnknown((s) => s.routes.add(route(from: 'nope')));
    });

    test('route to-body', () {
      expectUnknown((s) => s.routes.add(route(to: 'nope')));
    });

    test('shipment body', () {
      expectUnknown((s) => s.shipments.add(shipment(to: 'nope')));
    });

    test('shipment resource', () {
      expectUnknown((s) => s.shipments.add(shipment(resource: 'nope')));
    });
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
