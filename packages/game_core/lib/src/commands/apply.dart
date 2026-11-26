import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../num/format.dart';
import '../sim/crew.dart';
import '../sim/market.dart';
import '../state/game_state.dart';
import 'command.dart';

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
    RemoveRouteCommand() => _removeRoute(s, c, faction, cmd),
    SellCommand() => _sell(s, c, faction, cmd),
    SetAutoSellCommand() => _setAutoSell(s, c, faction, cmd),
    ClaimBodyCommand() => _claim(s, c, faction, cmd),
    ExpandSlotsCommand() => _expandSlots(s, c, faction, cmd),
  };
}

/// Cost of the next level of track [t] on [b]: `baseCredits × growth^level`
/// credits.
///
/// Throws [ArgumentError] if the building's type has no such track.
Map<String, BigNum> upgradeCost(Content c, BuildingState b, UpgradeTrack t) {
  final curve = c.buildings[b.defId]!.upgrades[t];
  if (curve == null) {
    throw ArgumentError.value(t, 't', 'building ${b.defId} has no such track');
  }
  return {
    _credits:
        curve.baseCredits * BigNum.from(curve.growth).powInt(b.levels[t]!),
  };
}

/// Cost for [factionId] to claim its next body.
///
/// With `n` bodies owned: `claimBaseCredits × claimGrowth^(n−1)` credits plus
/// `n − 1` outpost kits, so the first claim costs credits only. Kits are
/// listed only when needed.
Map<String, BigNum> claimCost(GameState s, Content c, String factionId) {
  final owned = s.bodies.where((b) => b.ownerId == factionId).length;
  final extra = math.max(0, owned - 1);
  final r = c.rules;
  return {
    _credits: r.claimBaseCredits * BigNum.from(r.claimGrowth).powInt(extra),
    if (extra > 0) r.outpostKitResource: BigNum.from(extra),
  };
}

/// Buildings [body] can hold: its type's build slots plus the extra
/// slots bought for it.
int buildSlots(Content c, BodyState body) =>
    c.bodyTypes[body.typeId]!.buildSlots + body.extraSlots;

/// Cost of [body]'s next extra build slot:
/// `slotBaseCredits × slotGrowth^extraSlots` credits.
Map<String, BigNum> slotCost(Content c, BodyState body) => {
  _credits:
      c.rules.slotBaseCredits *
      BigNum.from(c.rules.slotGrowth).powInt(body.extraSlots),
};

/// Most crew [b], a building of type [def], can hold: base slots plus
/// `capacityCrewPerLevel` per capacity level. Buildings with no base slots
/// (warehouses) hold none.
int maxCrew(RulesDef r, BuildingDef def, BuildingState b) => def.crewSlots == 0
    ? 0
    : def.crewSlots + r.capacityCrewPerLevel * b.levels[UpgradeTrack.capacity]!;

CommandFailed _fail(CommandError e, String message) =>
    CommandFailed(e, message);

CommandFailed _unknownBody(String id) =>
    _fail(CommandError.unknownBody, 'There is no body $id');

/// The acting faction does not own [what], a display phrase such as a
/// body's name.
CommandFailed _notOwner(String what) =>
    _fail(CommandError.notOwner, "You don't own $what");

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

