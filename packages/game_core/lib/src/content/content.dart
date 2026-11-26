import '../num/big_num.dart';
import 'content_loader.dart';

/// A tradeable item of any tier, from raw ore to megaproject parts.
final class ResourceDef {
  /// Creates a resource definition.
  const ResourceDef({
    required this.id,
    required this.name,
    required this.tier,
    required this.basePrice,
    this.marketDepth = defaultMarketDepth,
  });

  /// Market depth used when a resource does not set one.
  static const double defaultMarketDepth = 10000;

  /// The highest tier; megaproject parts need no consumer or price.
  static const int megaprojectTier = 4;

  /// Unique id, used as the key in recipes and stock maps.
  final String id;

  /// Display name.
  final String name;

  /// Product tier: 0 raw, 1 refined, 2 component, 3 advanced, 4 megaproject.
  final int tier;

  /// Neutral market price per unit at full saturation; zero means unsellable.
  final BigNum basePrice;

  /// Units that must be sold to push the market price down by the full
  /// saturation range; larger is a deeper, more forgiving market.
  final double marketDepth;
}

/// What a building does each cycle.
enum BuildingKind {
  /// Mines a deposit on its body; has no inputs.
  extractor,

  /// Turns inputs into outputs.
  factory,

  /// Consumes life support and provides crew housing.
  habitat,

  /// Raises the body's per-resource storage cap; runs no recipe.
  warehouse,
}

/// A separately levelled upgrade path on a building.
enum UpgradeTrack {
  /// More cycles per second.
  speed,

  /// Fewer inputs per cycle.
  efficiency,

  /// More crew slots and body storage; on habitats, more housing instead
  /// of crew slots (see [RulesDef.capacityHousingPerLevel]).
  capacity,
}

/// Cost curve of one upgrade track: `baseCredits × growth^level` credits.
final class UpgradeCostDef {
  /// Creates an upgrade cost curve.
  const UpgradeCostDef({required this.baseCredits, required this.growth});

  /// Credits for the first level.
  final BigNum baseCredits;

  /// Cost multiplier per level already bought; at least 1.
  final double growth;
}

/// A building type and the single recipe it runs.
final class BuildingDef {
  /// Creates a building definition; the collections are copied unmodifiable.
  BuildingDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.cycleSeconds,
    Map<String, double> inputs = const {},
    Map<String, double> outputs = const {},
    List<String> extracts = const [],
    required this.crewSlots,
    this.housing = 0,
    this.storageBonus = 0,
    required Map<String, BigNum> buildCost,
    Map<UpgradeTrack, UpgradeCostDef> upgrades = const {},
  }) : inputs = Map.unmodifiable(inputs),
       outputs = Map.unmodifiable(outputs),
       extracts = List.unmodifiable(extracts),
       buildCost = Map.unmodifiable(buildCost),
       upgrades = Map.unmodifiable(upgrades);

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// What the building does.
  final BuildingKind kind;

  /// Game seconds per recipe cycle at speed level 0 and full crew.
  final double cycleSeconds;

  /// Resource id to units consumed per cycle, in content order.
  final Map<String, double> inputs;

  /// Resource id to units produced per cycle, in content order.
  ///
  /// For an extractor each key is a resource it [extracts]; only the entry
  /// for the deposit it sits on applies, multiplied by that deposit's richness.
  final Map<String, double> outputs;

  /// Extractor only: resource ids this building may mine.
  final List<String> extracts;

  /// Crew slots at capacity level 0; zero for warehouses, and for
  /// habitats that run without crew.
  final int crewSlots;

  /// Habitat only: crew housed when the habitat runs at full rate, before
  /// capacity upgrades ([RulesDef.capacityHousingPerLevel]).
  final int housing;

  /// Warehouse only: fraction of the base storage cap added per resource.
  final double storageBonus;

  /// Cost to build: the key `credits` or a resource id, to an amount.
  final Map<String, BigNum> buildCost;

  /// Available upgrade tracks and their cost curves, in content order.
  final Map<UpgradeTrack, UpgradeCostDef> upgrades;
}

/// A kind of planetary body and what can be found on it.
final class BodyTypeDef {
  /// Creates a body type; [depositPool] is copied unmodifiable.
  BodyTypeDef({
    required this.id,
    required this.name,
    required List<String> depositPool,
    required this.buildSlots,
  }) : depositPool = List.unmodifiable(depositPool);

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Resource ids a body of this type may have deposits of.
  final List<String> depositPool;

  /// Buildings a body of this type can hold.
  final int buildSlots;
}

