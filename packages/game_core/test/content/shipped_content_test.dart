import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Reads every `content/*.json` at the repo root into a bundle by file stem.
Map<String, Object?> _shippedBundle() {
  final dir = Directory('../../content');
  return {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.json'))
        f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(
          f.readAsStringSync(),
        ),
  };
}

/// Resources that can be made from [deposits] alone, with no trade.
Set<String> _producible(Content c, Iterable<String> deposits) {
  final made = {
    for (final b in c.buildings.values)
      if (b.kind == BuildingKind.extractor)
        for (final r in b.extracts)
          if (deposits.contains(r)) r,
  };
  var grew = true;
  while (grew) {
    grew = false;
    for (final b in c.buildings.values) {
      if (b.kind == BuildingKind.extractor) continue;
      if (!b.inputs.keys.every(made.contains)) continue;
      for (final r in b.outputs.keys) {
        if (made.add(r)) grew = true;
      }
    }
  }
  return made;
}

Iterable<String> _depositsOf(Iterable<BodyDef> bodies) => [
  for (final b in bodies)
    for (final d in b.deposits) d.resourceId,
];

void main() {
  final result = Content.fromBundle(_shippedBundle());

  test('shipped content is valid', () {
    expect(
      result,
      isA<ContentOk>(),
      reason: result is ContentInvalid ? result.errors.join('\n') : null,
    );
  });

  final content = (result as ContentOk).content;
  final system = content.galaxy.systems.single;
  final bodies = {for (final b in system.bodies) b.id: b};
  final player = content.galaxy.factions.singleWhere((f) => f.isPlayer);
  final home = bodies[player.homeBodyId]!;
  final kit = content.rules.outpostKitResource;

  test('outpost kit needs deposits from at least 2 bodies', () {
    expect(_producible(content, _depositsOf(bodies.values)), contains(kit));
    for (final b in bodies.values) {
      expect(
        _producible(content, _depositsOf([b])),
        isNot(contains(kit)),
        reason: '${b.name} alone can make outpost kits',
      );
    }
  });

  test('home plus any one claimed body can make an outpost kit', () {
    // The second claim costs a kit, so no first claim may be a dead end.
    for (final b in bodies.values.where((b) => b != home)) {
      expect(
        _producible(content, _depositsOf([home, b])),
        contains(kit),
        reason: 'stuck after claiming ${b.name} first',
      );
    }
  });

  test('crew growth is possible after any single first claim', () {
    // Habitats need their inputs plus a habitat module. Whatever the
    // player claims first, at most one more claim, any one of the rest,
    // restores crew growth, and three different first claims give it
    // straight away (no single body is the only way).
    final habitat = content.buildings.values.singleWhere(
      (b) => b.kind == BuildingKind.habitat,
    );
    final needs = {...habitat.inputs.keys, ...habitat.buildCost.keys}
      ..remove('credits');
    bool housing(Iterable<BodyDef> bs) =>
        _producible(content, _depositsOf([home, ...bs])).containsAll(needs);
    final others = bodies.values.where((b) => b != home).toList();
    final atOnce = [
      for (final first in others)
        if (housing([first])) first.name,
    ];
    expect(atOnce.length, greaterThanOrEqualTo(3), reason: '$atOnce');
    for (final first in others) {
      for (final second in others.where((b) => b != first)) {
        expect(
          housing([first, second]),
          isTrue,
          reason: 'no crew growth after ${first.name} then ${second.name}',
        );
      }
    }
  });

  test('raw goods sell for at most 40% of what refining them earns', () {
    // Value added per chain step: every recipe's raw inputs at base price
    // are worth at most 40% of its outputs.
    for (final b in content.buildings.values) {
      if (b.kind != BuildingKind.factory) continue;
      double worth(String id, double n) =>
          n * content.resources[id]!.basePrice.toDouble();
      final out = b.outputs.entries.fold(
        0.0,
        (t, e) => t + worth(e.key, e.value),
      );
      for (final MapEntry(key: id, value: n) in b.inputs.entries) {
        if (content.resources[id]!.tier != 0) continue;
        expect(
          worth(id, n),
          lessThanOrEqualTo(0.4 * out),
          reason: '${b.id}: $n $id against outputs worth $out',
        );
      }
    }
  });

  test('cargo ships and habitat modules can be made at home', () {
    // Routes need ships before any goods can move between bodies.
    final atHome = _producible(content, _depositsOf([home]));
    expect(atHome, contains(content.rules.cargoShipResource));
    expect(atHome, contains('habitat_module'));
  });

  test('life support is made within the home system', () {
    final habitat = content.buildings.values.singleWhere(
      (b) => b.kind == BuildingKind.habitat,
    );
    expect(habitat.inputs.keys, unorderedEquals(['food', 'water', 'oxygen']));
    expect(habitat.housing, greaterThan(0));
    // Habitats need no crew, so a full crew pool can always grow.
    expect(habitat.crewSlots, 0);
    expect(
      _producible(content, _depositsOf(bodies.values)),
      containsAll(habitat.inputs.keys),
    );
  });

  test('electrolysis is a multi-output recipe', () {
    expect(content.buildings['electrolyzer']!.inputs.keys, ['water']);
    expect(content.buildings['electrolyzer']!.outputs.keys, [
      'oxygen',
      'hydrogen',
    ]);
  });

  test('stage-1 galaxy and starting setup', () {
    expect(system.bodies.map((b) => b.name), {
      'Kora',
      'Hollow Reach',
      'Brine',
      'Vastmere',
      'Cinder',
    });
    expect(home.name, 'Kora');
    expect(content.galaxy.factions, [player]);
    expect(player.baseCrew, 20);
    expect(player.buildings.map((b) => (b.defId, b.depositResourceId)), [
      ('mine', 'iron_ore'),
      ('mine', 'copper_ore'),
      ('smelter', null),
    ]);
    expect(content.rules.claimBaseCredits, BigNum.from(5000));
    expect(content.milestones, hasLength(19));
  });
}
