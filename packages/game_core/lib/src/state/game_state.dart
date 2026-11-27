import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../rng.dart';

Map<String, Object?> _asMap(Object? v) => (v as Map).cast<String, Object?>();

List<T> _list<T>(Object? v, T Function(Map<String, Object?>) f) => [
  for (final e in (v as List)) f(_asMap(e)),
];

Map<String, BigNum> _bigMap(Object? v) => {
  for (final e in _asMap(v).entries) e.key: BigNum.fromJson(e.value! as String),
};

/// A rule that sells a body's surplus of one resource automatically.
final class AutoSellRule {
  /// Creates a rule.
  AutoSellRule({
    required this.bodyId,
    required this.resourceId,
    required this.keepAtLeast,
  });

  /// Restores a rule written by [toJson].
  factory AutoSellRule.fromJson(Map<String, Object?> j) => AutoSellRule(
    bodyId: j['bodyId']! as String,
    resourceId: j['resourceId']! as String,
    keepAtLeast: BigNum.fromJson(j['keepAtLeast']! as String),
  );

  /// Body whose stock is sold.
  final String bodyId;

  /// Resource sold.
  final String resourceId;

  /// Units always kept; only the excess is sold.
  BigNum keepAtLeast;

  /// Serializes this rule.
  Map<String, Object?> toJson() => {
    'bodyId': bodyId,
    'resourceId': resourceId,
    'keepAtLeast': keepAtLeast.toJson(),
  };

  /// An independent copy of this rule.
  AutoSellRule copy() => AutoSellRule(
    bodyId: bodyId,
    resourceId: resourceId,
    keepAtLeast: keepAtLeast,
  );
}

/// A bottleneck a faction has had since [firstSeenAt], kept so reports can
/// tell a standing problem from a new one.
///
/// Identified by [kind], [bodyId], [buildingId] and [resourceId], as on the
/// report's `Bottleneck`; the engine refreshes the list after every tick.
final class SeenBottleneck {
  /// Creates a record.
  SeenBottleneck({
    required this.kind,
    this.bodyId,
    this.buildingId,
    this.resourceId,
    required this.firstSeenAt,
  });

  /// Restores a record written by [toJson].
  factory SeenBottleneck.fromJson(Map<String, Object?> j) => SeenBottleneck(
    kind: j['kind']! as String,
    bodyId: j['bodyId'] as String?,
    buildingId: j['buildingId'] as String?,
    resourceId: j['resourceId'] as String?,
    firstSeenAt: (j['firstSeenAt']! as num).toDouble(),
  );

  /// Name of its `BottleneckKind`, such as `input`.
  final String kind;

  /// Body it is on; null for a faction-wide crew shortage.
  final String? bodyId;

  /// Building held back; null for a crew shortage or a full store.
  final String? buildingId;

  /// Input short of, or resource being wasted; null otherwise.
  final String? resourceId;

  /// Game time in seconds of the tick it was first seen in.
  final double firstSeenAt;

  /// Its identity: kind, body, building and resource.
  String get key => bottleneckKey(kind, bodyId, buildingId, resourceId);

  /// Serializes this record; null ids are left out.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'bodyId': ?bodyId,
    'buildingId': ?buildingId,
    'resourceId': ?resourceId,
    'firstSeenAt': firstSeenAt,
  };
}

/// The identity of a bottleneck of [kind] on [bodyId], [buildingId] and
/// [resourceId], any of which may be null.
String bottleneckKey(
  String kind,
  String? bodyId,
  String? buildingId,
  String? resourceId,
) => '$kind/${bodyId ?? ''}/${buildingId ?? ''}/${resourceId ?? ''}';

/// An order on a faction's contracts board: deliver [quantity] of
/// [resourceId] for [rewardCredits], paid once all of it has been
/// delivered. It never expires (see `stepContracts`).
final class ContractState {
  /// Creates a contract; [delivered] defaults to none.
  ContractState({
    required this.id,
    required this.templateId,
    required this.resourceId,
    required this.quantity,
    this.delivered = const BigNum.zero(),
    required this.rewardCredits,
    required this.postedAt,
  });