/// Global tuning numbers.
final class RulesDef {
  /// Creates the rules.
  const RulesDef({
    required this.speedPerLevel,
    required this.speedMilestoneEvery,
    required this.speedMilestoneMult,
    required this.efficiencyPerLevel,
    required this.efficiencyFloor,
    required this.capacityCrewPerLevel,
    required this.capacityStoragePerLevel,
    this.capacityHousingPerLevel = defaultCapacityHousingPerLevel,
    required this.baseStorageCap,
    required this.offlineCapSeconds,
    required this.marketFloor,
    required this.marketRecoverySeconds,
    required this.claimBaseCredits,
    required this.claimGrowth,
    required this.outpostKitResource,
    required this.shipCapacityPerSecond,
    required this.cargoShipResource,
    required this.baseTravelSeconds,
  });

  /// Speed multiplier per speed level.
  final double speedPerLevel;

  /// Every this many speed levels, an extra [speedMilestoneMult] applies.
  final int speedMilestoneEvery;

  /// Extra speed multiplier per [speedMilestoneEvery] levels.
  final double speedMilestoneMult;

  /// Input multiplier per efficiency level, in `(0, 1]`.
  final double efficiencyPerLevel;

  /// Lowest input multiplier efficiency can reach, in `(0, 1]`.
  final double efficiencyFloor;

  /// Crew slots added per capacity level.
  final int capacityCrewPerLevel;

  /// Body storage fraction added per capacity level.
  final double capacityStoragePerLevel;

  /// [capacityHousingPerLevel] when the rules do not set it.
  static const double defaultCapacityHousingPerLevel = 0.25;

  /// Habitat housing fraction added per capacity level: a habitat houses
  /// `housing × (1 + capacityHousingPerLevel × capacity level)` at full
  /// rate. On habitats the capacity track adds housing, not crew slots
  /// (a habitat with no base slots never gets any).
  final double capacityHousingPerLevel;

  /// Units of each resource a body stores before warehouses and upgrades.
  final double baseStorageCap;

  /// Longest offline catch-up in seconds before upgrades.
  final double offlineCapSeconds;

  /// Lowest market saturation, in `[0, 1]`.
  final double marketFloor;

  /// Seconds for market saturation to recover from 0 to 1.
  final double marketRecoverySeconds;

  /// Credits for a faction's first extra body.
  final BigNum claimBaseCredits;

  /// Claim credit multiplier per extra body already owned.
  final double claimGrowth;

  /// Resource id spent as outpost kits on claims after the first.
  final String outpostKitResource;

  /// Units per second one cargo ship adds to a route's capacity.
  final double shipCapacityPerSecond;

  /// Resource id of cargo ships assigned to routes.
  final String cargoShipResource;

  /// Travel seconds between bodies at the same orbit in one system.
  final double baseTravelSeconds;
}

/// A deposit of one raw resource on a body.
final class DepositDef {
  /// Creates a deposit.
  const DepositDef({required this.resourceId, required this.richness});

  /// Resource mined from it.
  final String resourceId;

  /// Multiplier on an extractor's output; above zero.
  final double richness;
}

/// A planet, moon, or belt in the starting galaxy.
final class BodyDef {
  /// Creates a body; [deposits] is copied unmodifiable.
  BodyDef({
    required this.id,
    required this.name,
    required this.typeId,
    required this.orbit,
    required List<DepositDef> deposits,
  }) : deposits = List.unmodifiable(deposits);

  /// Unique id across the galaxy.
  final String id;

  /// Display name.
  final String name;

  /// Id of its [BodyTypeDef].
  final String typeId;

  /// Orbit index within its system; drives travel time.
  final int orbit;

  /// Its deposits, 1 to 4, each from the type's pool.
  final List<DepositDef> deposits;
}

/// A star system.
final class SystemDef {
  /// Creates a system; [bodies] is copied unmodifiable.
  SystemDef({
    required this.id,
    required this.name,
    required List<BodyDef> bodies,
  }) : bodies = List.unmodifiable(bodies);

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Its bodies in content order.
  final List<BodyDef> bodies;
}

/// A building a faction starts with on its home body.
final class StartingBuildingDef {
  /// Creates a starting building.
  const StartingBuildingDef({
    required this.defId,
    this.depositResourceId,
    required this.crew,
  });

  /// Id of its [BuildingDef].
  final String defId;

  /// Extractor only: the home-body deposit it mines.
  final String? depositResourceId;

  /// Crew assigned at start.
  final int crew;
}

