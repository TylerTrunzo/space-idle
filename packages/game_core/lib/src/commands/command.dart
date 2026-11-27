import '../content/content.dart';
import '../num/big_num.dart';
import 'outcome.dart';

String _str(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v is String) return v;
  throw FormatException('command field "$k" must be a string', j);
}

String? _optStr(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v == null || v is String) return v as String?;
  throw FormatException('command field "$k" must be a string or null', j);
}

int _int(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v is int) return v;
  throw FormatException('command field "$k" must be an integer', j);
}

int? _optInt(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v == null || v is int) return v as int?;
  throw FormatException('command field "$k" must be an integer or null', j);
}

bool _optBool(Map<String, Object?> j, String k, {required bool absent}) {
  final v = j[k];
  if (v == null) return absent;
  if (v is bool) return v;
  throw FormatException('command field "$k" must be true or false', j);
}

BigNum _big(Map<String, Object?> j, String k) => BigNum.parse(_str(j, k));

BigNum? _optBig(Map<String, Object?> j, String k) {
  final v = _optStr(j, k);
  return v == null ? null : BigNum.parse(v);
}

Map<String, BigNum> _bigs(Map<String, Object?> j, String k) {
  final v = j[k];
  if (v is! Map) {
    throw FormatException('command field "$k" must be an object', j);
  }
  final out = <String, BigNum>{};
  for (final MapEntry(key: id, value: n) in v.entries) {
    if (id is! String || n is! String) {
      throw FormatException(
        'command field "$k" must map ids to number strings',
        j,
      );
    }
    out[id] = BigNum.parse(n);
  }
  return out;
}

UpgradeTrack _track(Map<String, Object?> j, String k) =>
    UpgradeTrack.values.asNameMap()[_str(j, k)] ??
    (throw FormatException('command field "$k" is not an upgrade track', j));

/// A player or AI action, validated and applied by `applyCommand`.
///
/// Serialized with a `"cmd"` discriminator so scripts, bots and a future
/// server can send commands as JSON.
sealed class Command {
  const Command(this.factionId);

  /// Faction issuing the command; it must own whatever the command touches.
  final String factionId;

  /// The `"cmd"` discriminator written by [toJson].
  String get _cmd;

  /// Fields other than `cmd` and `factionId`.
  Map<String, Object?> get _fields;

  /// Serializes this command.
  Map<String, Object?> toJson() => {
    'cmd': _cmd,
    'factionId': factionId,
    ..._fields,
  };

  /// Restores a command written by [toJson].
  ///
  /// Throws [FormatException] for an unknown `cmd` or a missing or
  /// mistyped field.
  static Command fromJson(Map<String, Object?> j) {
    final f = _str(j, 'factionId');
    return switch (_str(j, 'cmd')) {
      'build' => BuildCommand(
        f,
        _str(j, 'bodyId'),
        _str(j, 'defId'),
        depositResourceId: _optStr(j, 'depositResourceId'),
        autoCrew: _optBool(j, 'autoCrew', absent: true),
      ),
      'demolish' => DemolishCommand(f, _str(j, 'buildingId')),
      'assignCrew' => AssignCrewCommand(
        f,
        _str(j, 'buildingId'),
        _int(j, 'crew'),
      ),
      'upgrade' => UpgradeCommand(f, _str(j, 'buildingId'), _track(j, 'track')),
      'createRoute' => CreateRouteCommand(
        f,
        _str(j, 'fromBodyId'),
        _str(j, 'toBodyId'),
        _str(j, 'resourceId'),
        _big(j, 'ratePerSecond'),
        _int(j, 'cargoShips'),
        stopAtDestination: _optBig(j, 'stopAtDestination'),
      ),
      'updateRoute' => UpdateRouteCommand(
        f,
        _str(j, 'routeId'),
        ratePerSecond: _optBig(j, 'ratePerSecond'),
        cargoShips: _optInt(j, 'cargoShips'),
        stopAtDestination: _optBig(j, 'stopAtDestination'),
        removeStopAtDestination: _optBool(
          j,
          'removeStopAtDestination',
          absent: false,
        ),
      ),
      'moveShips' => MoveShipsCommand(
        f,
        _str(j, 'fromBodyId'),
        _str(j, 'toBodyId'),
        _int(j, 'count'),
      ),
      'removeRoute' => RemoveRouteCommand(f, _str(j, 'routeId')),
      'sell' => SellCommand(
        f,
        _str(j, 'bodyId'),
        _str(j, 'resourceId'),
        _big(j, 'amount'),
      ),
      'setAutoSell' => SetAutoSellCommand(
        f,
        _str(j, 'bodyId'),
        _str(j, 'resourceId'),
        _optBig(j, 'keepAtLeast'),
      ),
      'claimBody' => ClaimBodyCommand(
        f,
        _str(j, 'bodyId'),
        _str(j, 'sourceBodyId'),
      ),
      'survey' => SurveyCommand(
        f,
        _optStr(j, 'bodyId'),
        _str(j, 'sourceBodyId'),
      ),
      'expandSlots' => ExpandSlotsCommand(f, _str(j, 'bodyId')),
      'startMegaprojectStage' => StartMegaprojectStageCommand(
        f,
        _str(j, 'megaprojectId'),
        _str(j, 'bodyId'),
      ),
      'deliverToMegaproject' => DeliverToMegaprojectCommand(
        f,
        _str(j, 'megaprojectId'),
        _str(j, 'bodyId'),
        _bigs(j, 'amounts'),
      ),
      'deliverContract' => DeliverContractCommand(
        f,
        _str(j, 'contractId'),
        _str(j, 'bodyId'),
        _big(j, 'amount'),
      ),
      'discardContract' => DiscardContractCommand(f, _str(j, 'contractId')),
      final other => throw FormatException('unknown command "$other"', j),
    };
  }
}