BodyState? _findBody(GameState s, String id) {
  for (final b in s.bodies) {
    if (b.id == id) return b;
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
CommandFailed? _checkCost(
  Content c,
  FactionState f,
  BodyState stockBody,
  Map<String, BigNum> cost,
) {
  for (final MapEntry(key: id, value: need) in cost.entries) {
    final have = id == _credits
        ? f.credits
        : stockBody.stock[id] ?? const BigNum.zero();
    if (have < need) {
      final what = id == _credits
          ? 'credits'
          : '${_resourceName(c, id)} on ${stockBody.name}';
      return _fail(
        CommandError.cannotAfford,
        'Needs ${formatNumber(need)} $what (you have ${formatNumber(have)})',
      );
    }
  }
  return null;
}

/// Takes [cost] from [f]'s credits and [stockBody]'s stock.
void _pay(FactionState f, BodyState stockBody, Map<String, BigNum> cost) {
  for (final MapEntry(key: id, value: amount) in cost.entries) {
    if (id == _credits) {
      f.credits = f.credits - amount;
    } else {
      stockBody.stock[id] = stockBody.stock[id]! - amount;
    }
  }
}

CommandResult _build(GameState s, Content c, FactionState f, BuildCommand cmd) {
  final body = _findBody(s, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  final def = c.buildings[cmd.defId];
  if (def == null) {
    return _fail(
      CommandError.unknownDef,
      'There is no building type ${cmd.defId}',
    );
  }
  if (body.ownerId != f.id) return _notOwner(body.name);
  if (body.buildings.length >= buildSlots(c, body)) {
    return _fail(
      CommandError.noBuildSlot,
      '${body.name} has no free build slot',
    );
  }
  String? deposit;
  if (def.kind == BuildingKind.extractor) {
    deposit = cmd.depositResourceId;
    if (deposit == null ||
        !def.extracts.contains(deposit) ||
        !body.deposits.any((d) => d.resourceId == deposit)) {
      return _fail(
        CommandError.depositMissing,
        deposit == null
            ? '${def.name} needs a deposit to mine'
            : "${def.name} can't mine ${_resourceName(c, deposit)} "
                  'on ${body.name}',
      );
    }
  }
  final short = _checkCost(c, f, body, def.buildCost);
  if (short != null) return short;

  _pay(f, body, def.buildCost);
  final b = BuildingState(
    id: s.newId('b'),
    defId: def.id,
    depositResourceId: deposit,
    crew: 0,
  );
  body.buildings.add(b);
  return CommandOk(createdId: b.id);
}

CommandResult _demolish(
  GameState s,
  Content c,
  FactionState f,
  DemolishCommand cmd,
) {
  final found = _findBuilding(s, cmd.buildingId);
  final missing = _checkOwnedBuilding(c, f, cmd.buildingId, found);
  if (missing != null) return missing;
  final (body, b) = found!;

  final paid = c.buildings[b.defId]!.buildCost[_credits];
  if (paid != null) f.credits = f.credits + paid.mulDouble(0.5);
  body.buildings.remove(b);
  return const CommandOk();
}

CommandResult _assignCrew(
  GameState s,
  Content c,
  FactionState f,
  AssignCrewCommand cmd,
) {
  final found = _findBuilding(s, cmd.buildingId);
  final missing = _checkOwnedBuilding(c, f, cmd.buildingId, found);
  if (missing != null) return missing;
  final (body, b) = found!;
  if (cmd.crew < 0) {
    return _fail(CommandError.invalidAmount, "Crew can't be negative");
  }
  final max = maxCrew(c.rules, c.buildings[b.defId]!, b);
  if (cmd.crew > max) {
    return _fail(
      CommandError.crewSlotsExceeded,
      '${_buildingName(c, body, b)} holds at most $max crew',
    );
  }
  final delta = cmd.crew - b.crew;
  final free = availableCrew(s, c, f.id);
  if (delta > 0 && free < delta) {
    return _fail(
      CommandError.crewUnavailable,
      'Needs $delta more crew (you have ${math.max(0, free)} free)',
    );
  }

  b.crew = cmd.crew;
  return const CommandOk();
}

CommandResult _upgrade(
  GameState s,
  Content c,
  FactionState f,
  UpgradeCommand cmd,
) {
  final found = _findBuilding(s, cmd.buildingId);
  final missing = _checkOwnedBuilding(c, f, cmd.buildingId, found);
  if (missing != null) return missing;
  final (body, b) = found!;
  final def = c.buildings[b.defId]!;
  if (!def.upgrades.containsKey(cmd.track)) {
    return _fail(
      CommandError.unknownDef,
      '${def.name} has no ${cmd.track.name} upgrade',
    );
  }
  final cost = upgradeCost(c, b, cmd.track);
  final short = _checkCost(c, f, body, cost);
  if (short != null) return short;

  _pay(f, body, cost);
  b.levels[cmd.track] = b.levels[cmd.track]! + 1;
  return const CommandOk();
}

CommandResult _createRoute(
  GameState s,
  Content c,
  FactionState f,
  CreateRouteCommand cmd,
) {
  final from = _findBody(s, cmd.fromBodyId);
  if (from == null) return _unknownBody(cmd.fromBodyId);
  final to = _findBody(s, cmd.toBodyId);
  if (to == null) return _unknownBody(cmd.toBodyId);
  if (!c.resources.containsKey(cmd.resourceId)) {
    return _unknownResource(cmd.resourceId);
  }
  if (from.ownerId != f.id) return _notOwner(from.name);
  if (to.ownerId != f.id) return _notOwner(to.name);
  if (from.id == to.id) {
    return _fail(
      CommandError.routeInvalid,
      'A route needs two different bodies',
    );
  }
  if (from.systemId != to.systemId) {
    return _fail(
      CommandError.routeInvalid,
      '${from.name} and ${to.name} are in different systems',
    );
  }
  if (cmd.cargoShips < 1) {
    return _fail(
      CommandError.invalidAmount,
      'A route needs at least one cargo ship',
    );
  }
  if (cmd.ratePerSecond <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Rate must be above 0');
  }
  final ships = {c.rules.cargoShipResource: BigNum.from(cmd.cargoShips)};
  final short = _checkCost(c, f, from, ships);
  if (short != null) return short;

  _pay(f, from, ships);
  final r = RouteState(
    id: s.newId('r'),
    ownerId: f.id,
    fromBodyId: from.id,
    toBodyId: to.id,
    resourceId: cmd.resourceId,
    ratePerSecond: cmd.ratePerSecond,
    cargoShips: cmd.cargoShips,
  );
  s.routes.add(r);
  return CommandOk(createdId: r.id);
}

CommandResult _removeRoute(
  GameState s,
  Content c,
  FactionState f,
  RemoveRouteCommand cmd,
) {
  final i = s.routes.indexWhere((r) => r.id == cmd.routeId);
  if (i < 0) {
    return _fail(CommandError.routeInvalid, 'There is no route ${cmd.routeId}');
  }
  final r = s.routes[i];
  if (r.ownerId != f.id) {
    return _notOwner(
      'the route from ${s.body(r.fromBodyId).name} '
      'to ${s.body(r.toBodyId).name}',
    );
  }

  final from = s.body(r.fromBodyId);
  final ships = c.rules.cargoShipResource;
  from.stock[ships] =
      (from.stock[ships] ?? const BigNum.zero()) + BigNum.from(r.cargoShips);
  s.routes.removeAt(i);
  return const CommandOk();
}

CommandResult _sell(GameState s, Content c, FactionState f, SellCommand cmd) {
  final body = _findBody(s, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (!c.resources.containsKey(cmd.resourceId)) {
    return _unknownResource(cmd.resourceId);
  }
  if (body.ownerId != f.id) return _notOwner(body.name);
  if (cmd.amount <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Amount must be above 0');
  }
  final held = body.stock[cmd.resourceId] ?? const BigNum.zero();
  if (held <= const BigNum.zero()) {
    return _fail(
      CommandError.invalidAmount,
      '${body.name} has no ${_resourceName(c, cmd.resourceId)} to sell',
    );
  }

  sell(s, c, f.id, body.id, cmd.resourceId, cmd.amount);
  return const CommandOk();
}

CommandResult _setAutoSell(
  GameState s,
  Content c,
  FactionState f,
  SetAutoSellCommand cmd,
) {
  final body = _findBody(s, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (!c.resources.containsKey(cmd.resourceId)) {
    return _unknownResource(cmd.resourceId);
  }
  if (body.ownerId != f.id) return _notOwner(body.name);
  final keep = cmd.keepAtLeast;
  if (keep != null && keep.isNegative) {
    return _fail(
      CommandError.invalidAmount,
      "The amount to keep can't be negative",
    );
  }

  final i = f.autoSell.indexWhere(
    (r) => r.bodyId == body.id && r.resourceId == cmd.resourceId,
  );
  if (keep == null) {
    if (i >= 0) f.autoSell.removeAt(i);
  } else if (i >= 0) {
    f.autoSell[i].keepAtLeast = keep;
  } else {
    f.autoSell.add(
      AutoSellRule(
        bodyId: body.id,
        resourceId: cmd.resourceId,
        keepAtLeast: keep,
      ),
    );
  }
  return const CommandOk();
}

CommandResult _claim(
  GameState s,
  Content c,
  FactionState f,
  ClaimBodyCommand cmd,
) {
  final target = _findBody(s, cmd.bodyId);
  if (target == null) return _unknownBody(cmd.bodyId);
  final source = _findBody(s, cmd.sourceBodyId);
  if (source == null) return _unknownBody(cmd.sourceBodyId);
  final owner = target.ownerId;
  if (owner != null) {
    return _fail(
      CommandError.alreadyOwned,
      owner == f.id
          ? 'You already own ${target.name}'
          : '${target.name} is already owned by ${_factionName(s, owner)}',
    );
  }
  if (source.ownerId != f.id) return _notOwner(source.name);
  final cost = claimCost(s, c, f.id);
  final short = _checkCost(c, f, source, cost);
  if (short != null) return short;

  _pay(f, source, cost);
  target.ownerId = f.id;
  return const CommandOk();
}

CommandResult _expandSlots(
  GameState s,
  Content c,
  FactionState f,
  ExpandSlotsCommand cmd,
) {
  final body = _findBody(s, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (body.ownerId != f.id) return _notOwner(body.name);
  final cost = slotCost(c, body);
  final short = _checkCost(c, f, body, cost);
  if (short != null) return short;

  _pay(f, body, cost);
  body.extraSlots++;
  return const CommandOk();
}