  /// Restores a contract written by [toJson].
  factory ContractState.fromJson(Map<String, Object?> j) => ContractState(
    id: j['id']! as String,
    templateId: j['templateId']! as String,
    resourceId: j['resourceId']! as String,
    quantity: BigNum.fromJson(j['quantity']! as String),
    delivered: BigNum.fromJson(j['delivered']! as String),
    rewardCredits: BigNum.fromJson(j['rewardCredits']! as String),
    postedAt: (j['postedAt']! as num).toDouble(),
  );

  /// Unique id, such as `c12`.
  final String id;

  /// Id of the [ContractTemplateDef] it was posted from.
  final String templateId;

  /// Resource asked for.
  final String resourceId;

  /// Units asked for in all.
  final BigNum quantity;

  /// Units delivered so far, at most [quantity].
  BigNum delivered;

  /// Credits paid when the last unit is delivered.
  final BigNum rewardCredits;

  /// Game time in seconds at which it was posted.
  final double postedAt;

  /// Units still to deliver: [quantity] less [delivered], never below
  /// zero, rounded up to whole units (deliveries move whole units, so a
  /// fraction can only come from an older save).
  BigNum get remaining =>
      takeFrom(quantity, delivered).max(const BigNum.zero()).ceil();

  /// Serializes this contract.
  Map<String, Object?> toJson() => {
    'id': id,
    'templateId': templateId,
    'resourceId': resourceId,
    'quantity': quantity.toJson(),
    'delivered': delivered.toJson(),
    'rewardCredits': rewardCredits.toJson(),
    'postedAt': postedAt,
  };

  /// An independent copy of this contract.
  ContractState copy() => ContractState(
    id: id,
    templateId: templateId,
    resourceId: resourceId,
    quantity: quantity,
    delivered: delivered,
    rewardCredits: rewardCredits,
    postedAt: postedAt,
  );
}

/// A faction's mutable state: the player or an AI rival.
final class FactionState {
  /// Creates a faction.
  FactionState({
    required this.id,
    required this.name,
    required this.isPlayer,
    required this.credits,
    required this.baseCrew,
    List<AutoSellRule>? autoSell,
    Set<String>? reachedMilestones,
    Map<String, BigNum>? salesRevenue,
    BigNum? lifetimeCredits,
    Map<String, BigNum>? lifetimeProduced,
    List<SeenBottleneck>? seenBottlenecks,
    Map<String, int>? megaprojectLevels,
    Map<String, Map<String, BigNum>>? megaprojectProgress,
    List<ContractState>? contracts,
    List<double>? contractRefillAt,
    this.contractsCompleted = 0,
    this.wasteFreeSince = 0,
  }) : autoSell = autoSell ?? [],
       megaprojectLevels = megaprojectLevels ?? {},
       megaprojectProgress = megaprojectProgress ?? {},
       contracts = contracts ?? [],
       contractRefillAt = contractRefillAt ?? [],
       seenBottlenecks = seenBottlenecks ?? [],
       reachedMilestones = reachedMilestones ?? {},
       salesRevenue = salesRevenue ?? {},
       lifetimeCredits =
           lifetimeCredits ??
           (salesRevenue ?? const {}).values.fold(
             const BigNum.zero(),
             (t, v) => t + v,
           ),
       lifetimeProduced = lifetimeProduced ?? {};