/// Builds [defId] on [bodyId], paying its build cost.
///
/// Credits come from the faction; resource costs from the body's stock.
/// With [autoCrew] the new building is crewed from the faction's free crew,
/// up to its base crew slots.
final class BuildCommand extends Command {
  /// Creates a build command; extractors need [depositResourceId].
  const BuildCommand(
    super.factionId,
    this.bodyId,
    this.defId, {
    this.depositResourceId,
    this.autoCrew = true,
  });

  /// Body to build on.
  final String bodyId;

  /// Building type to build.
  final String defId;

  /// Extractor only: the body deposit to mine. Ignored for other kinds.
  final String? depositResourceId;

  /// Whether the new building takes as much free crew as it has base crew
  /// slots for (fewer if fewer are free); false leaves it empty. On unless
  /// a command says otherwise, in JSON too.
  final bool autoCrew;

  @override
  String get _cmd => 'build';

  @override
  Map<String, Object?> get _fields => {
    'bodyId': bodyId,
    'defId': defId,
    'depositResourceId': depositResourceId,
    'autoCrew': autoCrew,
  };
}

/// Removes a building, refunding half the credits part of its build cost.
final class DemolishCommand extends Command {
  /// Creates a demolish command.
  const DemolishCommand(super.factionId, this.buildingId);

  /// Building to remove.
  final String buildingId;

  @override
  String get _cmd => 'demolish';

  @override
  Map<String, Object?> get _fields => {'buildingId': buildingId};
}

/// Sets a building's crew to an absolute count.
final class AssignCrewCommand extends Command {
  /// Creates an assign-crew command.
  const AssignCrewCommand(super.factionId, this.buildingId, this.crew);

  /// Building to crew.
  final String buildingId;

  /// Target crew count, not a delta.
  final int crew;

  @override
  String get _cmd => 'assignCrew';

  @override
  Map<String, Object?> get _fields => {'buildingId': buildingId, 'crew': crew};
}

/// Buys one level of an upgrade track for credits.
final class UpgradeCommand extends Command {
  /// Creates an upgrade command.
  const UpgradeCommand(super.factionId, this.buildingId, this.track);

  /// Building to upgrade.
  final String buildingId;

  /// Track to raise by one level.
  final UpgradeTrack track;

  @override
  String get _cmd => 'upgrade';

  @override
  Map<String, Object?> get _fields => {
    'buildingId': buildingId,
    'track': track.name,
  };
}

/// Opens a transport route, taking cargo ships from the from-body's stock.
final class CreateRouteCommand extends Command {
  /// Creates a create-route command; with [stopAtDestination] the route
  /// pauses while its destination holds that much.
  const CreateRouteCommand(
    super.factionId,
    this.fromBodyId,
    this.toBodyId,
    this.resourceId,
    this.ratePerSecond,
    this.cargoShips, {
    this.stopAtDestination,
  });

  /// Source body; must differ from [toBodyId] and share its system.
  final String fromBodyId;

  /// Destination body.
  final String toBodyId;

  /// Resource to move.
  final String resourceId;

  /// Requested units per second; above zero.
  final BigNum ratePerSecond;

