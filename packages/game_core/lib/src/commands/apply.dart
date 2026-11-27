import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../num/format.dart';
import '../sim/contracts.dart';
import '../sim/crew.dart';
import '../sim/logistics.dart';
import '../sim/market.dart';
import '../sim/megaprojects.dart';
import '../sim/production.dart';
import '../sim/projects.dart';
import '../sim/survey.dart';
import '../state/game_state.dart';
import '../state/save_codec.dart';
import 'command.dart';
import 'outcome.dart';

part 'apply_build.dart';
part 'apply_logistics.dart';
part 'apply_projects.dart';
part 'apply_megaprojects.dart';
part 'apply_contracts.dart';

/// Key of the credits entry in a cost map; every other key is a resource id.
const _credits = 'credits';

/// Validates [cmd] against [s] and the acting faction, then applies it.
///
/// Every check runs before anything is changed, so a [CommandFailed] result
/// always leaves [s] exactly as it was.
CommandResult applyCommand(GameState s, Content c, Command cmd) {
  final faction = _findFaction(s, cmd.factionId);
  if (faction == null) {
    return _fail(
      CommandError.unknownFaction,
      'There is no faction ${cmd.factionId}',
    );
  }
  return switch (cmd) {
    BuildCommand() => _build(s, c, faction, cmd),
    DemolishCommand() => _demolish(s, c, faction, cmd),
    AssignCrewCommand() => _assignCrew(s, c, faction, cmd),
    UpgradeCommand() => _upgrade(s, c, faction, cmd),
    CreateRouteCommand() => _createRoute(s, c, faction, cmd),
    UpdateRouteCommand() => _updateRoute(s, c, faction, cmd),
    MoveShipsCommand() => _moveShips(s, c, faction, cmd),
    RemoveRouteCommand() => _removeRoute(s, c, faction, cmd),
    SellCommand() => _sell(s, c, faction, cmd),
    SetAutoSellCommand() => _setAutoSell(s, c, faction, cmd),
    ClaimBodyCommand() => _claim(s, c, faction, cmd),
    SurveyCommand() => _survey(s, c, faction, cmd),
    ExpandSlotsCommand() => _expandSlots(s, c, faction, cmd),
    StartMegaprojectStageCommand() => _startMegaprojectStage(
      s,
      c,
      faction,
      cmd,
    ),
    DeliverToMegaprojectCommand() => _deliverToMegaproject(s, c, faction, cmd),
    SetMegaprojectAutoCommand() => _setMegaprojectAuto(s, c, faction, cmd),
    DeliverContractCommand() => _deliverContract(s, c, faction, cmd),
    DiscardContractCommand() => _discardContract(s, c, faction, cmd),
  };
}

CommandFailed _fail(CommandError e, String message) =>
    CommandFailed(e, message);

/// One unit: the least a delivery to a contract or megaproject moves, as
/// deliveries move whole units.
final _oneUnit = BigNum.from(1);

/// The failure for a delivery asking for less than [_oneUnit].
CommandFailed _wholeUnitsOnly() => _fail(
  CommandError.invalidAmount,
  'Deliver at least 1 unit: deliveries move whole units',
);

CommandFailed _unknownBody(String id) =>
    _fail(CommandError.unknownBody, 'There is no body $id');

/// The acting faction does not own [what], a display phrase such as a
/// body's name.
CommandFailed _notOwner(String what) =>
    _fail(CommandError.notOwner, "You don't own $what");

/// The failure for a command on [body], which [f] does not own:
/// `stillClaiming` while [f]'s claim of it is under way, such as "Brine is
/// still being claimed (25m left)", else `notOwner`.
CommandFailed _notYours(GameState s, FactionState f, BodyState body) {
  final claim = projectOn(s, ProjectKind.claim, body.id);
  if (claim != null && claim.factionId == f.id) {
    return _fail(
      CommandError.stillClaiming,
      '${body.name} is still being claimed (${_left(s, claim)} left)',
    );
  }
  return _notOwner(body.name);
}

CommandFailed _unknownResource(String id) =>
    _fail(CommandError.unknownDef, 'There is no resource $id');

/// Display name of faction [id], or the id itself if there is none.
String _factionName(GameState s, String id) => _findFaction(s, id)?.name ?? id;

/// Display name of resource [id], or the id itself if there is none.
String _resourceName(Content c, String id) => c.resources[id]?.name ?? id;

/// "Smelter on Kora": building [b] by its type's display name, on [body].
String _buildingName(Content c, BodyState body, BuildingState b) =>
    '${c.buildings[b.defId]!.name} on ${body.name}';

FactionState? _findFaction(GameState s, String id) {
  for (final f in s.factions) {
    if (f.id == id) return f;
  }
  return null;
}

