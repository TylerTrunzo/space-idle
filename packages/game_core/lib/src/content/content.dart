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
    this.marketFloor,
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

  /// How deep the market is: each unit sold cuts the price by
  /// `1 / marketDepth` of itself, so `marketDepth` units sold at once cut
  /// it to 1/e, and steady selling of `marketDepth /
  /// RulesDef.marketRecoverySeconds` units a second holds it at half
  /// price. Larger is a deeper, more forgiving market.
  final double marketDepth;

  /// Lowest saturation its market falls to, in `[0, 1]`; null uses
  /// [RulesDef.marketFloor]. A low floor makes piling up this resource pay
  /// ever less.
  final double? marketFloor;
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

  /// More crew slots and body storage; on habitats, more housing and the
  /// life support to match instead of crew slots (see
  /// [RulesDef.capacityHousingPerLevel]). On a building with a speed track
  /// it shares one price counter with speed (see `upgradeCost`).
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
    this.claimKitsBase = defaultClaimKitsBase,
    this.claimKitsPerOwned = defaultClaimKitsPerOwned,
    required this.slotBaseCredits,
    required this.slotGrowth,
    required this.outpostKitResource,
    required this.shipCapacityPerSecond,
    required this.cargoShipResource,
    required this.baseTravelSeconds,
    this.shipmentMergeSeconds = defaultShipmentMergeSeconds,
    this.claimSecondsBase = defaultClaimSecondsBase,
    this.claimSecondsPerOwned = defaultClaimSecondsPerOwned,
    this.expandSlotsSeconds = defaultExpandSlotsSeconds,
    this.contractRefillSeconds = defaultContractRefillSeconds,
    this.surveyDrones = defaultSurveyDrones,
    BigNum? surveyCredits,
    this.surveySeconds = defaultSurveySeconds,
    this.surveyDroneResource = defaultSurveyDroneResource,
  }) : _surveyCredits = surveyCredits;

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
  /// rate, and uses its inputs scaled by the same factor. On habitats the
  /// capacity track adds housing, not crew slots (a habitat with no base
  /// slots never gets any).
  final double capacityHousingPerLevel;

  /// Units of each resource a body stores before warehouses and upgrades.
  final double baseStorageCap;

  /// Longest offline catch-up in seconds before megaproject bonuses; see
  /// `offlineCapFor`.
  final double offlineCapSeconds;

  /// Longest offline catch-up in seconds whatever the bonuses: 48 hours.
  static const double maxOfflineCapSeconds = 172800;

  /// Lowest market saturation, in `[0, 1]`.
  final double marketFloor;

  /// Time constant of market recovery: an unsold resource's gap to full
  /// price shrinks by a factor e every this many seconds.
  final double marketRecoverySeconds;

  /// Credits for a faction's first extra body.
  final BigNum claimBaseCredits;

  /// Claim credit multiplier per extra body already owned.
  final double claimGrowth;

  /// [claimKitsBase] when the rules do not set it.
  static const int defaultClaimKitsBase = 5;

  /// [claimKitsPerOwned] when the rules do not set it.
  static const int defaultClaimKitsPerOwned = 5;

  /// Outpost kits every claim after the first costs, before
  /// [claimKitsPerOwned]: with `n` bodies owned or being claimed, a claim
  /// costs `claimKitsBase + claimKitsPerOwned × (n − 1)` kits; see
  /// `claimCost`.
  final int claimKitsBase;

  /// Outpost kits each body owned or being claimed beyond the home body
  /// adds to a claim.
  final int claimKitsPerOwned;

  /// Credits for a body's first extra build slot.
  final BigNum slotBaseCredits;

  /// Extra-slot credit multiplier per extra slot the body already has;
  /// above 1, so each slot costs more than the last.
  final double slotGrowth;

  /// Resource id spent as outpost kits on claims after the first.
  final String outpostKitResource;

  /// Units per second one cargo ship adds to a route's capacity.
  final double shipCapacityPerSecond;

  /// Resource id of cargo ships assigned to routes.
  final String cargoShipResource;

  /// Travel seconds between bodies at the same orbit in one system.
  final double baseTravelSeconds;

  /// [shipmentMergeSeconds] when the rules do not set it.
  static const double defaultShipmentMergeSeconds = 10;

  /// Game seconds within which a route's sends join its newest shipment
  /// instead of starting a new one; at least zero.
  ///
  /// Ticking once a second would otherwise put one shipment per route per
  /// second in flight; merged, a route has about one per this many seconds
  /// of travel. Merged cargo keeps the shipment's arrival time, so it lands
  /// up to this many seconds early. Auto-sell keeps this long's local
  /// demand back at least (see `stepMarket`), so a body fed in lots this
  /// far apart does not sell what it needs before the next lot lands.
  final double shipmentMergeSeconds;

  /// Shortest a timed project (a claim or a slot expansion) takes, in
  /// seconds: 10 minutes.
  static const double minProjectSeconds = 600;

  /// Longest a timed project takes, in seconds: 6 hours.
  static const double maxProjectSeconds = 21600;

  /// [claimSecondsBase] when the rules do not set it.
  static const double defaultClaimSecondsBase = 1800;

  /// [claimSecondsPerOwned] when the rules do not set it.
  static const double defaultClaimSecondsPerOwned = 1800;

  /// [expandSlotsSeconds] when the rules do not set it.
  static const double defaultExpandSlotsSeconds = 3600;

  /// Seconds a faction's first claim takes, while it owns only its home.
  ///
  /// With `n` bodies owned or being claimed, a claim takes
  /// `claimSecondsBase + claimSecondsPerOwned × (n − 1)` seconds, clamped
  /// to [[minProjectSeconds], [maxProjectSeconds]]; see `claimSeconds`.
  final double claimSecondsBase;

  /// Seconds each further body owned or being claimed adds to a claim.
  final double claimSecondsPerOwned;

  /// Seconds an extra build slot takes, in
  /// [[minProjectSeconds], [maxProjectSeconds]].
  final double expandSlotsSeconds;

  /// Contracts a faction's board holds at most.
  static const int contractSlots = 3;

  /// [contractRefillSeconds] when the rules do not set it: 4 hours.
  static const double defaultContractRefillSeconds = 14400;

  /// Seconds after which an emptied contract slot is filled again; above
  /// zero. Refills bank one after another (see `freeContractSlot`), so a
  /// board emptied while the player is away is full again when they return.
  final double contractRefillSeconds;

  /// [surveyDrones] when the rules do not set it.
  static const int defaultSurveyDrones = 3;

  /// [surveySeconds] when the rules do not set it: 3 hours.
  static const double defaultSurveySeconds = 10800;

  /// [surveyDroneResource] when the rules do not set it.
  static const String defaultSurveyDroneResource = 'survey_drone';

  /// [surveyCredits] when the rules do not set it.
  static final BigNum defaultSurveyCredits = BigNum.parse('2e4');

  /// Survey drones a survey uses up, from the stock of the body that pays.
  final int surveyDrones;

  final BigNum? _surveyCredits;

  /// Credits a survey costs, on top of its drones.
  BigNum get surveyCredits => _surveyCredits ?? defaultSurveyCredits;

  /// Seconds a survey takes, in [[minProjectSeconds], [maxProjectSeconds]].
  final double surveySeconds;

  /// Resource id of the drones a survey uses up.
  final String surveyDroneResource;
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
    this.hidden = false,
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

  /// Whether it stays out of sight, and out of reach, until a survey
  /// reveals it (`SurveyCommand`). A faction's home body is never hidden.
  final bool hidden;
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

