import 'dart:convert';
import 'dart:math' as math;
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
  // The five bodies in sight from the start. The hidden ones are surveyed
  // later, so the early-game reachability tests below leave them out.
  final bodies = {
    for (final b in system.bodies)
      if (!b.hidden) b.id: b,
  };
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

  test('crew grows after any two claims, or after one of three first '
      'claims', () {
    // Habitats need their inputs plus a habitat module. Whatever the
    // player claims first, at most one more claim, any one of the rest,
    // restores crew growth, and three different first claims give it
    // straight away (no single body is the only way). Cinder alone does
    // not: home plus Cinder has no water or hydrogen source for life
    // support, so a player who claims it first needs a second claim.
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
    expect(housing([bodies['cinder']!]), isFalse);
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
    // Value added per chain step: every recipe's raw inputs together, at
    // base price, are worth at most 40% of its outputs.
    for (final b in content.buildings.values) {
      if (b.kind != BuildingKind.factory) continue;
      double worth(String id, double n) =>
          n * content.resources[id]!.basePrice.toDouble();
      final out = b.outputs.entries.fold(
        0.0,
        (t, e) => t + worth(e.key, e.value),
      );
      final raw = b.inputs.entries
          .where((e) => content.resources[e.key]!.tier == 0)
          .fold(0.0, (t, e) => t + worth(e.key, e.value));
      expect(
        raw,
        lessThanOrEqualTo(0.4 * out),
        reason: '${b.id}: raw inputs worth $raw against outputs worth $out',
      );
    }
  });

  test('the hydrogen furnace cannot feed itself with an electrolyzer', () {
    // The electrolyzer turns the furnace's water back into hydrogen; the
    // furnace must use more hydrogen a cycle than that gives back, or the
    // pair would make steel and oxygen from iron ore alone.
    final furnace = content.buildings['hydrogen_furnace']!;
    final electrolyzer = content.buildings['electrolyzer']!;
    final back =
        furnace.outputs['water']! /
        electrolyzer.inputs['water']! *
        electrolyzer.outputs['hydrogen']!;
    expect(furnace.inputs['hydrogen']!, greaterThan(back));
  });

  group('every building is the best choice somewhere', () {
    // Per-crew and per-slot rates at level 0 and base crew.
    double perSlot(String defId, String resourceId) {
      final d = content.buildings[defId]!;
      return d.outputs[resourceId]! / d.cycleSeconds;
    }

    double perCrew(String defId, String resourceId) =>
        perSlot(defId, resourceId) / content.buildings[defId]!.crewSlots;

    double perInput(String defId, String out, String input) {
      final d = content.buildings[defId]!;
      return d.outputs[out]! / d.inputs[input]!;
    }

    test('smelter: steel from iron ore alone, the cheapest to build', () {
      final smelter = content.buildings['smelter']!;
      final furnace = content.buildings['hydrogen_furnace']!;
      expect(smelter.inputs.keys, ['iron_ore']);
      expect(
        smelter.buildCost['credits']!,
        lessThan(furnace.buildCost['credits']!),
      );
    });

    test('hydrogen furnace: more steel per iron ore, and water too', () {
      // Best where iron ore is shipped in and hydrogen is local, such as a
      // gas giant, and a water source on a body with no ice.
      expect(
        perInput('hydrogen_furnace', 'steel', 'iron_ore'),
        greaterThan(perInput('smelter', 'steel', 'iron_ore')),
      );
      expect(content.buildings['hydrogen_furnace']!.outputs, contains('water'));
    });

    test('hydroponic farm: the most food per crew where ammonia is', () {
      expect(
        perCrew('farm', 'food'),
        greaterThan(perCrew('protein_vat', 'food')),
      );
      expect(content.buildings['farm']!.inputs, contains('fertilizer'));
    });

    test('protein vat: food from water ice alone, with an electrolyzer', () {
      // A body with ice but no ammonia can still keep habitats fed.
      expect(_producible(content, ['water_ice']), contains('food'));
      expect(
        content.buildings.values
            .where((b) => b.outputs.containsKey('food'))
            .where((b) => !b.inputs.containsKey('fertilizer'))
            .map((b) => b.id),
        ['protein_vat'],
      );
    });

    test('fuel: refinery per crew, fusion per slot, mixer on volcanic '
        'worlds', () {
      const makers = ['fuel_refinery', 'fusion_refinery', 'propellant_mixer'];
      expect(
        content.buildings.values
            .where((b) => b.outputs.containsKey('fuel'))
            .map((b) => b.id)
            .toSet(),
        makers.toSet(),
      );
      String best(double Function(String, String) rate) =>
          makers.reduce((a, b) => rate(a, 'fuel') >= rate(b, 'fuel') ? a : b);
      expect(best(perCrew), 'fuel_refinery');
      expect(best(perSlot), 'fusion_refinery');
      // Cinder's deposits alone make fuel only through the mixer.
      final cinder = bodies['cinder']!;
      expect(_producible(content, _depositsOf([cinder])), contains('fuel'));
      expect(content.buildings['propellant_mixer']!.inputs.keys, ['sulfur']);
    });

    test('depot: Orbital Station stages outgrow a body without one', () {
      // From the stage to level 4 on, a stage needs more of one good than
      // the base storage cap holds; the depot is the one building that
      // adds storage.
      final station = content.megaprojects['orbital_station']!;
      final toLevel4 = megaprojectCost(content, station, 3);
      final most = toLevel4.entries
          .where((e) => e.key != 'credits')
          .map((e) => e.value.toDouble())
          .reduce(math.max);
      expect(most, greaterThan(content.rules.baseStorageCap));
      expect(
        content.buildings.values
            .where((b) => b.kind == BuildingKind.warehouse)
            .map((b) => b.id),
        ['depot'],
      );
    });
  });

  test('kits, habitat modules and cargo ships come in tens, not hundreds', () {
    // Their makers have no speed or capacity track: each makes a fixed
    // trickle, at most 100 in 6 h, and more takes another building.
    const items = ['outpost_kit', 'habitat_module', 'cargo_ship'];
    for (final d in content.buildings.values) {
      final made = items.where(d.outputs.containsKey).toList();
      if (made.isEmpty) continue;
      expect(d.upgrades.keys, [UpgradeTrack.efficiency], reason: d.id);
      for (final id in made) {
        expect(
          21600 / d.cycleSeconds * d.outputs[id]!,
          inInclusiveRange(10, 100),
          reason: '${d.id} makes $id',
        );
      }
    }
  });

  test('a capacity level never pays back over 2x faster than speed', () {
    // One more crew adds `1 / crew` of a building's output, a speed level
    // at least `speedPerLevel − 1` of it; the costs compared at the same
    // speed level, full crew, any capacity level.
    final r = content.rules;
    for (final d in content.buildings.values) {
      if (!d.upgrades.containsKey(UpgradeTrack.speed) ||
          !d.upgrades.containsKey(UpgradeTrack.capacity)) {
        continue;
      }
      for (final speed in [0, 1, 10, 24, 50, 100, 200]) {
        for (final cap in [0, 1, 2, 5, 10]) {
          final b = BuildingState(
            id: 'x',
            defId: d.id,
            crew: d.crewSlots + cap,
            levels: {UpgradeTrack.speed: speed, UpgradeTrack.capacity: cap},
          );
          double cost(UpgradeTrack t) =>
              upgradeCost(content, b, t)['credits']!.toDouble();
          final speedGain =
              speedMultiplier(r, speed + 1) / speedMultiplier(r, speed) - 1;
          final capGain = 1 / b.crew;
          final ratio =
              (cost(UpgradeTrack.speed) / speedGain) /
              (cost(UpgradeTrack.capacity) / capGain);
          expect(
            ratio,
            lessThanOrEqualTo(2),
            reason: '${d.id} at speed $speed, capacity $cap',
          );
        }
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

  test('credit milestones count credits earned; goods count units made', () {
    for (final m in content.milestones) {
      expect(m.condition, isNot(isA<CreditsCondition>()), reason: m.id);
      expect(m.condition, isNot(isA<StockCondition>()), reason: m.id);
    }
    expect(
      content.milestones.where((m) => m.condition is CreditsEarnedCondition),
      hasLength(15),
    );
    expect(
      content.milestones.where((m) => m.condition is ProducedCondition),
      hasLength(8),
    );
  });

  group('milestones', () {
    test('there are over fifty, with unique names', () {
      expect(content.milestones.length, inInclusiveRange(50, 60));
      expect(
        content.milestones.map((m) => m.name).toSet(),
        hasLength(content.milestones.length),
      );
    });

    test('each is reachable in principle', () {
      final hidden = system.bodies.where((b) => b.hidden).length;
      final made = _producible(content, _depositsOf(system.bodies));
      for (final m in content.milestones) {
        switch (m.condition) {
          case ProducedCondition(:final resourceId) ||
              ProductionRateCondition(:final resourceId):
            expect(made, contains(resourceId), reason: m.id);
          case BuildingTypesBuiltCondition(:final count):
            expect(count, lessThanOrEqualTo(content.buildings.length));
          case BodiesSurveyedCondition(:final count):
            expect(count, lessThanOrEqualTo(hidden), reason: m.id);
          case MegaprojectLevelCondition(:final megaprojectId, :final level):
            expect(content.megaprojects, contains(megaprojectId));
            expect(level, lessThanOrEqualTo(SaveCodec.maxMegaprojectLevel));
          case BodiesOwnedCondition(:final count):
            expect(count, lessThanOrEqualTo(system.bodies.length));
          case BuildingCountCondition(:final defId):
            expect(content.buildings, contains(defId));
          case StockCondition() ||
              CreditsCondition() ||
              CreditsEarnedCondition() ||
              ContractsCompletedCondition() ||
              CrewTotalCondition() ||
              ZeroWasteForCondition():
            break;
        }
      }
    });

    test('every new condition type is used', () {
      final types = content.milestones.map((m) => m.condition.runtimeType);
      expect(
        types,
        containsAll([
          ProductionRateCondition,
          BuildingTypesBuiltCondition,
          CrewTotalCondition,
          MegaprojectLevelCondition,
          ContractsCompletedCondition,
          ZeroWasteForCondition,
          BodiesSurveyedCondition,
        ]),
      );
      final earned = [
        for (final m in content.milestones)
          if (m.condition case CreditsEarnedCondition(:final amount)) amount,
      ];
      expect(earned.any((a) => a >= BigNum.parse('1e12')), isTrue);
    });
  });

  test('stage-1 galaxy and starting setup', () {
    expect(bodies.values.map((b) => b.name), {
      'Kora',
      'Hollow Reach',
      'Brine',
      'Vastmere',
      'Cinder',
    });
    // Seven bodies in all since stage 1.5: two more hidden until surveyed.
    expect(system.bodies, hasLength(7));
    expect(home.name, 'Kora');
    expect(content.galaxy.factions, [player]);
    expect(player.baseCrew, 20);
    expect(player.buildings.map((b) => (b.defId, b.depositResourceId)), [
      ('mine', 'iron_ore'),
      ('mine', 'copper_ore'),
      ('smelter', null),
    ]);
    expect(content.rules.claimBaseCredits, BigNum.from(5000));
    expect(content.milestones, hasLength(56));
  });

  group('hidden bodies', () {
    final hidden = system.bodies.where((b) => b.hidden).toList();

    test('there are two: an outer ice moon and a Kuiper rock', () {
      expect(hidden.map((b) => (b.name, b.typeId)), [
        ('Tessaly', 'ice_moon'),
        ('Dusk Cairn', 'kuiper'),
      ]);
      expect(hidden.any((b) => b.id == home.id), isFalse);
    });

    test('their deposits are richer than any visible body\'s of the same '
        'resource', () {
      double best(Iterable<BodyDef> bs, String r) => bs
          .expand((b) => b.deposits)
          .where((d) => d.resourceId == r)
          .fold(0.0, (m, d) => d.richness > m ? d.richness : m);
      for (final b in hidden) {
        for (final d in b.deposits) {
          expect(
            d.richness,
            greaterThan(best(bodies.values, d.resourceId)),
            reason: '${b.name} ${d.resourceId}',
          );
        }
      }
    });

    test('the Kuiper rock mines what magnets and reactors need', () {
      final rock = hidden.singleWhere((b) => b.typeId == 'kuiper');
      expect(rock.deposits.map((d) => d.resourceId), [
        'rare_earths',
        'nickel',
        'helium_3',
      ]);
    });

    test('survey drones are made, and used up by surveys', () {
      final drone = content.rules.surveyDroneResource;
      expect(drone, 'survey_drone');
      expect(content.rules.surveyDrones, 3);
      expect(_producible(content, _depositsOf(bodies.values)), contains(drone));
      expect(surveyCost(content)[drone], BigNum.from(3));
      expect(surveySeconds(content), inInclusiveRange(7200, 14400));
    });
  });
}