/// A faction's setup at the start of a new game.
final class StartingFactionDef {
  /// Creates a starting faction; the collections are copied unmodifiable.
  StartingFactionDef({
    required this.id,
    required this.name,
    required this.isPlayer,
    required this.homeBodyId,
    required this.credits,
    required this.baseCrew,
    required List<StartingBuildingDef> buildings,
    Map<String, BigNum> stock = const {},
  }) : buildings = List.unmodifiable(buildings),
       stock = Map.unmodifiable(stock);

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Whether a human plays this faction; exactly one does.
  final bool isPlayer;

  /// The only body it owns at start.
  final String homeBodyId;

  /// Starting credits.
  final BigNum credits;

  /// Crew available without habitats.
  final int baseCrew;

  /// Buildings on the home body at start.
  final List<StartingBuildingDef> buildings;

  /// Resource id to units in the home body's stock at start.
  final Map<String, BigNum> stock;
}

/// The starting galaxy: its systems and who lives where.
final class GalaxyDef {
  /// Creates a galaxy; the lists are copied unmodifiable.
  GalaxyDef({
    required List<SystemDef> systems,
    required List<StartingFactionDef> factions,
  }) : systems = List.unmodifiable(systems),
       factions = List.unmodifiable(factions);

  /// Systems in content order.
  final List<SystemDef> systems;

  /// Factions in content order.
  final List<StartingFactionDef> factions;
}

/// What a faction must reach to earn a milestone.
sealed class MilestoneCondition {
  const MilestoneCondition();
}

/// Holds at least [amount] of [resourceId], summed over its bodies.
final class StockCondition extends MilestoneCondition {
  /// Creates a stock condition.
  const StockCondition({required this.resourceId, required this.amount});

  /// Resource counted.
  final String resourceId;

  /// Units needed.
  final BigNum amount;
}

/// Holds at least [amount] credits.
final class CreditsCondition extends MilestoneCondition {
  /// Creates a credits condition.
  const CreditsCondition({required this.amount});

  /// Credits needed.
  final BigNum amount;
}

/// Owns at least [count] bodies.
final class BodiesOwnedCondition extends MilestoneCondition {
  /// Creates a bodies-owned condition.
  const BodiesOwnedCondition({required this.count});

  /// Bodies needed.
  final int count;
}

/// Owns at least [count] buildings of [defId].
final class BuildingCountCondition extends MilestoneCondition {
  /// Creates a building-count condition.
  const BuildingCountCondition({required this.defId, required this.count});

  /// Building type counted.
  final String defId;

  /// Buildings needed.
  final int count;
}

/// A named progress marker shown in reports.
final class MilestoneDef {
  /// Creates a milestone.
  const MilestoneDef({
    required this.id,
    required this.name,
    required this.condition,
  });

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// When it is reached.
  final MilestoneCondition condition;
}

/// All game content, validated.
final class Content {
  /// Creates content without validation; prefer [fromBundle].
  ///
  /// The maps and list are copied unmodifiable, keeping their order.
  Content({
    required this.rules,
    required Map<String, ResourceDef> resources,
    required Map<String, BuildingDef> buildings,
    required Map<String, BodyTypeDef> bodyTypes,
    required this.galaxy,
    required List<MilestoneDef> milestones,
  }) : resources = Map.unmodifiable(resources),
       buildings = Map.unmodifiable(buildings),
       bodyTypes = Map.unmodifiable(bodyTypes),
       milestones = List.unmodifiable(milestones);

  /// Global tuning numbers.
  final RulesDef rules;

  /// Resources by id, in content order.
  final Map<String, ResourceDef> resources;

  /// Buildings by id, in content order.
  final Map<String, BuildingDef> buildings;

  /// Body types by id, in content order.
  final Map<String, BodyTypeDef> bodyTypes;

  /// The starting galaxy.
  final GalaxyDef galaxy;

  /// Milestones in content order.
  final List<MilestoneDef> milestones;

  /// Parses and validates decoded content JSON without throwing.
  ///
  /// [bundle] maps each content file stem (`rules`, `resources`,
  /// `buildings`, `body_types`, `galaxy`, `milestones`) to its decoded JSON.
  static ContentResult fromBundle(Map<String, Object?> bundle) =>
      loadContentBundle(bundle);
}

/// Outcome of [Content.fromBundle].
sealed class ContentResult {
  const ContentResult();
}

/// The bundle was valid.
final class ContentOk extends ContentResult {
  /// Wraps loaded content.
  const ContentOk(this.content);

  /// The loaded content.
  final Content content;
}

/// The bundle had problems; nothing was loaded.
final class ContentInvalid extends ContentResult {
  /// Wraps the problems found.
  ContentInvalid(List<String> errors) : errors = List.unmodifiable(errors);

  /// Problems as `"<path>: <message>"`, in the order found.
  final List<String> errors;
}