/// Body [id] if it is in sight of [f] ([isVisible]), else null: a hidden
/// body nothing has surveyed is `unknownBody`.
BodyState? _findBody(GameState s, FactionState f, String id) {
  for (final b in s.bodies) {
    if (b.id == id) return isVisible(s, b, f.id) ? b : null;
  }
  return null;
}

(BodyState, BuildingState)? _findBuilding(GameState s, String id) {
  for (final body in s.bodies) {
    for (final b in body.buildings) {
      if (b.id == id) return (body, b);
    }
  }
  return null;
}

/// The failure if building [id], as [found] by [_findBuilding], is missing or
/// stands on a body [f] does not own, else null.
CommandFailed? _checkOwnedBuilding(
  Content c,
  FactionState f,
  String id,
  (BodyState, BuildingState)? found,
) {
  if (found == null) {
    return _fail(CommandError.unknownBuilding, 'There is no building $id');
  }
  final (body, b) = found;
  if (body.ownerId != f.id) {
    return _notOwner('the ${_buildingName(c, body, b)}');
  }
  return null;
}

/// The failure if [f] and [stockBody] cannot cover [cost], else null.
///
/// [hint], when given, may add a sentence about the first cost item short,
/// by its key, such as how to make it.
CommandFailed? _checkCost(
  Content c,
  FactionState f,
  BodyState stockBody,
  Map<String, BigNum> cost, {
  String? Function(String id)? hint,
}) {
  for (final MapEntry(key: id, value: need) in cost.entries) {
    final have = id == _credits
        ? f.credits
        : stockBody.stock[id] ?? const BigNum.zero();
    if (have < need) {
      final what = id == _credits
          ? 'credits'
          : '${_resourceName(c, id)} on ${stockBody.name}';
      final more = switch (hint?.call(id)) {
        final h? => '. $h',
        null => '',
      };
      return _fail(
        CommandError.cannotAfford,
        'Needs ${formatNumber(need)} $what (you have ${formatNumber(have)})'
        '$more',
      );
    }
  }
  return null;
}

/// "A" or "An", to start a sentence about [word].
String _article(String word) => 'AEIOUaeiou'.contains(word[0]) ? 'An' : 'A';

/// [items] as "a, b and c".
String _and(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

/// "6 Hull Plate": [units] of resource [id].
String _units(Content c, double units, String id) =>
    '${formatNumber(BigNum.from(units))} ${_resourceName(c, id)}';

/// What makes [resourceId], one sentence per building type whose recipe
/// outputs it, such as "An Outpost Kit Assembler makes 1 Outpost Kit from
/// 6 Hull Plate, 12 Fuel and 6 Circuit"; null if nothing does.
String? _howToMake(Content c, String resourceId) {
  final ways = <String>[];
  for (final d in c.buildings.values) {
    final out = d.outputs[resourceId];
    if (d.kind == BuildingKind.extractor || out == null) continue;
    final inputs = [
      for (final MapEntry(key: id, value: v) in d.inputs.entries)
        _units(c, v, id),
    ];
    ways.add(
      '${_article(d.name)} ${d.name} makes ${_units(c, out, resourceId)}'
      '${inputs.isEmpty ? '' : ' from ${_and(inputs)}'}',
    );
  }
  return ways.isEmpty ? null : ways.join('. ');
}

/// The building types [body] can hold, with what each costs, as "Mine
/// (mine, 100 credits), Depot (depot, 800 credits and 50 Steel)", in
/// content order: every one but an extractor that can mine none of the
/// body's deposits.
String _buildable(Content c, BodyState body) => [
  for (final d in c.buildings.values)
    if (d.kind != BuildingKind.extractor ||
        body.deposits.any((x) => d.extracts.contains(x.resourceId)))
      '${d.name} (${d.id}, ${_costText(c, d.buildCost)})',
].join(', ');

/// [cost] as "800 credits and 50 Steel", in its order; "nothing" when
/// empty.
String _costText(Content c, Map<String, BigNum> cost) => cost.isEmpty
    ? 'nothing'
    : _and([
        for (final MapEntry(key: id, value: v) in cost.entries)
          '${formatNumber(v)} ${_costName(c, id)}',
      ]);

/// Takes [cost] from [f]'s credits and [stockBody]'s stock, snapping float
/// residue below zero to zero ([takeFrom]).
void _pay(FactionState f, BodyState stockBody, Map<String, BigNum> cost) {
  for (final MapEntry(key: id, value: amount) in cost.entries) {
    if (id == _credits) {
      f.credits = takeFrom(f.credits, amount);
    } else {
      stockBody.take(id, amount);
    }
  }
}

/// Display name of a cost key: "credits" or the resource's name.
String _costName(Content c, String id) =>
    id == _credits ? 'credits' : _resourceName(c, id);

/// [items] as "a, b or c".
String _or(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} or ${items.last}';

/// Time left on project [p], such as `25m`.
String _left(GameState s, ProjectState p) =>
    formatDuration(p.finishAt - s.time);
