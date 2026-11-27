import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';

/// What a command that was applied did, as data for the app or a script to
/// word; it carries no text of its own.
///
/// Every outcome says what the command took and gave: [spent] and [gained]
/// map `credits` (the faction's) or a resource id (stock on [bodyId]) to
/// the amount, in the order the cost lists them. Each kind adds what it
/// changed.
sealed class CommandOutcome {
  /// Creates the parts every outcome has; the maps are copied
  /// unmodifiable.
  CommandOutcome({
    Map<String, BigNum> spent = const {},
    Map<String, BigNum> gained = const {},
  }) : spent = Map.unmodifiable(spent),
       gained = Map.unmodifiable(gained);

  /// Body whose stock the goods in [spent] and [gained] left or reached;
  /// null when the command moved no goods.
  String? get bodyId;

  /// Credits and goods the command took.
  final Map<String, BigNum> spent;

  /// Credits and goods the command gave back or paid out.
  final Map<String, BigNum> gained;
}

/// A `BuildCommand` put up [buildingId], a [defId], on [bodyId].
final class Built extends CommandOutcome {
  /// Creates the outcome.
  Built({
    required this.bodyId,
    required this.buildingId,
    required this.defId,
    required this.crew,
    super.spent,
  });

  @override
  final String bodyId;

  /// The new building.
  final String buildingId;

  /// Its building type.
  final String defId;

  /// Crew it took from the free crew (`autoCrew`).
  final int crew;
}

/// A `DemolishCommand` took down [buildingId], a [defId], on [bodyId];
/// [gained] is the credits refunded.
final class Demolished extends CommandOutcome {
  /// Creates the outcome.
  Demolished({
    required this.bodyId,
    required this.buildingId,
    required this.defId,
    super.gained,
  });

  @override
  final String bodyId;

  /// The building removed.
  final String buildingId;

  /// Its building type.
  final String defId;
}

/// An `AssignCrewCommand` set [buildingId]'s crew from [previousCrew] to
/// [crew].
final class CrewAssigned extends CommandOutcome {
  /// Creates the outcome.
  CrewAssigned({
    required this.buildingId,
    required this.previousCrew,
    required this.crew,
  });

  /// The building crewed.
  final String buildingId;

  /// Its crew before.
  final int previousCrew;

  /// Its crew now.
  final int crew;

  @override
  String? get bodyId => null;
}

/// An `UpgradeCommand` raised [track] on [buildingId] to [level].
final class Upgraded extends CommandOutcome {
  /// Creates the outcome.
  Upgraded({
    required this.bodyId,
    required this.buildingId,
    required this.track,
    required this.level,
    super.spent,
    this.crewAdded = 0,
  });

  @override
  final String bodyId;

  /// The building upgraded.
  final String buildingId;

  /// The track raised.
  final UpgradeTrack track;

  /// Its level now.
  final int level;

  /// Crew moved from the free crew into the crew slots a capacity level
  /// added: as many as are free, up to the slots added; 0 for the other
  /// tracks and for buildings without crew slots (habitats, warehouses).
  final int crewAdded;
}

/// A `CreateRouteCommand` opened [routeId], taking its cargo ships from
/// [bodyId], the route's source.
final class RouteCreated extends CommandOutcome {
  /// Creates the outcome.
  RouteCreated({
    required this.bodyId,
    required this.routeId,
    this.stopClampedTo,
    super.spent,
  });

  @override
  final String bodyId;

  /// The new route.
  final String routeId;

  /// When the stop level asked for was above the destination's storage
  /// cap, the cap it was cut to (the route's stop level now); else null.
  final BigNum? stopClampedTo;
}

/// An `UpdateRouteCommand` changed [routeId]; cargo ships added came from,
/// and ships taken off went back to, [bodyId], its source.
final class RouteUpdated extends CommandOutcome {
  /// Creates the outcome.
  RouteUpdated({
    required this.bodyId,
    required this.routeId,
    this.stopClampedTo,
    super.spent,
    super.gained,
  });

  @override
  final String bodyId;

  /// The route changed.
  final String routeId;

  /// When the stop level asked for was above the destination's storage
  /// cap, the cap it was cut to (the route's stop level now); else null.
  final BigNum? stopClampedTo;
}

