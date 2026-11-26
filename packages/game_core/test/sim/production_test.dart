import 'dart:convert';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

const _rules = RulesDef(
  speedPerLevel: 1.1,
  speedMilestoneEvery: 25,
  speedMilestoneMult: 2,
  efficiencyPerLevel: 0.95,
  efficiencyFloor: 0.25,
  capacityCrewPerLevel: 1,
  capacityStoragePerLevel: 0.2,
  baseStorageCap: 1000,
  offlineCapSeconds: 43200,
  marketFloor: 0.2,
  marketRecoverySeconds: 3600,
  claimBaseCredits: BigNum.zero(),
  claimGrowth: 1,
  outpostKitResource: 'kit',
  shipCapacityPerSecond: 1,
  cargoShipResource: 'ship',
  baseTravelSeconds: 60,
);

RulesDef _rulesWith({double baseStorageCap = 1000}) => RulesDef(
  speedPerLevel: _rules.speedPerLevel,
  speedMilestoneEvery: _rules.speedMilestoneEvery,
  speedMilestoneMult: _rules.speedMilestoneMult,
  efficiencyPerLevel: _rules.efficiencyPerLevel,
  efficiencyFloor: _rules.efficiencyFloor,
  capacityCrewPerLevel: _rules.capacityCrewPerLevel,
  capacityStoragePerLevel: _rules.capacityStoragePerLevel,
  baseStorageCap: baseStorageCap,
  offlineCapSeconds: _rules.offlineCapSeconds,
  marketFloor: _rules.marketFloor,
  marketRecoverySeconds: _rules.marketRecoverySeconds,
  claimBaseCredits: _rules.claimBaseCredits,
  claimGrowth: _rules.claimGrowth,
  outpostKitResource: _rules.outpostKitResource,
  shipCapacityPerSecond: _rules.shipCapacityPerSecond,
  cargoShipResource: _rules.cargoShipResource,
  baseTravelSeconds: _rules.baseTravelSeconds,
);

ResourceDef _res(String id) =>
    ResourceDef(id: id, name: id, tier: 0, basePrice: n(1));

/// Small inline content: one system with an owned body `home` (iron ore
/// deposit, richness 1.5) and an unowned body `wild`.
Content _content({double baseStorageCap = 1000}) {
  final buildings = [
    BuildingDef(
      id: 'drill',
      name: 'Drill',
      kind: BuildingKind.extractor,
      cycleSeconds: 10,
      extracts: ['iron_ore'],
      outputs: {'iron_ore': 2},
      crewSlots: 2,
      buildCost: const {},
    ),
    BuildingDef(
      id: 'smelter',
      name: 'Smelter',
      kind: BuildingKind.factory,
      cycleSeconds: 10,
      inputs: {'iron_ore': 4},
      outputs: {'steel': 1},
      crewSlots: 1,
      buildCost: const {},
    ),
    BuildingDef(
      id: 'caster',
      name: 'Caster',
      kind: BuildingKind.factory,
      cycleSeconds: 10,
      inputs: {'iron_ore': 2},
      outputs: {'ingot': 1},
      crewSlots: 1,
      buildCost: const {},
    ),
    BuildingDef(
      id: 'works',
      name: 'Works',
      kind: BuildingKind.factory,
      cycleSeconds: 10,
      outputs: {'gadget': 1},
      crewSlots: 7,
      buildCost: const {},
    ),
    BuildingDef(
      id: 'habitat',
      name: 'Habitat',
      kind: BuildingKind.habitat,
      cycleSeconds: 10,
      inputs: {'food': 1, 'water': 1},
      crewSlots: 1,
      housing: 10,
      buildCost: const {},
    ),
    // Invalid for loaded content (validator wants slots >= 1), but inline
    // content can hold it; production must skip it.
    BuildingDef(
      id: 'pod',
      name: 'Pod',
      kind: BuildingKind.habitat,
      cycleSeconds: 10,
      inputs: {'water': 1},
      crewSlots: 0,
      housing: 10,
      buildCost: const {},
    ),
    BuildingDef(
      id: 'depot',
      name: 'Depot',
      kind: BuildingKind.warehouse,
      cycleSeconds: 1,
      crewSlots: 0,
      storageBonus: 1,
      buildCost: const {},
    ),
  ];
  return Content(
    rules: _rulesWith(baseStorageCap: baseStorageCap),
    resources: {
      for (final id in [
        'iron_ore',
        'steel',
        'ingot',
        'gadget',
        'food',
        'water',
      ])
        id: _res(id),
    },
    buildings: {for (final b in buildings) b.id: b},
    bodyTypes: {
      'rock': BodyTypeDef(
        id: 'rock',
        name: 'Rock',
        depositPool: ['iron_ore'],
        buildSlots: 10,
      ),
    },
    galaxy: GalaxyDef(
      systems: [
        SystemDef(
          id: 'sys',
          name: 'Sys',
          bodies: [
            for (final id in ['home', 'wild'])
              BodyDef(
                id: id,
                name: id,
                typeId: 'rock',
                orbit: 1,
                deposits: const [
                  DepositDef(resourceId: 'iron_ore', richness: 1.5),
                ],
              ),
          ],
        ),
      ],
      factions: [
        StartingFactionDef(
          id: 'p',
          name: 'P',
          isPlayer: true,
          homeBodyId: 'home',
          credits: n(0),
          baseCrew: 100,
          buildings: const [],
        ),
      ],
    ),
    milestones: const [],
  );
}