  /// Restores a faction written by [toJson].
  ///
  /// A save from before contracts existed has none; a player's board then
  /// has every slot due to refill at once, so contracts appear as soon as
  /// it produces something.
  factory FactionState.fromJson(Map<String, Object?> j) => FactionState(
    id: j['id']! as String,
    name: j['name']! as String,
    isPlayer: j['isPlayer']! as bool,
    credits: BigNum.fromJson(j['credits']! as String),
    baseCrew: j['baseCrew']! as int,
    autoSell: _list(j['autoSell'], AutoSellRule.fromJson),
    reachedMilestones: {
      for (final e in j['reachedMilestones']! as List) e as String,
    },
    // Absent in saves from before sales were tracked.
    salesRevenue: j['salesRevenue'] == null ? null : _bigMap(j['salesRevenue']),
    // Both absent in saves from before they were tracked: lifetime credits
    // then default to the sales revenue's total.
    lifetimeCredits: j['lifetimeCredits'] == null
        ? null
        : BigNum.fromJson(j['lifetimeCredits']! as String),
    lifetimeProduced: j['lifetimeProduced'] == null
        ? null
        : _bigMap(j['lifetimeProduced']),
    // Absent in saves from before bottlenecks were remembered.
    seenBottlenecks: j['seenBottlenecks'] == null
        ? null
        : _list(j['seenBottlenecks'], SeenBottleneck.fromJson),
    // Absent in saves from before megaprojects existed.
    megaprojectLevels: j['megaprojectLevels'] == null
        ? null
        : {
            for (final e in _asMap(j['megaprojectLevels']).entries)
              e.key: e.value! as int,
          },
    // Absent in saves from before deliveries accumulated.
    megaprojectProgress: j['megaprojectProgress'] == null
        ? null
        : {
            for (final e in _asMap(j['megaprojectProgress']).entries)
              e.key: _bigMap(e.value),
          },
    // All three absent in saves from before contracts existed.
    contracts: j['contracts'] == null
        ? null
        : _list(j['contracts'], ContractState.fromJson),
    contractRefillAt: switch (j['contractRefillAt']) {
      null when j['isPlayer'] == true => List.filled(
        RulesDef.contractSlots,
        0,
        growable: true,
      ),
      null => null,
      final v => [for (final t in v as List) (t! as num).toDouble()],
    },
    contractsCompleted: (j['contractsCompleted'] as int?) ?? 0,
    // Absent in saves from before waste-free time was tracked.
    wasteFreeSince: (j['wasteFreeSince'] as num?)?.toDouble() ?? 0,
  );

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Whether a human plays this faction.
  final bool isPlayer;

  /// Credits held.
  BigNum credits;

  /// Crew available without habitats.
  int baseCrew;

  /// Auto-sell rules in priority order.
  final List<AutoSellRule> autoSell;

  /// Ids of milestones already reached.
  final Set<String> reachedMilestones;

  /// Resource id to the credits earned selling it on the market since the
  /// game began, manual and auto-sales alike, in first-sale order.
  final Map<String, BigNum> salesRevenue;

  /// Credits earned since the game began: market sales, manual and
  /// auto-sales alike (the sum of [salesRevenue]), plus contract rewards;
  /// spending never lowers it. Credits-earned milestones count it.
  BigNum lifetimeCredits;

  /// Resource id to the units the faction's buildings have made since the
  /// game began, before the storage cap, in first-made order; produced
  /// milestones count it.
  final Map<String, BigNum> lifetimeProduced;

  /// The bottlenecks the faction had in the last tick, each with when it
  /// was first seen, in report order; see `noteBottlenecks`.
  final List<SeenBottleneck> seenBottlenecks;

  /// Megaproject id to the stages of it the faction has completed, in
  /// first-completed order; absent means level 0. Each level grants the
  /// megaproject's bonuses for good (see `bonusesFor`).
  final Map<String, int> megaprojectLevels;

  /// Megaproject id to what has been delivered toward its next stage (the
  /// one after a stage under way), in first-delivered order: each cost key
  /// (`credits` or a resource id) to the amount handed over, at most the
  /// stage's cost. The stage starts, and its entry goes, once every key is
  /// delivered in full, or, while a stage is under way, when that one
  /// completes; absent means nothing delivered yet. See
  /// `DeliverToMegaprojectCommand`.
  final Map<String, Map<String, BigNum>> megaprojectProgress;

  /// Its contracts board, in the order they were posted; at most
  /// [RulesDef.contractSlots]. Only the player has a board in stage 1.5.
  final List<ContractState> contracts;

  /// Game times in seconds at which its empty contract slots refill,
  /// earliest first; banked one after another (see `freeContractSlot`), at
  /// most [RulesDef.contractSlots]. A faction with no contracts and no
  /// refills banked has no board.
  final List<double> contractRefillAt;

  /// Contracts it has completed since the game began; contracts-completed
  /// milestones count it.
  int contractsCompleted;