  /// Cargo ships to assign; at least one.
  final int cargoShips;

  /// Destination stock, cargo in flight on the route included, at which
  /// the route pauses; above zero, or null to never pause. See
  /// `RouteState.stopAtDestination`.
  final BigNum? stopAtDestination;

  @override
  String get _cmd => 'createRoute';

  @override
  Map<String, Object?> get _fields => {
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'resourceId': resourceId,
    'ratePerSecond': ratePerSecond.toJson(),
    'cargoShips': cargoShips,
    'stopAtDestination': stopAtDestination?.toJson(),
  };
}

/// Changes an existing route's rate, cargo ships or stop level; whatever is
/// left null stays as it is.
///
/// More cargo ships are taken from the from-body's stock, fewer go back to
/// it.
final class UpdateRouteCommand extends Command {
  /// Creates an update-route command; it must change at least one thing.
  const UpdateRouteCommand(
    super.factionId,
    this.routeId, {
    this.ratePerSecond,
    this.cargoShips,
    this.stopAtDestination,
    this.removeStopAtDestination = false,
  });

  /// Route to change.
  final String routeId;

  /// New requested units per second, above zero; null keeps the rate.
  final BigNum? ratePerSecond;

  /// New number of cargo ships, at least one; null keeps them.
  final int? cargoShips;

  /// New stop level, above zero; null keeps the current one (or none).
  final BigNum? stopAtDestination;

  /// Whether to take the stop level off so the route never pauses; not
  /// together with [stopAtDestination].
  final bool removeStopAtDestination;

  @override
  String get _cmd => 'updateRoute';

  @override
  Map<String, Object?> get _fields => {
    'routeId': routeId,
    'ratePerSecond': ratePerSecond?.toJson(),
    'cargoShips': cargoShips,
    'stopAtDestination': stopAtDestination?.toJson(),
    'removeStopAtDestination': removeStopAtDestination,
  };
}

/// Sends [count] cargo ships from one owned body's stock to another in the
/// same system, as a shipment that leaves now and lands after the normal
/// travel time (`travelSeconds`).
///
/// It is the way to get ships to a body before opening a route from it.
final class MoveShipsCommand extends Command {
  /// Creates a move-ships command.
  const MoveShipsCommand(
    super.factionId,
    this.fromBodyId,
    this.toBodyId,
    this.count,
  );

  /// Body whose stock the ships leave; must differ from [toBodyId] and
  /// share its system.
  final String fromBodyId;

  /// Body the ships land on.
  final String toBodyId;

  /// Cargo ships to move; at least one.
  final int count;

  @override
  String get _cmd => 'moveShips';

  @override
  Map<String, Object?> get _fields => {
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'count': count,
  };
}

/// Closes a route, returning its cargo ships to the from-body's stock.
final class RemoveRouteCommand extends Command {
  /// Creates a remove-route command.
  const RemoveRouteCommand(super.factionId, this.routeId);

  /// Route to close.
  final String routeId;

  @override
  String get _cmd => 'removeRoute';

  @override
  Map<String, Object?> get _fields => {'routeId': routeId};
}

/// Sells up to [amount] of a body's stock on the market.
final class SellCommand extends Command {
  /// Creates a sell command.
  const SellCommand(super.factionId, this.bodyId, this.resourceId, this.amount);

  /// Body whose stock is sold.
  final String bodyId;

  /// Resource to sell.
  final String resourceId;

  /// Units to sell; above zero, clamped to the stock held, which must not
  /// be empty.
  final BigNum amount;

  @override
  String get _cmd => 'sell';

  @override
  Map<String, Object?> get _fields => {
    'bodyId': bodyId,
    'resourceId': resourceId,
    'amount': amount.toJson(),
  };
}

/// Adds, changes or removes the auto-sell rule for one body and resource.
final class SetAutoSellCommand extends Command {
  /// Creates a set-auto-sell command; a null [keepAtLeast] removes the rule.
  const SetAutoSellCommand(
    super.factionId,
    this.bodyId,
    this.resourceId,
    this.keepAtLeast,
  );

  /// Body whose stock is sold.
  final String bodyId;

  /// Resource sold.
  final String resourceId;

  /// Units always kept, at least zero; null removes the rule.
  final BigNum? keepAtLeast;

  @override
  String get _cmd => 'setAutoSell';

  @override
  Map<String, Object?> get _fields => {
    'bodyId': bodyId,
    'resourceId': resourceId,
    'keepAtLeast': keepAtLeast?.toJson(),
  };
}