void main() {
  late Content c;
  late GameState s;
  late BodyState home;
  var nextId = 0;

  setUp(() {
    c = _content();
    s = newGameState(c, 1);
    home = s.body('home');
    nextId = 0;
  });

  BuildingState add(
    BodyState body,
    String defId, {
    int crew = 1,
    String? deposit,
    Map<UpgradeTrack, int>? levels,
  }) {
    final b = BuildingState(
      id: 't${nextId++}',
      defId: defId,
      depositResourceId: deposit,
      crew: crew,
      levels: levels,
    );
    body.buildings.add(b);
    return b;
  }

  BigNum stock(BodyState b, String id) => b.stock[id] ?? const BigNum.zero();

  Matcher near(num v) => predicate<BigNum>(
    (x) => (x.toDouble() - v).abs() < 1e-9,
    'a BigNum near $v',
  );

  test('extractor produces rate × dt', () {
    final d = add(home, 'drill', crew: 2, deposit: 'iron_ore');
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(3));
    expect(d.lastRunFraction, 1);
    expect(d.lastLimitReason, isNull);
  });

  test('factory limited by input', () {
    final sm = add(home, 'smelter');
    home.stock['iron_ore'] = n(2);
    stepProduction(s, c, 10);
    expect(sm.lastRunFraction, closeTo(0.5, 1e-12));
    expect(sm.lastLimitReason, 'input:iron_ore');
    expect(stock(home, 'steel'), near(0.5));
    expect(stock(home, 'iron_ore').isZero, isTrue);
  });

  test('two consumers share proportionally', () {
    final sm = add(home, 'smelter'); // wants 4 ore
    final ca = add(home, 'caster'); // wants 2 ore
    home.stock['iron_ore'] = n(3); // half the total demand of 6
    stepProduction(s, c, 10);
    expect(sm.lastRunFraction, closeTo(0.5, 1e-12));
    expect(ca.lastRunFraction, closeTo(0.5, 1e-12));
    expect(stock(home, 'steel'), near(0.5));
    expect(stock(home, 'ingot'), near(0.5));
    expect(stock(home, 'iron_ore').isZero, isTrue);
  });

  test('outputs made this step are not consumed in the same step', () {
    add(home, 'smelter');
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(3));
    expect(stock(home, 'steel').isZero, isTrue);
  });

  test('production may pass the storage cap within a tick', () {
    c = _content(baseStorageCap: 10);
    s = newGameState(c, 1);
    home = s.body('home');
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    home.stock['iron_ore'] = n(9);
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(12));
    expect(home.wastedThisStep, isEmpty);
  });

  test('clampStorage cuts stock to the cap and records waste', () {
    c = _content(baseStorageCap: 10);
    s = newGameState(c, 1);
    home = s.body('home');
    home.stock['iron_ore'] = n(12);
    home.stock['steel'] = n(4);
    clampStorage(s, c, const {});
    expect(stock(home, 'iron_ore'), near(10));
    expect(stock(home, 'steel'), near(4));
    expect(home.wastedThisStep, {'iron_ore': near(2)});
    expect(jsonEncode(home.toJson()), isNot(contains('wasted')));

    home.stock['iron_ore'] = n(13);
    clampStorage(s, c, const {});
    expect(home.wastedThisStep['iron_ore'], near(5));
  });

  test('stock already above the cap is kept, new output wasted', () {
    c = _content(baseStorageCap: 10);
    s = newGameState(c, 1);
    home = s.body('home');
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    home.stock['iron_ore'] = n(50);
    final kept = stockOverCap(s, c);
    expect(kept, {
      'home': {'iron_ore': near(50)},
    });
    stepProduction(s, c, 10);
    clampStorage(s, c, kept);
    expect(stock(home, 'iron_ore'), near(50));
    expect(home.wastedThisStep['iron_ore'], near(3));
  });

  test('stock above the cap that falls is clamped no lower than the cap', () {
    c = _content(baseStorageCap: 10);
    s = newGameState(c, 1);
    home = s.body('home');
    home.stock['iron_ore'] = n(50);
    final kept = stockOverCap(s, c);
    home.stock['iron_ore'] = n(5);
    clampStorage(s, c, kept);
    expect(stock(home, 'iron_ore'), near(5));
    expect(home.wastedThisStep, isEmpty);
  });

  test('storageCap adds warehouse bonus and capacity levels', () {
    expect(storageCap(s, c, home), near(1000));
    add(home, 'depot', crew: 0);
    expect(storageCap(s, c, home), near(2000));
    add(home, 'smelter', levels: {UpgradeTrack.capacity: 2});
    add(home, 'depot', crew: 0, levels: {UpgradeTrack.capacity: 1});
    // (1000 + 1000 × (1 + 1)) × (1 + 0.2 × 3)
    expect(storageCap(s, c, home), near(3000 * 1.6));
  });

  test('speed milestone', () {
    final r = shippedContent().rules;
    expect(speedMultiplier(r, 0), 1);
    expect(speedMultiplier(r, 24), closeTo(math.pow(1.1, 24), 1e-9));
    expect(speedMultiplier(r, 25), closeTo(math.pow(1.1, 25) * 2, 1e-9));
    expect(speedMultiplier(r, 50), closeTo(math.pow(1.1, 50) * 4, 1e-6));
  });

  test('speed level raises output', () {
    add(
      home,
      'drill',
      crew: 2,
      deposit: 'iron_ore',
      levels: {UpgradeTrack.speed: 2},
    );
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(3 * 1.21));
  });

  test('efficiency reduces inputs, floor respected', () {
    expect(efficiencyMultiplier(_rules, 0), 1);
    expect(efficiencyMultiplier(_rules, 2), closeTo(0.9025, 1e-12));
    expect(efficiencyMultiplier(_rules, 100), 0.25);

    add(home, 'smelter', levels: {UpgradeTrack.efficiency: 2});
    home.stock['iron_ore'] = n(100);
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(100 - 4 * 0.9025));
    expect(stock(home, 'steel'), near(1));

    home.buildings.clear();
    add(home, 'smelter', levels: {UpgradeTrack.efficiency: 100});
    home.stock['iron_ore'] = n(100);
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(99));
  });

  test('crew above base slots pushes output above 100%', () {
    add(
      home,
      'drill',
      crew: 3,
      deposit: 'iron_ore',
      levels: {UpgradeTrack.capacity: 1},
    );
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(4.5));
  });

  test('crew efficiency drops when habitats starve', () {
    s.faction('p').baseCrew = 2;
    final hab = add(home, 'habitat');
    add(home, 'works', crew: 7);
    home.stock['food'] = n(100);
    home.stock['water'] = n(100);

    stepProduction(s, c, 10);
    expect(hab.lastRunFraction, 1);
    expect(crewEfficiency(s, c, 'p'), 1.0);

    home.stock.remove('food');
    stepProduction(s, c, 10);
    expect(hab.lastRunFraction, 0);
    expect(hab.lastLimitReason, 'input:food');
    expect(crewEfficiency(s, c, 'p'), 0.25);
    // availableCrew shares the supported-crew rule: 2 supported, 8 assigned.
    expect(availableCrew(s, c, 'p'), -6);
  });

  test('crewTotals counts base, supported, assigned and free crew', () {
    s.faction('p').baseCrew = 5;
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    add(home, 'habitat', crew: 1).lastRunFraction = 0.5; // houses 5
    s
        .body('wild')
        .buildings
        .add(
          BuildingState(id: 'w1', defId: 'smelter', crew: 1),
        ); // unowned: not counted
    final t = crewTotals(s, c, 'p');
    expect((t.base, t.supported, t.assigned, t.free), (5, 10, 3, 7));
    expect(t.free, availableCrew(s, c, 'p'));
  });

  test('crew efficiency scales output', () {
    s.faction('p').baseCrew = 2;
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    add(home, 'works', crew: 2);
    expect(crewEfficiency(s, c, 'p'), 0.5);
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(1.5));
  });

  test('crew efficiency is 1 when nothing is assigned', () {
    s.faction('p').baseCrew = 0;
    expect(crewEfficiency(s, c, 'p'), 1.0);
  });

  test('zero crew produces nothing', () {
    final d = add(home, 'drill', crew: 0, deposit: 'iron_ore');
    final sm = add(home, 'smelter', crew: 0);
    final hab = add(home, 'habitat', crew: 0);
    home.stock['iron_ore'] = n(10);
    home.stock['food'] = n(10);
    home.stock['water'] = n(10);
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore'), near(10));
    expect(stock(home, 'steel').isZero, isTrue);
    expect(stock(home, 'food'), near(10));
    for (final b in [d, sm, hab]) {
      expect(b.lastRunFraction, 0);
      expect(b.lastLimitReason, 'noCrew');
    }
  });

  test('unowned bodies and warehouses produce nothing', () {
    final wild = s.body('wild');
    final d = add(wild, 'drill', crew: 2, deposit: 'iron_ore');
    final depot = add(home, 'depot', crew: 0);
    stepProduction(s, c, 10);
    expect(wild.stock, isEmpty);
    expect(d.lastRunFraction, 0);
    expect(depot.lastRunFraction, 0);
    expect(depot.lastLimitReason, isNull);
  });

  test('zero-slot habitat is not run and provides no housing', () {
    s.faction('p').baseCrew = 2;
    final pod = add(home, 'pod', crew: 0);
    add(home, 'works', crew: 4);
    home.stock['water'] = n(100);
    stepProduction(s, c, 10);
    stepProduction(s, c, 10);
    expect(stock(home, 'water'), near(100));
    expect(pod.lastRunFraction, 0);
    expect(pod.lastLimitReason, isNull);
    expect(crewEfficiency(s, c, 'p'), 0.5);
    expect(availableCrew(s, c, 'p'), -2);
  });

  test('no stock goes negative', () {
    for (var seed = 1; seed <= 4; seed++) {
      final rng = Rng(seed);
      final rc = _randomContent(rng);
      final rs = newGameState(rc, seed);
      final defIds = rc.buildings.keys.toList();
      final resIds = rc.resources.keys.toList();
      for (var step = 0; step < 500; step++) {
        for (var k = rng.nextInt(3); k > 0; k--) {
          applyCommand(rs, rc, _randomCommand(rng, rs, defIds, resIds));
        }
        stepProduction(rs, rc, 0.5 + rng.nextDouble() * 20);
        for (final body in rs.bodies) {
          for (final MapEntry(:key, :value) in body.stock.entries) {
            expect(
              value.isNegative,
              isFalse,
              reason: 'seed $seed step $step ${body.id} $key = $value',
            );
          }
        }
      }
      expect(
        rs.bodies.expand((b) => b.buildings).where((b) => b.crew > 0),
        isNotEmpty,
        reason: 'seed $seed should have exercised crewed buildings',
      );
    }
  });
}