  /// Game time in seconds since which the faction has had no waste (or the
  /// game's start); the engine moves it to the end of every tick in which a
  /// body it owns wasted anything, or it owns no building. Zero-waste
  /// milestones measure from it.
  double wasteFreeSince;

  /// Serializes this faction; milestones are written sorted.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isPlayer': isPlayer,
    'credits': credits.toJson(),
    'baseCrew': baseCrew,
    'autoSell': [for (final r in autoSell) r.toJson()],
    'reachedMilestones': reachedMilestones.toList()..sort(),
    'salesRevenue': {
      for (final e in salesRevenue.entries) e.key: e.value.toJson(),
    },
    'lifetimeCredits': lifetimeCredits.toJson(),
    'lifetimeProduced': {
      for (final e in lifetimeProduced.entries) e.key: e.value.toJson(),
    },
    'seenBottlenecks': [for (final b in seenBottlenecks) b.toJson()],
    'megaprojectLevels': Map.of(megaprojectLevels),
    'megaprojectProgress': {
      for (final MapEntry(key: id, value: got) in megaprojectProgress.entries)
        id: {for (final e in got.entries) e.key: e.value.toJson()},
    },
    'contracts': [for (final k in contracts) k.toJson()],
    'contractRefillAt': List.of(contractRefillAt),
    'contractsCompleted': contractsCompleted,
    'wasteFreeSince': wasteFreeSince,
  };

  /// An independent deep copy of this faction.
  FactionState copy() => FactionState(
    id: id,
    name: name,
    isPlayer: isPlayer,
    credits: credits,
    baseCrew: baseCrew,
    autoSell: [for (final r in autoSell) r.copy()],
    reachedMilestones: Set.of(reachedMilestones),
    salesRevenue: Map.of(salesRevenue),
    lifetimeCredits: lifetimeCredits,
    lifetimeProduced: Map.of(lifetimeProduced),
    // Records are immutable, so a new list is a deep copy.
    seenBottlenecks: List.of(seenBottlenecks),
    megaprojectLevels: Map.of(megaprojectLevels),
    megaprojectProgress: {
      for (final MapEntry(key: id, value: got) in megaprojectProgress.entries)
        id: Map.of(got),
    },
    contracts: [for (final k in contracts) k.copy()],
    contractRefillAt: List.of(contractRefillAt),
    contractsCompleted: contractsCompleted,
    wasteFreeSince: wasteFreeSince,
  );
}

/// One constructed building and its upgrade levels.
final class BuildingState {
  /// Creates a building; every upgrade track starts at level 0 unless given.
  BuildingState({
    required this.id,
    required this.defId,
    this.depositResourceId,
    required this.crew,
    Map<UpgradeTrack, int>? levels,
    this.lastRunFraction = 0,
    this.lastLimitReason,
  }) : levels = {for (final t in UpgradeTrack.values) t: levels?[t] ?? 0};

  /// Restores a building written by [toJson].
  factory BuildingState.fromJson(Map<String, Object?> j) {
    final lv = _asMap(j['levels']);
    return BuildingState(
      id: j['id']! as String,
      defId: j['defId']! as String,
      depositResourceId: j['depositResourceId'] as String?,
      crew: j['crew']! as int,
      levels: {
        for (final t in UpgradeTrack.values) t: (lv[t.name] as int?) ?? 0,
      },
      lastRunFraction: (j['lastRunFraction']! as num).toDouble(),
      lastLimitReason: j['lastLimitReason'] as String?,
    );
  }

  /// Unique id.
  final String id;

  /// Id of its [BuildingDef].
  final String defId;

  /// Extractor only: the deposit it mines.
  final String? depositResourceId;

  /// Crew assigned.
  int crew;

  /// Level of every upgrade track.
  final Map<UpgradeTrack, int> levels;

  /// Fraction of full rate achieved in the last step.
  double lastRunFraction;

  /// Why the last step ran below full rate, if it did: `noCrew`,
  /// `input:<resourceId>` or `understaffed` (see `stepProduction`).
  String? lastLimitReason;

