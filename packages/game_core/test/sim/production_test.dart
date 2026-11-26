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
  slotBaseCredits: BigNum.zero(),
  slotGrowth: 1,
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
  slotBaseCredits: _rules.slotBaseCredits,
  slotGrowth: _rules.slotGrowth,
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
    // A habitat that needs no crew.
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

  test("output adds to the owner's lifetime produced, waste or not", () {
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    add(home, 'smelter');
    stepProduction(s, c, 10);
    final made = s.faction('p').lifetimeProduced;
    // The drill made 3 ore; the smelter used it all for 0.75 steel.
    expect(made.keys, ['iron_ore', 'steel']);
    expect(made['iron_ore'], near(3));
    expect(made['steel'], near(0.75));
    home.stock.clear();
    stepProduction(s, c, 10);
    expect(made['iron_ore'], near(6));
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

  test('a chain on one body runs within one step, in recipe order', () {
    // Listed consumer first: the drill still runs first, and the smelter
    // uses its 3 ore of the 4 it wants in the same step.
    final sm = add(home, 'smelter');
    add(home, 'drill', crew: 2, deposit: 'iron_ore');
    stepProduction(s, c, 10);
    expect(stock(home, 'iron_ore').isZero, isTrue);
    expect(stock(home, 'steel'), near(0.75));
    expect(sm.lastRunFraction, closeTo(0.75, 1e-12));
    expect(sm.lastLimitReason, 'input:iron_ore');
  });

  test('consumers at one depth share the same step\'s output', () {
    final sm = add(home, 'smelter'); // wants 4 ore
    final ca = add(home, 'caster'); // wants 2 ore
    add(home, 'drill', crew: 2, deposit: 'iron_ore'); // makes 3
    stepProduction(s, c, 10);
    expect(sm.lastRunFraction, closeTo(0.5, 1e-12));
    expect(ca.lastRunFraction, closeTo(0.5, 1e-12));
    expect(stock(home, 'iron_ore').isZero, isTrue);
  });

  test('recipe depth: extractors 0, then each consumer past its inputs', () {
    expect(recipeDepth(c), {
      'drill': 0,
      'smelter': 1,
      'caster': 1,
      'works': 1,
      'habitat': 1,
      'pod': 1,
      'depot': 0,
    });
    expect(recipeDepth(c), same(recipeDepth(c)));
  });

  test('recipe depth breaks a cycle by list order', () {
    BuildingDef f(String id, String from, String to) => BuildingDef(
      id: id,
      name: id,
      kind: BuildingKind.factory,
      cycleSeconds: 1,
      inputs: {from: 1},
      outputs: {to: 1},
      crewSlots: 1,
      buildCost: const {},
    );
    final cyc = Content(
      rules: c.rules,
      resources: {
        for (final id in ['r1', 'r2', 'r3']) id: _res(id),
      },
      buildings: {
        for (final b in [
          f('x', 'r1', 'r2'),
          f('y', 'r2', 'r1'),
          f('z', 'r2', 'r3'),
        ])
          b.id: b,
      },
      bodyTypes: c.bodyTypes,
      galaxy: c.galaxy,
      milestones: const [],
    );
    // x is listed first, so its input from y is the edge that is dropped:
    // y runs before x, and z after x.
    expect(recipeDepth(cyc), {'x': 2, 'y': 1, 'z': 3});
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
    // availableCrew shares the supported-crew rule: 2 supported, 8 assigned,
    // so none is free and 6 are assigned beyond what is supported.
    expect(availableCrew(s, c, 'p'), 0);
    expect(crewTotals(s, c, 'p').free, 0);
    expect(crewTotals(s, c, 'p').overAssigned, 6);
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
    expect(t.overAssigned, 0);
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

  test('crew below the base slots is understaffed, even at full supply', () {
    final works = add(home, 'works', crew: 2);
    final full = add(home, 'works', crew: 7);
    stepProduction(s, c, 10);
    expect(works.lastRunFraction, 1);
    expect(works.lastLimitReason, 'understaffed');
    expect(full.lastLimitReason, isNull);
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

  test('a habitat with no crew slots runs on its inputs alone', () {
    s.faction('p').baseCrew = 2;
    final pod = add(home, 'pod', crew: 0);
    add(home, 'works', crew: 4);
    home.stock['water'] = n(100);
    // Crew efficiency is 0.5 before the pod houses anyone; the pod runs at
    // full rate all the same.
    expect(crewEfficiency(s, c, 'p'), 0.5);
    stepProduction(s, c, 10);
    expect(stock(home, 'water'), near(99));
    expect(pod.lastRunFraction, 1);
    expect(pod.lastLimitReason, isNull);
    expect(crewEfficiency(s, c, 'p'), 1.0);
    expect(availableCrew(s, c, 'p'), 8);

    home.stock['water'] = n(0.25);
    stepProduction(s, c, 10);
    expect(pod.lastRunFraction, closeTo(0.25, 1e-12));
    expect(pod.lastLimitReason, 'input:water');
    expect(crewTotals(s, c, 'p').supported, 2 + 2);
  });

  test('habitat capacity levels add a quarter of housing each', () {
    s.faction('p').baseCrew = 0;
    add(
      home,
      'pod',
      crew: 0,
      levels: {UpgradeTrack.capacity: 2},
    ).lastRunFraction = 1;
    add(
      home,
      'habitat',
      crew: 1,
      levels: {UpgradeTrack.capacity: 1},
    ).lastRunFraction = 0.5;
    // 10 × 1.5 + 10 × 1.25 × 0.5
    expect(crewTotals(s, c, 'p').supported, 21);
  });

  test('habitat capacity raises life support as much as housing', () {
    s.faction('p').baseCrew = 0;
    final pod = add(home, 'pod', crew: 0, levels: {UpgradeTrack.capacity: 2});
    expect(
      fullRateFlow(c, home, pod, 10, 1).inputs['water'],
      near(1.5),
      reason: '1 water a cycle × (1 + 0.25 × 2)',
    );
    home.stock['water'] = n(100);
    stepProduction(s, c, 10);
    expect(stock(home, 'water'), near(98.5));
    expect(pod.lastRunFraction, 1);
    expect(crewTotals(s, c, 'p').supported, 15);

    // Half of the raised need: half the raised housing.
    home.stock['water'] = n(0.75);
    stepProduction(s, c, 10);
    expect(pod.lastRunFraction, closeTo(0.5, 1e-12));
    expect(crewTotals(s, c, 'p').supported, 7);
  });

  group('habitats get first claim on their inputs', () {
    final shipped = shippedContent();
    late GameState gs;
    late BodyState kora;
    BuildingState put(String defId, {int crew = 1}) {
      final b = BuildingState(
        id: 'h${kora.buildings.length}',
        defId: defId,
        crew: crew,
      );
      kora.buildings.add(b);
      return b;
    }

    setUp(() {
      gs = newGameState(shipped, 1)..faction('player').baseCrew = 50;
      kora = gs.body('kora')..buildings.clear();
    });

    test('short of water and oxygen, the habitat is served before the '
        'electrolyzer and fuel refinery that also use them', () {
      // In 60 s the habitat needs 6 each of food, water and oxygen; the
      // electrolyzer wants 20 water and the fuel refinery 10 oxygen.
      final hab = put('habitat', crew: 0);
      final electrolyzer = put('electrolyzer');
      final refinery = put('fuel_refinery');
      kora.stock
        ..clear()
        ..['water'] = n(4)
        ..['oxygen'] = n(3)
        ..['food'] = n(100)
        ..['hydrogen'] = n(100);
      stepProduction(gs, shipped, 60);
      // Oxygen limits it: 3 of 6.
      expect(hab.lastRunFraction, closeTo(0.5, 1e-12));
      expect(hab.lastLimitReason, 'input:oxygen');
      // What the habitat claimed was not there for the others.
      expect(electrolyzer.lastRunFraction, 0);
      expect(electrolyzer.lastLimitReason, 'input:water');
      expect(refinery.lastRunFraction, 0);
      expect(stock(kora, 'oxygen').isZero, isTrue);
      expect(stock(kora, 'water'), near(1));
    });

    test('a habitat with capacity levels claims its raised need first', () {
      // Capacity 2: 1.5 × the 6 each a level-0 habitat needs in 60 s.
      final hab = put('habitat', crew: 0)..levels[UpgradeTrack.capacity] = 2;
      final electrolyzer = put('electrolyzer');
      kora.stock
        ..clear()
        ..['water'] = n(9)
        ..['oxygen'] = n(4.5)
        ..['food'] = n(100);
      stepProduction(gs, shipped, 60);
      expect(hab.lastRunFraction, closeTo(0.5, 1e-12));
      expect(hab.lastLimitReason, 'input:oxygen');
      // The habitat's full 9 water was held back from the electrolyzer.
      expect(electrolyzer.lastRunFraction, 0);
      expect(stock(kora, 'water'), near(4.5));
    });

    test('the habitat still uses what the body makes in the same step', () {
      // An ice melter makes 30 water in 60 s from stock; the habitat needs 6.
      final hab = put('habitat', crew: 0);
      put('ice_melter');
      kora.stock
        ..clear()
        ..['water_ice'] = n(100)
        ..['oxygen'] = n(100)
        ..['food'] = n(100);
      stepProduction(gs, shipped, 60);
      expect(hab.lastRunFraction, 1);
      expect(stock(kora, 'water'), near(24));
    });
  });

  test('the furnace and electrolyzer cycle steps without going negative, '
      'the same every time', () {
    // The hydrogen furnace makes water from hydrogen; the electrolyzer
    // makes hydrogen from water. Recipe depth visits the furnace first
    // (content order), reaches the electrolyzer through hydrogen, and
    // drops the electrolyzer's edge back to the furnace's water: so the
    // electrolyzer (depth 2) runs before the furnace (depth 3), and the
    // furnace's water reaches it in the next step.
    final shipped = shippedContent();
    final depth = recipeDepth(shipped);
    expect(depth['electrolyzer'], 2);
    expect(depth['hydrogen_furnace'], 3);

    String run() {
      final gs = newGameState(shipped, 1)..faction('player').baseCrew = 50;
      final kora = gs.body('kora')
        ..buildings.clear()
        ..stock.clear()
        ..stock['iron_ore'] = n(500)
        ..stock['hydrogen'] = n(7)
        ..stock['water'] = n(3);
      kora.buildings.addAll([
        BuildingState(id: 'f', defId: 'hydrogen_furnace', crew: 2),
        BuildingState(id: 'e', defId: 'electrolyzer', crew: 3),
      ]);
      final rng = Rng(9);
      for (var step = 0; step < 300; step++) {
        stepProduction(gs, shipped, 0.5 + rng.nextDouble() * 30);
        for (final MapEntry(:key, :value) in kora.stock.entries) {
          expect(value.isNegative, isFalse, reason: 'step $step $key $value');
        }
      }
      // The cycle ran: the electrolyzer used the furnace's water.
      expect(gs.faction('player').lifetimeProduced['oxygen'], isNotNull);
      return jsonEncode(gs.toJson());
    }

    expect(run(), run());
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
