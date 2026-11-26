import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// A small valid bundle. Each call returns a fresh, mutable deep copy.
Map<String, Object?> minimalBundle() =>
    jsonDecode(jsonEncode(_minimal)) as Map<String, Object?>;

const _minimal = {
  'rules': {
    'speedPerLevel': 1.1,
    'speedMilestoneEvery': 25,
    'speedMilestoneMult': 2,
    'efficiencyPerLevel': 0.95,
    'efficiencyFloor': 0.25,
    'capacityCrewPerLevel': 1,
    'capacityStoragePerLevel': 0.2,
    'baseStorageCap': 1000,
    'offlineCapSeconds': 43200,
    'marketFloor': 0.2,
    'marketRecoverySeconds': 3600,
    'claimBaseCredits': '5e3',
    'claimGrowth': 4,
    'slotBaseCredits': '1e4',
    'slotGrowth': 2,
    'outpostKitResource': 'kit',
    'shipCapacityPerSecond': 2,
    'cargoShipResource': 'ship',
    'baseTravelSeconds': 120,
  },
  'resources': [
    {'id': 'ore', 'name': 'Ore', 'tier': 0, 'basePrice': '1'},
    {'id': 'bar', 'name': 'Bar', 'tier': 1, 'basePrice': '3'},
    {
      'id': 'ship',
      'name': 'Ship',
      'tier': 2,
      'basePrice': '10',
      'marketDepth': 500,
    },
    {'id': 'kit', 'name': 'Kit', 'tier': 2, 'basePrice': '20'},
  ],
  'buildings': [
    {
      'id': 'mine',
      'name': 'Mine',
      'kind': 'extractor',
      'cycleSeconds': 5,
      'extracts': ['ore'],
      'outputs': {'ore': 2},
      'crewSlots': 1,
      'buildCost': {'credits': '100'},
      'upgrades': {
        'speed': {'baseCredits': '50', 'growth': 1.2},
      },
    },
    {
      'id': 'smelter',
      'name': 'Smelter',
      'kind': 'factory',
      'cycleSeconds': 5,
      'inputs': {'ore': 2},
      'outputs': {'bar': 1},
      'crewSlots': 1,
      'buildCost': {'credits': '150'},
    },
    {
      'id': 'yard',
      'name': 'Yard',
      'kind': 'factory',
      'cycleSeconds': 30,
      'inputs': {'bar': 4},
      'outputs': {'ship': 1, 'kit': 1},
      'crewSlots': 2,
      'buildCost': {'credits': '500', 'bar': '10'},
    },
  ],
  'body_types': [
    {
      'id': 'rock',
      'name': 'Rock',
      'depositPool': ['ore'],
      'buildSlots': 4,
    },
  ],
  'galaxy': {
    'systems': [
      {
        'id': 'home',
        'name': 'Home',
        'bodies': [
          {
            'id': 'b1',
            'name': 'B1',
            'typeId': 'rock',
            'orbit': 1,
            'deposits': [
              {'resourceId': 'ore', 'richness': 1.5},
            ],
          },
        ],
      },
    ],
    'factions': [
      {
        'id': 'p',
        'name': 'P',
        'isPlayer': true,
        'homeBodyId': 'b1',
        'credits': '100',
        'baseCrew': 2,
        'buildings': [
          {'defId': 'mine', 'depositResourceId': 'ore', 'crew': 1},
        ],
        'stock': {'ore': '5'},
      },
    ],
  },
  'milestones': [
    {
      'id': 'm1',
      'name': 'M1',
      'condition': {'type': 'credits', 'amount': '1e3'},
    },
    {
      'id': 'm2',
      'name': 'M2',
      'condition': {'type': 'stock', 'resource': 'bar', 'amount': '100'},
    },
    {
      'id': 'm3',
      'name': 'M3',
      'condition': {'type': 'bodiesOwned', 'count': 2},
    },
    {
      'id': 'm4',
      'name': 'M4',
      'condition': {'type': 'buildingCount', 'defId': 'mine', 'count': 3},
    },
  ],
};

const _remove = Object();

List<Map<String, Object?>> _list(Map<String, Object?> b, String key) =>
    (b[key] as List).cast<Map<String, Object?>>();

Map<String, Object?> _entry(Map<String, Object?> b, String key, String id) =>
    _list(b, key).firstWhere((e) => e['id'] == id);

Map<String, Object?> _body(Map<String, Object?> b) {
  final galaxy = b['galaxy'] as Map<String, Object?>;
  final system = (galaxy['systems'] as List).first as Map<String, Object?>;
  return (system['bodies'] as List).first as Map<String, Object?>;
}