  /// Serializes this building.
  Map<String, Object?> toJson() => {
    'id': id,
    'defId': defId,
    'depositResourceId': depositResourceId,
    'crew': crew,
    'levels': {for (final e in levels.entries) e.key.name: e.value},
    'lastRunFraction': lastRunFraction,
    'lastLimitReason': lastLimitReason,
  };

  /// An independent deep copy of this building.
  BuildingState copy() => BuildingState(
    id: id,
    defId: defId,
    depositResourceId: depositResourceId,
    crew: crew,
    levels: levels,
    lastRunFraction: lastRunFraction,
    lastLimitReason: lastLimitReason,
  );
}

/// A planet, moon, or belt and what is built on it.
final class BodyState {
  /// Creates a body.
  BodyState({
    required this.id,
    required this.name,
    required this.systemId,
    required this.typeId,
    required this.orbit,
    required this.deposits,
    this.ownerId,
    this.extraSlots = 0,
    this.surveyed = true,
    Map<String, BigNum>? stock,
    List<BuildingState>? buildings,
  }) : stock = stock ?? {},
       buildings = buildings ?? [];

  /// Restores a body written by [toJson].
  factory BodyState.fromJson(Map<String, Object?> j) => BodyState(
    id: j['id']! as String,
    name: j['name']! as String,
    systemId: j['systemId']! as String,
    typeId: j['typeId']! as String,
    orbit: j['orbit']! as int,
    deposits: [
      for (final d in j['deposits']! as List)
        DepositDef(
          resourceId: _asMap(d)['resourceId']! as String,
          richness: (_asMap(d)['richness']! as num).toDouble(),
        ),
    ],
    ownerId: j['ownerId'] as String?,
    extraSlots: j['extraSlots']! as int,
    surveyed: j['surveyed'] as bool? ?? true,
    stock: _bigMap(j['stock']),
    buildings: _list(j['buildings'], BuildingState.fromJson),
  );

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Id of the system it belongs to.
  final String systemId;

  /// Id of its [BodyTypeDef].
  final String typeId;

  /// Orbit index within its system.
  final int orbit;

  /// Its deposits.
  final List<DepositDef> deposits;

  /// Owning faction id, or null if unclaimed.
  String? ownerId;

  /// Build slots bought on top of its body type's (`ExpandSlotsCommand`).
  int extraSlots;

  /// Whether it is known to the factions: false for a hidden body until a
  /// survey completes, true for every other body. A body that is not
  /// surveyed is invisible and out of reach (see `isVisible`).
  bool surveyed;

  /// Resource id to units stored here.
  final Map<String, BigNum> stock;

  /// Buildings on this body.
  final List<BuildingState> buildings;

  /// Resource id to units lost in the last engine tick: cut by the storage
  /// cap at the end of the tick, or cargo lost with both its ends.
  ///
  /// Transient: reset at the start of every tick, never serialized.
  final Map<String, BigNum> wastedThisStep = {};

  /// Takes [amount] of [resourceId] from [stock], float residue below zero
  /// snapped to zero ([takeFrom]).
  void take(String resourceId, BigNum amount) => stock[resourceId] = takeFrom(
    stock[resourceId] ?? const BigNum.zero(),
    amount,
  );

  /// Serializes this body; [wastedThisStep] is left out.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'systemId': systemId,
    'typeId': typeId,
    'orbit': orbit,
    'deposits': [
      for (final d in deposits)
        {'resourceId': d.resourceId, 'richness': d.richness},
    ],
    'ownerId': ownerId,
    'extraSlots': extraSlots,
    'surveyed': surveyed,
    'stock': {for (final e in stock.entries) e.key: e.value.toJson()},
    'buildings': [for (final b in buildings) b.toJson()],
  };

  /// An independent deep copy of this body; [wastedThisStep] starts empty,
  /// as after a save round trip.
  BodyState copy() => BodyState(
    id: id,
    name: name,
    systemId: systemId,
    typeId: typeId,
    orbit: orbit,
    deposits: List.of(deposits),
    ownerId: ownerId,
    extraSlots: extraSlots,
    surveyed: surveyed,
    stock: Map.of(stock),
    buildings: [for (final b in buildings) b.copy()],
  );
}