/// A random small content set: four resources, extractors, factories with
/// one or two inputs, a habitat and a depot, on two bodies in one system.
Content _randomContent(Rng rng) {
  const res = ['r0', 'r1', 'r2', 'r3'];
  double qty() => 0.5 + rng.nextInt(8) / 2;
  final upgrades = {
    for (final t in UpgradeTrack.values)
      t: UpgradeCostDef(baseCredits: n(1 + rng.nextInt(20)), growth: 1.1),
  };
  final buildings = <BuildingDef>[
    BuildingDef(
      id: 'ex',
      name: 'ex',
      kind: BuildingKind.extractor,
      cycleSeconds: 1.0 + rng.nextInt(10),
      extracts: ['r0'],
      outputs: {'r0': qty()},
      crewSlots: 1 + rng.nextInt(3),
      buildCost: {'credits': n(10)},
      upgrades: upgrades,
    ),
    for (var i = 0; i < 4; i++)
      BuildingDef(
        id: 'f$i',
        name: 'f$i',
        kind: BuildingKind.factory,
        cycleSeconds: 1.0 + rng.nextInt(10),
        inputs: {
          res[rng.nextInt(3)]: qty(),
          if (rng.nextInt(2) == 0) res[rng.nextInt(4)]: qty(),
        },
        outputs: {res[1 + rng.nextInt(3)]: qty()},
        crewSlots: 1 + rng.nextInt(3),
        buildCost: {'credits': n(10)},
        upgrades: upgrades,
      ),
    BuildingDef(
      id: 'hab',
      name: 'hab',
      kind: BuildingKind.habitat,
      cycleSeconds: 5,
      inputs: {'r2': qty(), 'r3': qty()},
      crewSlots: 1,
      housing: 5 + rng.nextInt(10),
      buildCost: {'credits': n(10)},
      upgrades: upgrades,
    ),
    BuildingDef(
      id: 'depot',
      name: 'depot',
      kind: BuildingKind.warehouse,
      cycleSeconds: 1,
      crewSlots: 0,
      storageBonus: 0.5,
      buildCost: {'credits': n(10)},
      upgrades: {UpgradeTrack.capacity: upgrades[UpgradeTrack.capacity]!},
    ),
  ];
  return Content(
    rules: _rulesWith(baseStorageCap: 20.0 + rng.nextInt(80)),
    resources: {for (final id in res) id: _res(id)},
    buildings: {for (final b in buildings) b.id: b},
    bodyTypes: {
      'rock': BodyTypeDef(
        id: 'rock',
        name: 'rock',
        depositPool: ['r0'],
        buildSlots: 8,
      ),
    },
    galaxy: GalaxyDef(
      systems: [
        SystemDef(
          id: 'sys',
          name: 'sys',
          bodies: [
            for (final id in ['a', 'b'])
              BodyDef(
                id: id,
                name: id,
                typeId: 'rock',
                orbit: 1,
                deposits: [
                  DepositDef(
                    resourceId: 'r0',
                    richness: 0.5 + rng.nextDouble(),
                  ),
                ],
              ),
          ],
        ),
      ],
      factions: [
        StartingFactionDef(
          id: 'p',
          name: 'p',
          isPlayer: true,
          homeBodyId: 'a',
          credits: n(1e6),
          baseCrew: 6,
          buildings: const [],
          stock: {for (final id in res) id: n(rng.nextInt(30))},
        ),
      ],
    ),
    milestones: const [],
  );
}

/// A random command for faction `p`; many will fail validation, which is fine.
Command _randomCommand(
  Rng rng,
  GameState s,
  List<String> defIds,
  List<String> resIds,
) {
  T pick<T>(List<T> xs) => xs[rng.nextInt(xs.length)];
  final bodyId = pick(s.bodies).id;
  final buildings = [for (final b in s.bodies) ...b.buildings];
  final buildingId = buildings.isEmpty ? 'none' : pick(buildings).id;
  return switch (rng.nextInt(7)) {
    0 || 1 => BuildCommand('p', bodyId, pick(defIds), depositResourceId: 'r0'),
    2 || 3 => AssignCrewCommand('p', buildingId, rng.nextInt(5)),
    4 => UpgradeCommand('p', buildingId, pick(UpgradeTrack.values)),
    5 => SellCommand('p', bodyId, pick(resIds), n(1 + rng.nextInt(20))),
    _ =>
      rng.nextInt(4) == 0
          ? DemolishCommand('p', buildingId)
          : ClaimBodyCommand('p', 'b', 'a'),
  };
}