/// Has made at least [amount] of [resourceId] since the game began, over
/// all its bodies, whatever became of it (see
/// `FactionState.lifetimeProduced`).
final class ProducedCondition extends MilestoneCondition {
  /// Creates a produced condition.
  const ProducedCondition({required this.resourceId, required this.amount});

  /// Resource counted.
  final String resourceId;

  /// Units needed.
  final BigNum amount;
}

/// Has earned at least [amount] credits from market sales and contract
/// rewards since the game began, whatever it spent (see `FactionState.lifetimeCredits`).
final class CreditsEarnedCondition extends MilestoneCondition {
  /// Creates a credits-earned condition.
  const CreditsEarnedCondition({required this.amount});

  /// Credits needed.
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

/// Has completed at least [count] contracts since the game began (see
/// `FactionState.contractsCompleted`).
final class ContractsCompletedCondition extends MilestoneCondition {
  /// Creates a contracts-completed condition.
  const ContractsCompletedCondition({required this.count});

  /// Contracts needed.
  final int count;
}

/// Its buildings net at least [perSec] units of [resourceId] a second, in
/// steady state over the whole empire (see `FlowReport.netProducedPerSec`).
final class ProductionRateCondition extends MilestoneCondition {
  /// Creates a production-rate condition.
  const ProductionRateCondition({
    required this.resourceId,
    required this.perSec,
  });