/// A standing transport order between two bodies.
final class RouteState {
  /// Creates a route.
  RouteState({
    required this.id,
    required this.ownerId,
    required this.fromBodyId,
    required this.toBodyId,
    required this.resourceId,
    required this.ratePerSecond,
    required this.cargoShips,
    this.stopAtDestination,
  });

  /// Restores a route written by [toJson]; a missing stop level is none.
  factory RouteState.fromJson(Map<String, Object?> j) => RouteState(
    id: j['id']! as String,
    ownerId: j['ownerId']! as String,
    fromBodyId: j['fromBodyId']! as String,
    toBodyId: j['toBodyId']! as String,
    resourceId: j['resourceId']! as String,
    ratePerSecond: BigNum.fromJson(j['ratePerSecond']! as String),
    cargoShips: j['cargoShips']! as int,
    stopAtDestination: switch (j['stopAtDestination']) {
      null => null,
      final v => BigNum.fromJson(v as String),
    },
  );

  /// Unique id.
  final String id;

  /// Owning faction id.
  final String ownerId;

  /// Source body id.
  final String fromBodyId;

  /// Destination body id.
  final String toBodyId;

  /// Resource moved.
  final String resourceId;

  /// Requested units per second.
  BigNum ratePerSecond;

  /// Cargo ships assigned.
  int cargoShips;

  /// Destination stock at which the route pauses, above zero, or null to
  /// send without stopping. Only the destination's stock counts, not cargo
  /// in flight, so the destination may end up above it by what was in
  /// flight when it got there (see `routePaused`). The route
  /// commands keep it to the destination's storage cap.
  BigNum? stopAtDestination;

  /// Serializes this route.
  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'resourceId': resourceId,
    'ratePerSecond': ratePerSecond.toJson(),
    'cargoShips': cargoShips,
    'stopAtDestination': stopAtDestination?.toJson(),
  };

  /// An independent copy of this route.
  RouteState copy() => RouteState(
    id: id,
    ownerId: ownerId,
    fromBodyId: fromBodyId,
    toBodyId: toBodyId,
    resourceId: resourceId,
    ratePerSecond: ratePerSecond,
    cargoShips: cargoShips,
    stopAtDestination: stopAtDestination,
  );
}

/// Cargo in flight along a route, or cargo ships being moved
/// (`MoveShipsCommand`).
final class Shipment {
  /// Creates a shipment.
  Shipment({
    required this.routeId,
    required this.fromBodyId,
    required this.toBodyId,
    required this.ownerId,
    required this.resourceId,
    required this.amount,
    required this.departAt,
    required this.arriveAt,
  });

  /// Restores a shipment written by [toJson].
  factory Shipment.fromJson(Map<String, Object?> j) => Shipment(
    routeId: j['routeId']! as String,
    fromBodyId: j['fromBodyId']! as String,
    toBodyId: j['toBodyId']! as String,
    ownerId: j['ownerId']! as String,
    resourceId: j['resourceId']! as String,
    amount: BigNum.fromJson(j['amount']! as String),
    departAt: (j['departAt']! as num).toDouble(),
    arriveAt: (j['arriveAt']! as num).toDouble(),
  );

  /// Route that sent it, or for cargo ships being moved the id the move
  /// was given (`MoveShipsCommand`), which no route has.
  final String routeId;

  /// Source body id, where the goods return if the destination is lost.
  final String fromBodyId;

  /// Destination body id.
  final String toBodyId;

  /// Faction that sent it; it outlives the route's removal.
  final String ownerId;

  /// Resource carried.
  final String resourceId;

  /// Units carried; grows while later sends merge into it (see
  /// `sendCargo`).
  BigNum amount;

  /// Game time in seconds at which it left; later sends within
  /// [RulesDef.shipmentMergeSeconds] of this join it.
  final double departAt;

  /// Game time in seconds at which it arrives.
  final double arriveAt;

  /// Serializes this shipment.
  Map<String, Object?> toJson() => {
    'routeId': routeId,
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'ownerId': ownerId,
    'resourceId': resourceId,
    'amount': amount.toJson(),
    'departAt': departAt,
    'arriveAt': arriveAt,
  };