/// Starts claiming an unowned body, paying credits and outpost kits now;
/// the body becomes the faction's when the claim project completes (see
/// `claimSeconds`).
final class ClaimBodyCommand extends Command {
  /// Creates a claim command.
  const ClaimBodyCommand(super.factionId, this.bodyId, this.sourceBodyId);

  /// Unowned body to claim.
  final String bodyId;

  /// Owned body whose stock supplies the outpost kits.
  final String sourceBodyId;

  @override
  String get _cmd => 'claimBody';

  @override
  Map<String, Object?> get _fields => {
    'bodyId': bodyId,
    'sourceBodyId': sourceBodyId,
  };
}

/// Starts surveying a hidden body, paying credits and survey drones now;
/// the body becomes visible to every faction when the survey project
/// completes (see `surveyCost`, `surveySeconds`). It runs beside claims and
/// other surveys without affecting them.
final class SurveyCommand extends Command {
  /// Creates a survey command; a null [bodyId] surveys the next hidden body
  /// of [sourceBodyId]'s system.
  const SurveyCommand(super.factionId, this.bodyId, this.sourceBodyId);

  /// Hidden body to reveal, in the source body's system; null for the
  /// first one in content order in that system that is neither surveyed
  /// nor under survey (see `unsurveyedSignals`).
  final String? bodyId;

  /// Owned body whose stock supplies the survey drones.
  final String sourceBodyId;

  @override
  String get _cmd => 'survey';

  @override
  Map<String, Object?> get _fields => {
    'bodyId': bodyId,
    'sourceBodyId': sourceBodyId,
  };
}

/// Buys one more build slot on an owned body for credits, paid now; the
/// slot arrives when the project completes, after `expandSlotsSeconds`.
/// See `slotCost`.
final class ExpandSlotsCommand extends Command {
  /// Creates an expand-slots command.
  const ExpandSlotsCommand(super.factionId, this.bodyId);

  /// Owned body to add a slot to.
  final String bodyId;

  @override
  String get _cmd => 'expandSlots';

  @override
  Map<String, Object?> get _fields => {'bodyId': bodyId};
}

/// Delivers everything the next stage of a megaproject still needs from
/// one owned body, all or nothing, and so starts the stage: credits from
/// the faction, goods from the body's stock, as a
/// [DeliverToMegaprojectCommand] of whatever `megaprojectRemaining` lists.
/// With nothing delivered yet that is the whole level's cost
/// (`megaprojectCost`). The faction's level rises by one when the stage
/// completes, after `megaprojectStageSeconds`. While a stage is under way
/// it pays for the one after, which then starts as that one completes.
final class StartMegaprojectStageCommand extends Command {
  /// Creates a start-megaproject-stage command.
  const StartMegaprojectStageCommand(
    super.factionId,
    this.megaprojectId,
    this.bodyId,
  );

  /// Megaproject whose next stage to start.
  final String megaprojectId;

  /// Owned body that supplies the goods still owed.
  final String bodyId;

  @override
  String get _cmd => 'startMegaprojectStage';

  @override
  Map<String, Object?> get _fields => {
    'megaprojectId': megaprojectId,
    'bodyId': bodyId,
  };
}

/// Hands goods and credits toward the next stage of a megaproject; the
/// deliveries add up in `FactionState.megaprojectProgress`, from any owned
/// bodies over any time, so a stage may cost more than one body can store.
///
/// Each amount is clamped to what the stage still needs of it and to what
/// is held (the body's stock; the faction's credits for `credits`).
/// Credits are paid as they are delivered, like goods. The delivery that
/// completes the last cost entry starts the stage's timer at once, as a
/// megaproject-stage project, and clears the progress. A megaproject with a
/// host body type takes deliveries only while the faction owns a body of
/// that type; the goods may come from any owned body.
///
/// While a stage is under way, deliveries go to the stage after it
/// (`megaprojectRemaining`); once that is paid for in full it waits, and
/// starts as the stage under way completes (`stepProjects`), its timer
/// running from then. Until it starts, further deliveries fail with
/// [CommandError.projectInProgress].
final class DeliverToMegaprojectCommand extends Command {
  /// Creates a deliver-to-megaproject command.
  const DeliverToMegaprojectCommand(
    super.factionId,
    this.megaprojectId,
    this.bodyId,
    this.amounts,
  );

  /// Megaproject whose next stage to deliver to.
  final String megaprojectId;

  /// Owned body whose stock supplies the goods.
  final String bodyId;

