import 'package:game_core/game_core.dart';

BigNum n(num v) => BigNum.from(v);

/// Inline content: system `sys` with bodies `a` (orbit 1), `b` (orbit 2),
/// `c` (orbit 1); faction `p` owns `a`; `ore` sells at 10 with depth 100;
/// base travel 60 s, one ship carries 2/s, storage cap 1000.
Content economyContent() => Content(
  rules: const RulesDef(
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
    marketRecoverySeconds: 1800,
    claimBaseCredits: BigNum.zero(),
    claimGrowth: 1,
    slotBaseCredits: BigNum.zero(),
    slotGrowth: 1,
    outpostKitResource: 'kit',
    shipCapacityPerSecond: 2,
    cargoShipResource: 'ship',
    baseTravelSeconds: 60,
  ),
  resources: {
    'ore': ResourceDef(
      id: 'ore',
      name: 'Ore',
      tier: 0,
      basePrice: n(10),
      marketDepth: 100,
    ),
  },
  buildings: const {},
  bodyTypes: {
    'rock': BodyTypeDef(
      id: 'rock',
      name: 'Rock',
      depositPool: ['ore'],
      buildSlots: 10,
    ),
  },
  galaxy: GalaxyDef(
    systems: [
      SystemDef(
        id: 'sys',
        name: 'Sys',
        bodies: [
          for (final (id, orbit) in [('a', 1), ('b', 2), ('c', 1)])
            BodyDef(
              id: id,
              name: id,
              typeId: 'rock',
              orbit: orbit,
              deposits: const [],
            ),
        ],
      ),
    ],
    factions: [
      StartingFactionDef(
        id: 'p',
        name: 'P',
        isPlayer: true,
        homeBodyId: 'a',
        credits: n(0),
        baseCrew: 10,
        buildings: const [],
      ),
    ],
  ),
  milestones: const [],
);