Content _ok(Map<String, Object?> b) => switch (Content.fromBundle(b)) {
  ContentOk(:final content) => content,
  ContentInvalid(:final errors) => fail('expected ContentOk, got $errors'),
};

List<String> _errors(Map<String, Object?> b) => switch (Content.fromBundle(b)) {
  ContentOk() => fail('expected ContentInvalid'),
  ContentInvalid(:final errors) => errors,
};

void main() {
  test('valid minimal bundle loads', () {
    final c = _ok(minimalBundle());
    expect(c.resources.keys, ['ore', 'bar', 'ship', 'kit']);
    expect(c.resources['ore']!.basePrice, BigNum.from(1));
    expect(c.resources['ore']!.marketDepth, 10000);
    expect(c.resources['ship']!.marketDepth, 500);
    expect(c.rules.claimBaseCredits, BigNum.from(5000));
    expect(c.rules.cargoShipResource, 'ship');

    final yard = c.buildings['yard']!;
    expect(yard.kind, BuildingKind.factory);
    expect(yard.outputs.keys, ['ship', 'kit']);
    expect(yard.buildCost, {
      'credits': BigNum.from(500),
      'bar': BigNum.from(10),
    });
    final mine = c.buildings['mine']!;
    expect(mine.extracts, ['ore']);
    expect(mine.upgrades[UpgradeTrack.speed]!.growth, 1.2);
    expect(mine.upgrades.containsKey(UpgradeTrack.efficiency), isFalse);

    final body = c.galaxy.systems.single.bodies.single;
    expect(body.deposits.single.richness, 1.5);
    final p = c.galaxy.factions.single;
    expect(p.isPlayer, isTrue);
    expect(p.buildings.single.depositResourceId, 'ore');
    expect(p.stock, {'ore': BigNum.from(5)});

    expect(c.milestones.map((m) => m.condition.runtimeType), [
      CreditsCondition,
      StockCondition,
      BodiesOwnedCondition,
      BuildingCountCondition,
    ]);
  });

  test('defs are immutable', () {
    final c = _ok(minimalBundle());
    expect(() => c.resources.remove('ore'), throwsUnsupportedError);
    expect(
      () => c.buildings['smelter']!.inputs['ore'] = 9,
      throwsUnsupportedError,
    );
  });

  test('unknown recipe input is reported', () {
    final b = minimalBundle();
    (_entry(b, 'buildings', 'smelter')['inputs'] as Map)['unobtainium'] = 1;
    expect(
      _errors(b),
      contains("buildings.smelter.inputs: unknown resource 'unobtainium'"),
    );
  });

  test('resource with no producer is reported', () {
    final b = minimalBundle();
    _list(
      b,
      'resources',
    ).add({'id': 'x', 'name': 'X', 'tier': 1, 'basePrice': '1'});
    expect(_errors(b), contains('resources.x: nothing produces it'));
  });

  test('resource whose producer needs unmakeable inputs is reported', () {
    final b = minimalBundle();
    // 'gem' is extractable but no body has the deposit, so 'cut' is stuck.
    _list(b, 'resources')
      ..add({'id': 'gem', 'name': 'Gem', 'tier': 0, 'basePrice': '1'})
      ..add({'id': 'cut', 'name': 'Cut', 'tier': 1, 'basePrice': '1'});
    final mine = _entry(b, 'buildings', 'mine');
    (mine['extracts'] as List).add('gem');
    (mine['outputs'] as Map)['gem'] = 1;
    _list(b, 'buildings').add({
      'id': 'cutter',
      'name': 'Cutter',
      'kind': 'factory',
      'cycleSeconds': 5,
      'inputs': {'gem': 1},
      'outputs': {'cut': 1},
      'crewSlots': 1,
      'buildCost': {'credits': '1'},
    });
    final errors = _errors(b);
    expect(errors, contains('resources.gem: nothing produces it'));
    expect(
      errors,
      contains('resources.cut: its producers need inputs that are never made'),
    );
  });

  test('resource never consumed and unsellable is reported', () {
    final b = minimalBundle();
    _entry(b, 'resources', 'bar')['basePrice'] = '0';
    _entry(b, 'buildings', 'yard')['inputs'] = {'ore': 1};
    _entry(b, 'buildings', 'yard')['buildCost'] = {'credits': '1'};
    expect(
      _errors(b),
      contains('resources.bar: never consumed and cannot be sold'),
    );
  });

  test('unreachable deposit type', () {
    final b = minimalBundle();
    _body(b)['typeId'] = 'nope';
    expect(
      _errors(b),
      contains(
        "galaxy.systems.home.bodies.b1.typeId: unknown body type 'nope'",
      ),
    );
  });

  test('missing required field gives error not throw', () {
    final b = minimalBundle();
    _entry(b, 'resources', 'ore').remove('name');
    expect(_errors(b), contains('resources.ore.name: missing'));
  });

  test('wrong shapes give errors not throws', () {
    final cases = <Map<String, Object?>>[
      {},
      {...minimalBundle(), 'resources': 5},
      {...minimalBundle(), 'rules': 'fast'},
      {...minimalBundle(), 'galaxy': []},
      {
        ...minimalBundle(),
        'buildings': [7, null, <String, Object?>{}],
      },
      {
        ...minimalBundle(),
        'milestones': [
          {
            'id': 'm',
            'name': 'M',
            'condition': {'type': 'vibes'},
          },
        ],
      },
    ];
    for (final b in cases) {
      expect(Content.fromBundle(b), isA<ContentInvalid>(), reason: '$b');
    }
    expect(_errors({}), contains('rules: missing'));
    expect(
      _errors({...minimalBundle(), 'resources': 5}),
      contains('resources: expected a list'),
    );
  });

  test('every node replaced or removed gives a result, never a throw', () {
    const junk = <Object?>[null, 7, -1.5, 'x', '', true, <Object?>[], {}];
    var variants = 0;
    // Visits each map entry and list element of a fresh bundle by path.
    void visit(List<Object> path) {
      Object? node = minimalBundle();
      for (final step in path) {
        node = step is int ? (node as List)[step] : (node as Map)[step];
      }
      final children = switch (node) {
        Map() => node.keys.cast<Object>().toList(),
        List() => [for (var i = 0; i < node.length; i++) i],
        _ => const <Object>[],
      };
      for (final child in children) {
        for (final replacement in [_remove, ...junk]) {
          final b = minimalBundle();
          Object? parent = b;
          for (final step in path) {
            parent = step is int
                ? (parent as List)[step]
                : (parent as Map)[step];
          }
          if (identical(replacement, _remove)) {
            parent is List
                ? parent.removeAt(child as int)
                : (parent as Map).remove(child);
          } else {
            parent is List
                ? parent[child as int] = replacement
                : (parent as Map)[child] = replacement;
          }
          expect(
            () => Content.fromBundle(b),
            returnsNormally,
            reason: '$path/$child = $replacement',
          );
          variants++;
        }
        visit([...path, child]);
      }
    }

    visit(const []);
    expect(variants, greaterThan(500));
  });

  test('bad values are reported with paths', () {
    final b = minimalBundle();
    _entry(b, 'resources', 'ore')['basePrice'] = 'lots';
    _entry(b, 'resources', 'bar')['tier'] = 9;
    _entry(b, 'buildings', 'mine')['kind'] = 'mill';
    (b['rules'] as Map)['claimGrowth'] = 'four';
    (b['rules'] as Map)['slotGrowth'] = 0.5;
    (b['rules'] as Map)['slotBaseCredits'] = '0';
    final errors = _errors(b);
    expect(
      errors,
      containsAll([
        'resources.ore.basePrice: expected a number string like "5e3"',
        'resources.bar.tier: must be <= 4',
        "buildings.mine.kind: unknown kind 'mill'",
        'rules.claimGrowth: expected a number',
        'rules.slotGrowth: must be >= 1',
        'rules.slotBaseCredits: must be > 0',
      ]),
    );
  });

  test('habitats may have no crew slots; extractors and factories may not', () {
    final b = minimalBundle();
    _list(
      b,
      'resources',
    ).add({'id': 'air', 'name': 'Air', 'tier': 1, 'basePrice': '1'});
    _list(b, 'buildings').addAll([
      {
        'id': 'vent',
        'name': 'Vent',
        'kind': 'factory',
        'cycleSeconds': 5,
        'inputs': {'ore': 1},
        'outputs': {'air': 1},
        'crewSlots': 1,
        'buildCost': {'credits': '10'},
      },
      {
        'id': 'dome',
        'name': 'Dome',
        'kind': 'habitat',
        'cycleSeconds': 10,
        'inputs': {'air': 1},
        'housing': 5,
        'crewSlots': 0,
        'buildCost': {'credits': '10'},
      },
    ]);
    expect(_ok(b).buildings['dome']!.crewSlots, 0);
    _entry(b, 'buildings', 'smelter')['crewSlots'] = 0;
    _entry(b, 'buildings', 'mine')['crewSlots'] = 0;
    expect(
      _errors(b),
      containsAll([
        'buildings.smelter.crewSlots: must be >= 1 for factory buildings',
        'buildings.mine.crewSlots: must be >= 1 for extractor buildings',
      ]),
    );
  });

  test('a resource may set its own market floor', () {
    final b = minimalBundle();
    _entry(b, 'resources', 'ore')['marketFloor'] = 0.02;
    final c = _ok(b);
    expect(c.resources['ore']!.marketFloor, 0.02);
    expect(c.resources['bar']!.marketFloor, isNull);
    expect(marketFloorOf(c, 'ore'), 0.02);
    expect(marketFloorOf(c, 'bar'), c.rules.marketFloor);
    _entry(b, 'resources', 'bar')['marketFloor'] = 1.5;
    expect(_errors(b), contains('resources.bar.marketFloor: must be <= 1'));
  });

  test('unknown fields are reported', () {
    final b = minimalBundle();
    _entry(b, 'buildings', 'smelter')['housng'] = 4;
    b['extras'] = <String, Object?>{};
    expect(
      _errors(b),
      containsAll([
        'buildings.smelter.housng: unknown field',
        'extras: unknown field',
      ]),
    );
  });

  test('duplicate ids are reported', () {
    final b = minimalBundle();
    _list(
      b,
      'resources',
    ).add({'id': 'ore', 'name': 'Ore again', 'tier': 0, 'basePrice': '1'});
    expect(_errors(b), contains('resources.ore: duplicate id'));
  });

  test('deposit not in body type pool', () {
    final b = minimalBundle();
    _list(
      b,
      'resources',
    ).add({'id': 'gem', 'name': 'Gem', 'tier': 0, 'basePrice': '1'});
    final mine = _entry(b, 'buildings', 'mine');
    (mine['extracts'] as List).add('gem');
    (mine['outputs'] as Map)['gem'] = 1;
    (_body(b)['deposits'] as List).add({'resourceId': 'gem', 'richness': 1});
    expect(
      _errors(b),
      contains(
        "galaxy.systems.home.bodies.b1.deposits: 'gem' is not in the "
        "'rock' deposit pool",
      ),
    );
  });

  test('rules resource ids must exist', () {
    final b = minimalBundle();
    (b['rules'] as Map)['cargoShipResource'] = 'boat';
    expect(
      _errors(b),
      contains("rules.cargoShipResource: unknown resource 'boat'"),
    );
  });

  test('build cost resources must exist', () {
    final b = minimalBundle();
    (_entry(b, 'buildings', 'yard')['buildCost'] as Map)['gold'] = '1';
    expect(
      _errors(b),
      contains("buildings.yard.buildCost: unknown resource 'gold'"),
    );
  });

  test('extractor outputs must match what it extracts', () {
    final b = minimalBundle();
    (_entry(b, 'buildings', 'mine')['outputs'] as Map)['bar'] = 1;
    expect(
      _errors(b),
      contains("buildings.mine.outputs: 'bar' is not in extracts"),
    );
  });

  test('starting faction is checked', () {
    final b = minimalBundle();
    final galaxy = b['galaxy'] as Map<String, Object?>;
    final p = (galaxy['factions'] as List).first as Map<String, Object?>;
    p['homeBodyId'] = 'nowhere';
    expect(
      _errors(b),
      contains("galaxy.factions.p.homeBodyId: unknown body 'nowhere'"),
    );

    final b2 = minimalBundle();
    final p2 =
        ((b2['galaxy'] as Map)['factions'] as List).first
            as Map<String, Object?>;
    final building = (p2['buildings'] as List).first as Map<String, Object?>;
    building['depositResourceId'] = 'bar';
    building['crew'] = 5;
    expect(
      _errors(b2),
      containsAll([
        "galaxy.factions.p.buildings[0].depositResourceId: 'mine' cannot "
            "extract 'bar'",
        'galaxy.factions.p.buildings[0].crew: exceeds 1 crew slots',
      ]),
    );
  });

  test('milestone references must exist', () {
    final b = minimalBundle();
    final m4 = _entry(b, 'milestones', 'm4');
    (m4['condition'] as Map)['defId'] = 'tower';
    expect(
      _errors(b),
      contains("milestones.m4.condition.defId: unknown building 'tower'"),
    );
  });
}
