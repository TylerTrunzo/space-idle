import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Placeholder replaced by the number literal `1e999` in the save text.
const _huge = '__huge__';

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
          fromBodyId: 'kora',
          toBodyId: to,
          ownerId: 'player',
          resourceId: resource,
          amount: BigNum.parse('1'),
          departAt: 0,
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

    test('sales revenue resource', () {
      expectUnknown(
        (s) => s.faction('player').salesRevenue['nope'] = BigNum.parse('1'),
      );
    });

    test('market saturation resource', () {
      expectUnknown((s) => s.market.saturation['nope'] = 0.5);
    });

    test('lifetime produced resource', () {
      expectUnknown(
        (s) => s.faction('player').lifetimeProduced['nope'] = BigNum.parse('1'),
      );
    });

    test('seen bottleneck resource and body', () {
      for (final (body, resource) in [('kora', 'nope'), ('nope', 'steel')]) {
        expectUnknown(
          (s) => s
              .faction('player')
              .seenBottlenecks
              .add(
                SeenBottleneck(
                  kind: 'storageFull',
                  bodyId: body,
                  resourceId: resource,
                  firstSeenAt: 0,
                ),
              ),
        );
      }
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

  test('decode rejects a shipment without its source, owner or departure', () {
    for (final field in ['fromBodyId', 'ownerId', 'departAt']) {
      final m = fresh()
        ..['shipments'] = [
          {
            'routeId': 'r1',
            'fromBodyId': 'kora',
            'toBodyId': 'brine',
            'ownerId': 'player',
            'resourceId': 'iron_ore',
            'amount': '1',
            'departAt': 0,
            'arriveAt': 5,
          }..remove(field),
        ];
      expect(
        err(SaveCodec.decode(jsonEncode(m), content)).kind,
        SaveErrorKind.missingField,
        reason: field,
      );
    }
  });

  group('decode rejects saves the engine cannot run:', () {
    // Each case breaks one integrity rule in an otherwise valid save.
    List<Map<String, Object?>> list(Object? v) =>
        (v! as List).cast<Map<String, Object?>>();
    Map<String, Object?> body(Map<String, Object?> m, String id) =>
        list(m['bodies']).firstWhere((b) => b['id'] == id);
    Map<String, Object?> building(Map<String, Object?> m, int i) =>
        list(body(m, 'kora')['buildings'])[i];
    Map<String, Object?> player(Map<String, Object?> m) =>
        list(m['factions']).first;
    Map<String, Object?> route({String owner = 'player', String id = 'r1'}) => {
      'id': id,
      'ownerId': owner,
      'fromBodyId': 'kora',
      'toBodyId': 'cinder',
      'resourceId': 'iron_ore',
      'ratePerSecond': '1',
      'cargoShips': 1,
    };
    Map<String, Object?> shipment({String owner = 'player'}) => {
      'routeId': 'r1',
      'fromBodyId': 'kora',
      'toBodyId': 'cinder',
      'ownerId': owner,
      'resourceId': 'iron_ore',
      'amount': '1',
      'departAt': 0,
      'arriveAt': 5,
    };

    final cases = <String, void Function(Map<String, Object?>)>{
      'body owned by a missing faction': (m) =>
          body(m, 'brine')['ownerId'] = 'ghost',
      'route owned by a missing faction': (m) =>
          m['routes'] = [route(owner: 'ghost')],
      'shipment owned by a missing faction': (m) =>
          m['shipments'] = [shipment(owner: 'ghost')],
      'no player faction': (m) => player(m)['isPlayer'] = false,
      'no factions at all': (m) => m['factions'] = <Object?>[],
      'two player factions': (m) => m['factions'] = [
        player(m),
        {...player(m), 'id': 'player2'},
      ],
      'duplicate faction id': (m) => m['factions'] = [
        player(m),
        {...player(m), 'isPlayer': false},
      ],
      'duplicate body id': (m) => body(m, 'brine')['id'] = 'kora',
      'duplicate building id': (m) =>
          building(m, 1)['id'] = building(m, 0)['id'],
      'duplicate route id': (m) => m['routes'] = [route(), route()],
      'nextId at a building id in use': (m) => m['nextId'] = 3,
      'nextId below a route id in use': (m) => m['routes'] = [route(id: 'r40')],
      'building id suffix too large for an int': (m) =>
          building(m, 0)['id'] = 'b99999999999999999999999',
      'route id suffix too large for an int': (m) =>
          m['routes'] = [route(id: 'r99999999999999999999999')],
      'negative extra slots': (m) => body(m, 'kora')['extraSlots'] = -1,
      'extra slots above 1000': (m) => body(m, 'kora')['extraSlots'] = 1001,
      'more buildings than build slots': (m) {
        final b = body(m, 'cinder');
        b['buildings'] = [
          for (var i = 0; i < 7; i++)
            {...building(m, 2), 'id': 'b${100 + i}', 'crew': 0},
        ];
        m['nextId'] = 200;
      },
      'negative crew': (m) => building(m, 0)['crew'] = -1,
      'crew above the building slots': (m) => building(m, 0)['crew'] = 2,
      'negative upgrade level': (m) =>
          (building(m, 0)['levels']! as Map)['speed'] = -3,
      'upgrade level above 1000': (m) =>
          (building(m, 0)['levels']! as Map)['speed'] = 100000,
      'run fraction outside [0, 1]': (m) =>
          building(m, 0)['lastRunFraction'] = 1.5,
      'negative stock': (m) =>
          (body(m, 'kora')['stock']! as Map)['iron_ore'] = '-5e3',
      'negative keepAtLeast': (m) => player(m)['autoSell'] = [
        {'bodyId': 'kora', 'resourceId': 'iron_ore', 'keepAtLeast': '-1e9'},
      ],
      'two auto-sell rules for one body and resource': (m) =>
          player(m)['autoSell'] = [
            {'bodyId': 'kora', 'resourceId': 'iron_ore', 'keepAtLeast': '0'},
            {'bodyId': 'kora', 'resourceId': 'iron_ore', 'keepAtLeast': '5'},
          ],
      'negative credits': (m) => player(m)['credits'] = '-1',
      'negative sales revenue': (m) =>
          player(m)['salesRevenue'] = {'iron_ore': '-1'},
      'negative lifetime credits': (m) => player(m)['lifetimeCredits'] = '-1',
      'negative lifetime produced': (m) =>
          player(m)['lifetimeProduced'] = {'steel': '-1'},
      'bottleneck seen after the save time': (m) =>
          player(m)['seenBottlenecks'] = [
            {
              'kind': 'noCrew',
              'bodyId': 'kora',
              'buildingId': 'b1',
              'firstSeenAt': 5,
            },
          ],
      'bottleneck of an unknown kind': (m) => player(m)['seenBottlenecks'] = [
        {'kind': 'vibes', 'bodyId': 'kora', 'firstSeenAt': 0},
      ],
      'the same bottleneck twice': (m) => player(m)['seenBottlenecks'] = [
        {
          'kind': 'noCrew',
          'bodyId': 'kora',
          'buildingId': 'b1',
          'firstSeenAt': 0,
        },
        {
          'kind': 'noCrew',
          'bodyId': 'kora',
          'buildingId': 'b1',
          'firstSeenAt': 0,
        },
      ],
      'negative base crew': (m) => player(m)['baseCrew'] = -1,
      'saturation above 1': (m) => m['market'] = {
        'saturation': {'iron_ore': 5},
      },
      'saturation below the market floor': (m) => m['market'] = {
        'saturation': {'iron_ore': -0.1},
      },
      'extractor on a deposit its body lacks': (m) =>
          building(m, 0)['depositResourceId'] = 'nickel',
      'extractor with no deposit': (m) =>
          building(m, 0)['depositResourceId'] = null,
      'extractor on a deposit it cannot mine': (m) {
        (body(m, 'kora')['deposits']! as List).add({
          'resourceId': 'water_ice',
          'richness': 1,
        });
        building(m, 0)['depositResourceId'] = 'water_ice';
      },
      'deposit richness not above 0': (m) =>
          (list(body(m, 'kora')['deposits']).first)['richness'] = 0,
      'route without a cargo ship': (m) =>
          m['routes'] = [route()..['cargoShips'] = 0],
      'route rate not above 0': (m) =>
          m['routes'] = [route()..['ratePerSecond'] = '0'],
      'negative shipment amount': (m) =>
          m['shipments'] = [shipment()..['amount'] = '-1'],
      'negative time': (m) => m['time'] = -1,
      // JSON can spell a number too large for a double; it reads as
      // infinity.
      'time too large to be finite': (m) => m['time'] = _huge,
    };
    for (final MapEntry(key: name, value: corrupt) in cases.entries) {
      test(name, () {
        final m = jsonDecode(jsonEncode(fresh())) as Map<String, Object?>;
        corrupt(m);
        final text = jsonEncode(m).replaceAll('"$_huge"', '1e999');
        final r = SaveCodec.decode(text, content);
        expect(r, isA<SaveError>(), reason: name);
        expect((r as SaveError).kind, SaveErrorKind.invalidValue);
        expect(r.message, isNotEmpty);
      });
    }

    test('a body in an unknown system is an unknown content id', () {
      final m = fresh();
      body(m, 'brine')['systemId'] = 'nowhere';
      expect(
        err(SaveCodec.decode(jsonEncode(m), content)).kind,
        SaveErrorKind.unknownContentId,
      );
    });

    test('a game played for a while still loads', () {
      final s = newGameState(content, 3);
      final e = GameEngine(content);
      e
        ..apply(s, SetAutoSellCommand('player', 'kora', 'steel', BigNum.zero()))
        ..apply(
          s,
          const BuildCommand(
            'player',
            'kora',
            'mine',
            depositResourceId: 'silicon',
          ),
        )
        ..advance(s, 86400);
      expect(SaveCodec.decode(SaveCodec.encode(s), content), isA<SaveOk>());
    });
  });

  group('float residue in a save', () {
    // A balanced-bot save stored −2.2e-16 cargo ships on Cinder: float
    // residue of taking the last ship, not a real overdraw.
    Map<String, Object?> withCinderShips(String v) {
      final m = jsonDecode(jsonEncode(fresh())) as Map<String, Object?>;
      final cinder = (m['bodies']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((b) => b['id'] == 'cinder');
      cinder['ownerId'] = 'player';
      (cinder['stock']! as Map)['cargo_ship'] = v;
      return m;
    }

    test('a tiny negative stock loads as zero', () {
      final r = SaveCodec.decode(
        jsonEncode(withCinderShips('-2.220446049250313e-16')),
        content,
      );
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      final stock = (r as SaveOk).state.body('cinder').stock['cargo_ship'];
      expect(stock, const BigNum.zero());
      expect(stock!.isNegative, isFalse);
    });

    test('a negative stock beyond residue is still rejected', () {
      final r = SaveCodec.decode(jsonEncode(withCinderShips('-1e-3')), content);
      expect(err(r).kind, SaveErrorKind.invalidValue);
    });
  });

  test('a save without sales revenue loads with none', () {
    final m = fresh();
    (m['factions']! as List).cast<Map<String, Object?>>().first.remove(
      'salesRevenue',
    );
    final r = SaveCodec.decode(jsonEncode(m), content);
    expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
    expect((r as SaveOk).state.faction('player').salesRevenue, isEmpty);
  });

  test('a save without lifetime totals loads with earnings from its sales', () {
    final m = fresh();
    (m['factions']! as List).cast<Map<String, Object?>>().first
      ..remove('lifetimeCredits')
      ..remove('lifetimeProduced')
      ..['salesRevenue'] = {'steel': '30', 'iron_ore': '12'};
    final r = SaveCodec.decode(jsonEncode(m), content);
    expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
    final f = (r as SaveOk).state.faction('player');
    expect(f.lifetimeCredits, BigNum.from(42));
    expect(f.lifetimeProduced, isEmpty);
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
    final m3 = fresh();
    ((m3['bodies']! as List).first as Map).remove('extraSlots');
    expect(
      err(SaveCodec.decode(jsonEncode(m3), content)).kind,
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
