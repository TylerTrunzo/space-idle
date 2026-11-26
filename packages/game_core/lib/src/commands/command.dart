import '../content/content.dart';
import '../num/big_num.dart';

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

BigNum _big(Map<String, Object?> j, String k) => BigNum.parse(_str(j, k));

BigNum? _optBig(Map<String, Object?> j, String k) {
  final v = _optStr(j, k);
  return v == null ? null : BigNum.parse(v);
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
      'expandSlots' => ExpandSlotsCommand(f, _str(j, 'bodyId')),
      final other => throw FormatException('unknown command "$other"', j),
    };
  }
}

/// Builds [defId] on [bodyId], paying its build cost.
///
/// Credits come from the faction; resource costs from the body's stock.
final class BuildCommand extends Command {
  /// Creates a build command; extractors need [depositResourceId].
  const BuildCommand(
    super.factionId,
    this.bodyId,
    this.defId, {
    this.depositResourceId,
  });

  /// Body to build on.
  final String bodyId;

  /// Building type to build.
  final String defId;

  /// Extractor only: the body deposit to mine. Ignored for other kinds.
  final String? depositResourceId;

  @override
  String get _cmd => 'build';

  @override
  Map<String, Object?> get _fields => {
    'bodyId': bodyId,
    'defId': defId,
    'depositResourceId': depositResourceId,
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
  /// Creates a create-route command.
  const CreateRouteCommand(
    super.factionId,
    this.fromBodyId,
    this.toBodyId,
    this.resourceId,
    this.ratePerSecond,
    this.cargoShips,
  );

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

  @override
  String get _cmd => 'createRoute';

  @override
  Map<String, Object?> get _fields => {
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'resourceId': resourceId,
    'ratePerSecond': ratePerSecond.toJson(),
    'cargoShips': cargoShips,
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

/// Why a command was rejected.
enum CommandError {
  /// The acting faction does not exist.
  unknownFaction,

  /// A named body does not exist.
  unknownBody,

  /// The named building does not exist.
  unknownBuilding,

  /// A named building type, resource or upgrade track does not exist.
  unknownDef,

  /// The faction does not own what the command touches.
  notOwner,

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

  /// The route does not exist, or its endpoints are not a valid pair.
  routeInvalid,

  /// The same timed work is already under way: a claim of the body, or an
  /// extra build slot on it.
  projectInProgress,
}

/// Outcome of applying a command.
sealed class CommandResult {
  const CommandResult();
}

/// The command was applied.
final class CommandOk extends CommandResult {
  /// Creates a success result.
  const CommandOk({this.createdId});

  /// Id of the building, route or project the command created, if any.
  final String? createdId;
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