/// A `RemoveRouteCommand` closed [routeId]; its cargo ships went back to
/// [bodyId], its source.
final class RouteRemoved extends CommandOutcome {
  /// Creates the outcome.
  RouteRemoved({required this.bodyId, required this.routeId, super.gained});

  @override
  final String bodyId;

  /// The route closed.
  final String routeId;
}

/// A `MoveShipsCommand` sent [count] cargo ships from [bodyId] to
/// [toBodyId] as shipment [shipmentId], landing at [arriveAt].
final class ShipsSent extends CommandOutcome {
  /// Creates the outcome.
  ShipsSent({
    required this.bodyId,
    required this.shipmentId,
    required this.toBodyId,
    required this.count,
    required this.arriveAt,
    super.spent,
  });

  @override
  final String bodyId;

  /// The `Shipment.routeId` of the ships in flight.
  final String shipmentId;

  /// Body they land on.
  final String toBodyId;

  /// Cargo ships sent.
  final int count;

  /// Game time in seconds at which they land.
  final double arriveAt;
}

/// A `SellCommand` sold [amount] of [resourceId] from [bodyId] for
/// [revenue] credits.
final class Sold extends CommandOutcome {
  /// Creates the outcome; [spent] and [gained] follow from the sale.
  Sold({
    required this.bodyId,
    required this.resourceId,
    required this.amount,
    required this.revenue,
  }) : super(spent: {resourceId: amount}, gained: {'credits': revenue});

  @override
  final String bodyId;

  /// Resource sold.
  final String resourceId;

  /// Units sold, at most the amount asked for.
  final BigNum amount;

  /// Credits earned.
  final BigNum revenue;
}

/// A `SetAutoSellCommand` set the rule for [resourceId] on [bodyId] to keep
/// [keepAtLeast], or removed it when that is null.
final class AutoSellSet extends CommandOutcome {
  /// Creates the outcome.
  AutoSellSet({
    required this.bodyId,
    required this.resourceId,
    required this.keepAtLeast,
  });

  @override
  final String bodyId;

  /// Resource the rule sells.
  final String resourceId;

  /// Units kept; null when the rule was removed.
  final BigNum? keepAtLeast;
}

/// A claim, survey or extra build slot started: project [projectId], of
/// [kind], on body [targetId], paid from [bodyId] (the claim's or
/// survey's source, the body getting the slot), done at [finishAt].
final class ProjectStarted extends CommandOutcome {
  /// Creates the outcome.
  ProjectStarted({
    required this.bodyId,
    required this.projectId,
    required this.kind,
    required this.targetId,
    required this.finishAt,
    this.noKitsNeeded = false,
    super.spent,
  });

  @override
  final String bodyId;

  /// The new project.
  final String projectId;

  /// What it does.
  final ProjectKind kind;

  /// Body it acts on: the one claimed, surveyed or given a slot.
  final String targetId;

  /// Game time in seconds at which it completes.
  final double finishAt;

  /// For a claim, whether it took no outpost kits (only the first one
  /// does); false for other kinds.
  final bool noKitsNeeded;
}

/// A delivery to megaproject [megaprojectId] (`DeliverToMegaprojectCommand`
/// or `StartMegaprojectStageCommand`), from [bodyId], toward the stage
/// that brings it to [level].
///
/// [delivered] is what this delivery handed over (the same as [spent]),
/// and [remaining] what that stage still lacks after it. Once it lacks
/// nothing, either [stageStarted] (project [projectId], done at
/// [finishAt]) or, while the stage before it is under way, [queued]: it
/// starts as that one completes, at [finishAt] of it.
final class MegaprojectDelivered extends CommandOutcome {
  /// Creates the outcome.
  MegaprojectDelivered({
    required this.bodyId,
    required this.megaprojectId,
    required this.level,
    required Map<String, BigNum> delivered,
    required Map<String, BigNum> remaining,
    this.stageStarted = false,
    this.queued = false,
    this.projectId,
    this.finishAt,
  }) : delivered = Map.unmodifiable(delivered),
       remaining = Map.unmodifiable(remaining),
       super(spent: delivered);

  @override
  final String bodyId;

  /// The megaproject delivered to.
  final String megaprojectId;

  /// The level the stage being paid for brings it to.
  final int level;

  /// What this delivery handed over: `credits` or a resource id to the
  /// amount.
  final Map<String, BigNum> delivered;