  /// An independent copy of this shipment.
  Shipment copy() => Shipment(
    routeId: routeId,
    fromBodyId: fromBodyId,
    toBodyId: toBodyId,
    ownerId: ownerId,
    resourceId: resourceId,
    amount: amount,
    departAt: departAt,
    arriveAt: arriveAt,
  );
}

/// Market saturation per resource.
final class MarketState {
  /// Creates a market; a missing resource is at full saturation.
  MarketState({Map<String, double>? saturation})
    : saturation = saturation ?? {};

  /// Restores a market written by [toJson].
  factory MarketState.fromJson(Map<String, Object?> j) => MarketState(
    saturation: {
      for (final e in _asMap(j['saturation']).entries)
        e.key: (e.value! as num).toDouble(),
    },
  );

  /// Resource id to saturation in `[floor, 1]`; absent means 1.
  final Map<String, double> saturation;

  /// Serializes this market.
  Map<String, Object?> toJson() => {'saturation': saturation};

  /// An independent copy of this market.
  MarketState copy() => MarketState(saturation: Map.of(saturation));
}

/// What a [ProjectState] does when it completes.
enum ProjectKind {
  /// Makes its target body the faction's.
  claim,

  /// Adds one extra build slot to its target body.
  expandSlots,

  /// Reveals its hidden target body (`SurveyCommand`).
  survey,

  /// Finishes a stage of its target megaproject.
  megaprojectStage,
}

/// Timed work a faction has paid for, which takes effect at [finishAt]
/// (see `stepProjects`).
final class ProjectState {
  /// Creates a project.
  ProjectState({
    required this.id,
    required this.factionId,
    required this.kind,
    required this.targetId,
    required this.startedAt,
    required this.finishAt,
  });

  /// Restores a project written by [toJson]; an unknown [kind] throws. The
  /// `data` field older saves wrote, always empty, is ignored.
  factory ProjectState.fromJson(Map<String, Object?> j) => ProjectState(
    id: j['id']! as String,
    factionId: j['factionId']! as String,
    kind: ProjectKind.values.byName(j['kind']! as String),
    targetId: j['targetId']! as String,
    startedAt: (j['startedAt']! as num).toDouble(),
    finishAt: (j['finishAt']! as num).toDouble(),
  );

  /// Unique id, such as `p7`.
  final String id;

  /// Faction that started it and gets its effect.
  final String factionId;

  /// What it does on completion.
  final ProjectKind kind;

  /// What it acts on: a body id, or a megaproject id for
  /// [ProjectKind.megaprojectStage].
  final String targetId;

  /// Game time in seconds at which it was started and paid for.
  final double startedAt;

  /// Game time in seconds from which it is complete.
  final double finishAt;

  /// Serializes this project.
  Map<String, Object?> toJson() => {
    'id': id,
    'factionId': factionId,
    'kind': kind.name,
    'targetId': targetId,
    'startedAt': startedAt,
    'finishAt': finishAt,
  };

  /// An independent copy of this project.
  ProjectState copy() => ProjectState(
    id: id,
    factionId: factionId,
    kind: kind,
    targetId: targetId,
    startedAt: startedAt,
    finishAt: finishAt,
  );
}

/// The whole mutable game world.
final class GameState {
  /// Creates a game state.
  GameState({
    this.saveVersion = currentSaveVersion,
    this.time = 0,
    required this.rngState,
    required this.factions,
    required this.bodies,
    List<RouteState>? routes,
    List<Shipment>? shipments,
    MarketState? market,
    List<ProjectState>? projects,
    this.nextId = 1,
  }) : routes = routes ?? [],
       shipments = shipments ?? [],
       market = market ?? MarketState(),
       projects = projects ?? [];