  /// Resource measured.
  final String resourceId;

  /// Net units a second needed.
  final BigNum perSec;
}

/// Owns buildings of at least [count] different types.
final class BuildingTypesBuiltCondition extends MilestoneCondition {
  /// Creates a building-types-built condition.
  const BuildingTypesBuiltCondition({required this.count});

  /// Distinct building types needed.
  final int count;
}

/// Has crew support for at least [count] people (see `CrewTotals.supported`).
final class CrewTotalCondition extends MilestoneCondition {
  /// Creates a crew-total condition.
  const CrewTotalCondition({required this.count});

  /// Supported crew needed.
  final int count;
}

/// Has completed at least [level] stages of megaproject [megaprojectId].
final class MegaprojectLevelCondition extends MilestoneCondition {
  /// Creates a megaproject-level condition.
  const MegaprojectLevelCondition({
    required this.megaprojectId,
    required this.level,
  });

  /// Megaproject measured.
  final String megaprojectId;

  /// Level needed.
  final int level;
}

/// Has had no empire waste, with buildings standing, for [seconds] of game
/// time running (see `FactionState.wasteFreeSince`).
final class ZeroWasteForCondition extends MilestoneCondition {
  /// Creates a zero-waste condition.
  const ZeroWasteForCondition({required this.seconds});

  /// Game seconds without waste needed.
  final double seconds;
}

/// Has surveyed at least [count] of the bodies that began hidden.
final class BodiesSurveyedCondition extends MilestoneCondition {
  /// Creates a bodies-surveyed condition.
  const BodiesSurveyedCondition({required this.count});

  /// Hidden bodies revealed needed.
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

/// What a megaproject level adds to its faction's whole empire.
enum BonusKind {
  /// Percent added to every body's storage cap.
  storagePercent,

  /// Percent added to the crew habitats house.
  housingPercent,

  /// Seconds added to the offline catch-up cap, up to
  /// [RulesDef.maxOfflineCapSeconds] in all.
  offlineCapSeconds,

  /// Percent added to what every building makes.
  outputPercent,

  /// Percent added to the market depth of the faction's sales.
  marketDepthPercent,
}

/// One permanent bonus a megaproject grants per level.
final class BonusDef {
  /// Creates a bonus.
  const BonusDef({required this.kind, required this.amount});

  /// What it raises.
  final BonusKind kind;

  /// How much per level, above zero: percent for the `…Percent` kinds,
  /// seconds for [BonusKind.offlineCapSeconds].
  final double amount;
}

/// A repeatable megaproject: each completed stage raises its level by one
/// and grants [bonusesPerLevel] again, for good; the next stage costs
/// more and takes longer.
final class MegaprojectDef {
  /// Creates a megaproject; the collections are copied unmodifiable.
  MegaprojectDef({
    required this.id,
    required this.name,
    this.hostBodyType,
    required Map<String, BigNum> baseCost,
    required this.costGrowth,
    required this.stageSeconds,
    required this.stageSecondsGrowth,
    required List<BonusDef> bonusesPerLevel,
  }) : baseCost = Map.unmodifiable(baseCost),
       bonusesPerLevel = List.unmodifiable(bonusesPerLevel);

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Id of the [BodyTypeDef] it is built at, or null for none: the faction
  /// must own a body of that type to deliver to a stage, though the goods
  /// may come from any body it owns.
  final String? hostBodyType;