  /// What the stage still lacks; empty once it is paid for.
  final Map<String, BigNum> remaining;

  /// Whether the stage's timer started now.
  final bool stageStarted;

  /// Whether the stage is paid for and waits for the one under way.
  final bool queued;

  /// The stage's project when [stageStarted]; else null.
  final String? projectId;

  /// When [stageStarted], when the stage completes; when [queued], when
  /// the stage under way completes and this one starts; else null.
  final double? finishAt;
}

/// A `SetMegaprojectAutoCommand` set how the faction feeds
/// [megaprojectId] on its own: when [goods] go in, and whether it takes
/// [credits] above the shared reserve, at [creditWeight]; no goods and no
/// credits clears it.
final class MegaprojectAutoSet extends CommandOutcome {
  /// Creates the outcome.
  MegaprojectAutoSet({
    required this.megaprojectId,
    required this.goods,
    required this.credits,
    required this.creditWeight,
  });

  @override
  String? get bodyId => null;

  /// The megaproject fed.
  final String megaprojectId;

  /// When goods go in on their own.
  final GoodsFeedMode goods;

  /// Whether credits go in on their own.
  final bool credits;

  /// Its weight in the split of the credits above the reserve, 0 to 10.
  final int creditWeight;
}

/// A `SetAutoPayReserveCommand` set the credits the faction keeps from
/// auto-pay to [reserve].
final class AutoPayReserveSet extends CommandOutcome {
  /// Creates the outcome.
  AutoPayReserveSet({required this.reserve});

  @override
  String? get bodyId => null;

  /// Credits always kept.
  final BigNum reserve;
}

/// A `DeliverContractCommand` delivered [delivered] units of [resourceId]
/// to contract [contractId], [totalDelivered] of its [quantity] in all:
/// from [bodyId], or, for a delivery from every body ([bodyId] null), from
/// the bodies [fromBodies] lists.
///
/// When that [completed] it, [rewardPaid] credits were paid (also in
/// [gained]), the contract left the board, and its slot refills; the
/// board's next contract arrives at [nextContractAt], the soonest refill.
final class ContractProgress extends CommandOutcome {
  /// Creates the outcome.
  ContractProgress({
    required this.bodyId,
    required Map<String, BigNum> fromBodies,
    required this.contractId,
    required this.resourceId,
    required this.delivered,
    required this.totalDelivered,
    required this.quantity,
    this.rewardPaid,
    this.nextContractAt,
  }) : fromBodies = Map.unmodifiable(fromBodies),
       super(spent: {resourceId: delivered}, gained: {'credits': ?rewardPaid});

  /// The body the goods came from, or null for a delivery from every body,
  /// whose units [fromBodies] gives by body.
  @override
  final String? bodyId;

  /// Body id to the whole units of [resourceId] taken from it, in the order
  /// they were taken (the fullest first); one entry with [bodyId] when it
  /// is set. They add up to [delivered].
  final Map<String, BigNum> fromBodies;

  /// The contract delivered to.
  final String contractId;

  /// Resource it asks for.
  final String resourceId;

  /// Units this delivery handed over.
  final BigNum delivered;

  /// Units delivered to it in all, now.
  final BigNum totalDelivered;

  /// Units it asks for in all.
  final BigNum quantity;

  /// Credits paid on completion; null while it is still open.
  final BigNum? rewardPaid;

  /// Once [completed], the game time in seconds of the board's soonest
  /// refill; else null, as when none is banked.
  final double? nextContractAt;

  /// Whether this delivery finished it.
  bool get completed => rewardPaid != null;
}

/// A `DiscardContractCommand` took contract [contractId], for [quantity] of
/// [resourceId], off the board; the board's next contract arrives at
/// [nextContractAt], the soonest refill.
final class ContractDiscarded extends CommandOutcome {
  /// Creates the outcome.
  ContractDiscarded({
    required this.contractId,
    required this.resourceId,
    required this.quantity,
    this.nextContractAt,
  });

  /// The contract discarded.
  final String contractId;

  /// Resource it asked for.
  final String resourceId;

  /// Units it asked for.
  final BigNum quantity;

  /// Game time in seconds of the board's soonest refill; null only if
  /// none is banked, which a board of full slots never has.
  final double? nextContractAt;

  @override
  String? get bodyId => null;
}