  /// Restores a state written by [toJson].
  factory GameState.fromJson(Map<String, Object?> j) => GameState(
    saveVersion: j['saveVersion']! as int,
    time: (j['time']! as num).toDouble(),
    rngState: j['rngState']! as int,
    factions: _list(j['factions'], FactionState.fromJson),
    bodies: _list(j['bodies'], BodyState.fromJson),
    routes: _list(j['routes'], RouteState.fromJson),
    shipments: _list(j['shipments'], Shipment.fromJson),
    market: MarketState.fromJson(_asMap(j['market'])),
    // Absent in saves from before projects existed.
    projects: j['projects'] == null
        ? null
        : _list(j['projects'], ProjectState.fromJson),
    nextId: j['nextId']! as int,
  );

  /// The save format version this code writes.
  static const int currentSaveVersion = 1;

  /// Version of the format this state was loaded from or created in.
  int saveVersion;

  /// Game seconds elapsed.
  double time;

  /// State of the game's [Rng].
  int rngState;

  /// Factions in content order.
  final List<FactionState> factions;

  /// Bodies in content order.
  final List<BodyState> bodies;

  /// Transport routes.
  final List<RouteState> routes;

  /// Cargo in flight.
  final List<Shipment> shipments;

  /// Market saturation.
  final MarketState market;

  /// Projects under way, every faction's, in the order they were started.
  final List<ProjectState> projects;

  /// Counter behind [newId].
  int nextId;

  /// Returns a fresh unique id such as `b7`.
  String newId(String prefix) => '$prefix${nextId++}';

  /// Returns the faction with [id]; throws if there is none.
  FactionState faction(String id) => factions.firstWhere((f) => f.id == id);

  /// Returns the body with [id]; throws if there is none.
  BodyState body(String id) => bodies.firstWhere((b) => b.id == id);

  /// Serializes the whole state.
  Map<String, Object?> toJson() => {
    'saveVersion': saveVersion,
    'time': time,
    'rngState': rngState,
    'factions': [for (final f in factions) f.toJson()],
    'bodies': [for (final b in bodies) b.toJson()],
    'routes': [for (final r in routes) r.toJson()],
    'shipments': [for (final s in shipments) s.toJson()],
    'market': market.toJson(),
    'projects': [for (final p in projects) p.toJson()],
    'nextId': nextId,
  };

  /// An independent deep copy of the whole state, equal to a save round
  /// trip (`GameState.fromJson(toJson())`) but without the JSON; transient
  /// [BodyState.wastedThisStep] starts empty.
  GameState copy() => GameState(
    saveVersion: saveVersion,
    time: time,
    rngState: rngState,
    factions: [for (final f in factions) f.copy()],
    bodies: [for (final b in bodies) b.copy()],
    routes: [for (final r in routes) r.copy()],
    shipments: [for (final sh in shipments) sh.copy()],
    market: market.copy(),
    projects: [for (final p in projects) p.copy()],
    nextId: nextId,
  );
}

/// Builds the starting world from [content], seeding the game [Rng] with
/// [seed].
GameState newGameState(Content content, int seed) {
  final state = GameState(
    rngState: Rng(seed).state,
    factions: [],
    bodies: [
      for (final sys in content.galaxy.systems)
        for (final b in sys.bodies)
          BodyState(
            id: b.id,
            name: b.name,
            systemId: sys.id,
            typeId: b.typeId,
            orbit: b.orbit,
            deposits: List.of(b.deposits),
            surveyed: !b.hidden,
          ),
    ],
  );
  final refill = content.rules.contractRefillSeconds;
  for (final f in content.galaxy.factions) {
    state.factions.add(
      FactionState(
        id: f.id,
        name: f.name,
        isPlayer: f.isPlayer,
        credits: f.credits,
        baseCrew: f.baseCrew,
        // The player's board starts empty: its first slot fills as soon as
        // something is made, the others one refill apart. Only the player
        // trades with the exchange in stage 1.5.
        contractRefillAt: f.isPlayer
            ? [for (var i = 0; i < RulesDef.contractSlots; i++) refill * i]
            : null,
      ),
    );
    final home = state.body(f.homeBodyId)..ownerId = f.id;
    home.stock.addAll(f.stock);
    for (final sb in f.buildings) {
      home.buildings.add(
        BuildingState(
          id: state.newId('b'),
          defId: sb.defId,
          depositResourceId: sb.depositResourceId,
          crew: sb.crew,
        ),
      );
    }
  }
  return state;
}