  /// Cost of the first stage, level 0: the key `credits` or a resource id,
  /// to an amount above zero. Goods come from the stock of any owned body
  /// that delivers them.
  final Map<String, BigNum> baseCost;

  /// Cost multiplier per level already reached; at least 1. See
  /// `megaprojectCost`.
  final double costGrowth;

  /// Seconds the first stage takes, in
  /// [[RulesDef.minProjectSeconds], [RulesDef.maxProjectSeconds]].
  final double stageSeconds;

  /// Stage time multiplier per level already reached; at least 1. See
  /// `megaprojectStageSeconds`.
  final double stageSecondsGrowth;

  /// Bonuses each level grants, in content order; at least one.
  final List<BonusDef> bonusesPerLevel;
}

/// A kind of order a neutral exchange posts on a faction's contracts board:
/// deliver a quantity of one resource for a reward in credits (see
/// `stepContracts`).
final class ContractTemplateDef {
  /// Creates a contract template; [minQuantity] defaults to
  /// [defaultMinQuantity].
  ContractTemplateDef({
    required this.id,
    required this.issuer,
    required this.minTier,
    required this.maxTier,
    this.quantitySeconds = defaultQuantitySeconds,
    this.rewardMultiplier = defaultRewardMultiplier,
    BigNum? minQuantity,
    this.maxQuantity,
    this.rewardIncomeSeconds = 0,
  }) : minQuantity = minQuantity ?? BigNum.from(defaultMinQuantity);

  /// [quantitySeconds] when a template does not set it: 4 hours.
  static const double defaultQuantitySeconds = 14400;

  /// [rewardMultiplier] when a template does not set it.
  static const double defaultRewardMultiplier = 2.5;

  /// [minQuantity] when a template does not set it.
  static const double defaultMinQuantity = 10;

  /// Unique id.
  final String id;

  /// Display name of who posts it, such as "Veyra Exchange".
  final String issuer;

  /// Lowest resource tier it asks for.
  final int minTier;

  /// Highest resource tier it asks for; at least [minTier].
  final int maxTier;

  /// Seconds of the faction's current net production of the resource that
  /// a contract asks for; above zero.
  final double quantitySeconds;

  /// Reward per unit as a multiple of the resource's base price: a contract
  /// pays `quantity × basePrice × rewardMultiplier` credits; above zero.
  final double rewardMultiplier;

  /// Fewest units a contract asks for, above zero: what a resource made
  /// slowly, or not yet at all, is asked for.
  final BigNum minQuantity;

  /// Most units a contract asks for, however much is made; at least
  /// [minQuantity]. Null for no ceiling beyond the storage one (a contract
  /// never asks for more than one owned body can store).
  final BigNum? maxQuantity;

  /// Seconds of the faction's income a contract pays at least, so a
  /// capped order still pays its way; zero for none.
  final double rewardIncomeSeconds;
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
    Map<String, MegaprojectDef> megaprojects = const {},
    Map<String, ContractTemplateDef> contractTemplates = const {},
  }) : resources = Map.unmodifiable(resources),
       buildings = Map.unmodifiable(buildings),
       bodyTypes = Map.unmodifiable(bodyTypes),
       milestones = List.unmodifiable(milestones),
       megaprojects = Map.unmodifiable(megaprojects),
       contractTemplates = Map.unmodifiable(contractTemplates);

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

  /// Megaprojects by id, in content order.
  final Map<String, MegaprojectDef> megaprojects;

  /// Contract templates by id, in content order; none means no contracts
  /// are posted.
  final Map<String, ContractTemplateDef> contractTemplates;

  /// Parses and validates decoded content JSON without throwing.
  ///
  /// [bundle] maps each content file stem (`rules`, `resources`,
  /// `buildings`, `body_types`, `galaxy`, `milestones`, and the optional
  /// `megaprojects` and `contracts`, absent meaning none) to its decoded
  /// JSON.
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