  /// Cost key (`credits` or a resource id of the stage's cost) to the
  /// amount to deliver, each above zero; at least one entry.
  final Map<String, BigNum> amounts;

  @override
  String get _cmd => 'deliverToMegaproject';

  @override
  Map<String, Object?> get _fields => {
    'megaprojectId': megaprojectId,
    'bodyId': bodyId,
    'amounts': {for (final e in amounts.entries) e.key: e.value.toJson()},
  };
}

/// Delivers up to [amount] of a contract's resource from an owned body's
/// stock to the faction's contract; partial deliveries add up, and the
/// reward is paid when the last unit is delivered (see `stepContracts`).
final class DeliverContractCommand extends Command {
  /// Creates a deliver-contract command.
  const DeliverContractCommand(
    super.factionId,
    this.contractId,
    this.bodyId,
    this.amount,
  );

  /// Contract on the faction's board to deliver to.
  final String contractId;

  /// Owned body whose stock supplies the goods.
  final String bodyId;

  /// Units to deliver; above zero, clamped to what the contract still
  /// wants and to the stock held, which must not be empty.
  final BigNum amount;

  @override
  String get _cmd => 'deliverContract';

  @override
  Map<String, Object?> get _fields => {
    'contractId': contractId,
    'bodyId': bodyId,
    'amount': amount.toJson(),
  };
}

/// Takes a contract off the faction's board with no penalty; goods already
/// delivered to it are not returned. Its slot refills after
/// `contractRefillSeconds`, banked after any refills already waiting.
final class DiscardContractCommand extends Command {
  /// Creates a discard-contract command.
  const DiscardContractCommand(super.factionId, this.contractId);

  /// Contract on the faction's board to discard.
  final String contractId;

  @override
  String get _cmd => 'discardContract';

  @override
  Map<String, Object?> get _fields => {'contractId': contractId};
}

/// Why a command was rejected.
enum CommandError {
  /// The acting faction does not exist.
  unknownFaction,

  /// A named body does not exist.
  unknownBody,

  /// The named building does not exist.
  unknownBuilding,

  /// A named building type, resource, upgrade track or megaproject does
  /// not exist.
  unknownDef,

  /// The faction does not own what the command touches.
  notOwner,

  /// The body the command touches is not the faction's yet: its claim of
  /// it is still under way.
  stillClaiming,

  /// The body has no free build slot.
  noBuildSlot,

  /// An extractor names no deposit it can mine on its body.
  depositMissing,

  /// Credits or stock are short of the cost.
  cannotAfford,

  /// The faction's free crew pool is too small.
  crewUnavailable,

  /// The building has fewer crew slots than asked for.
  crewSlotsExceeded,

  /// A count or amount is out of range.
  invalidAmount,

  /// The body to claim already has an owner.
  alreadyOwned,

  /// The body to survey is already surveyed, or a survey without a body
  /// id finds nothing left to survey in the system.
  alreadySurveyed,

  /// The route does not exist, or the endpoints of a route or ship move
  /// are not a valid pair (one body twice, or two systems), or a survey's
  /// body is in another system than its source.
  routeInvalid,

  /// The same timed work is already under way: a claim of the body, an
  /// extra build slot on it, a survey of it, or, for a megaproject, a
  /// stage with the next one already paid for.
  projectInProgress,

  /// The megaproject is built at a body type (`MegaprojectDef.hostBodyType`)
  /// of which the faction owns no body.
  wrongBodyType,

  /// The faction's contracts board has no contract with that id.
  unknownContract,
}

/// Outcome of applying a command.
sealed class CommandResult {
  const CommandResult();
}

/// The command was applied.
final class CommandOk extends CommandResult {
  /// Creates a success result.
  const CommandOk({this.createdId, this.outcome});

  /// Id of the building, route, ship move or project the command created,
  /// if any. A ship move's id is the `Shipment.routeId` of the ships in
  /// flight.
  final String? createdId;

  /// What the command did, as data; `applyCommand` always gives one, of
  /// the kind its command has (see [CommandOutcome]).
  final CommandOutcome? outcome;
}

/// The command was rejected and the state left unchanged.
final class CommandFailed extends CommandResult {
  /// Creates a failure result.
  const CommandFailed(this.error, this.message);

  /// Category of the failure.
  final CommandError error;

  /// A sentence for the player, using display names and formatted
  /// numbers, such as "Needs 1.5K credits (you have 250)". Ids appear only
  /// for things that do not exist.
  final String message;
}
