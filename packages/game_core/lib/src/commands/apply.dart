import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../num/format.dart';
import '../sim/contracts.dart';
import '../sim/crew.dart';
import '../sim/market.dart';
import '../sim/megaprojects.dart';
import '../sim/production.dart';
import '../sim/projects.dart';
import '../sim/survey.dart';
import '../state/game_state.dart';
import '../state/save_codec.dart';
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
    SurveyCommand() => _survey(s, c, faction, cmd),
    ExpandSlotsCommand() => _expandSlots(s, c, faction, cmd),
    StartMegaprojectStageCommand() => _startMegaprojectStage(
      s,
      c,
      faction,
      cmd,
    ),
    DeliverContractCommand() => _deliverContract(s, c, faction, cmd),
    DiscardContractCommand() => _discardContract(s, c, faction, cmd),
  };
}

/// Cost of the next level of track [t] on [b]: `baseCredits × growth^level`
/// credits.
///
/// Speed and capacity on a building that has both share one level
/// counter: either costs its own `baseCredits × growth^(speed level +
/// capacity level)` (the two growths are equal; content validation checks
/// it). So each speed or capacity upgrade makes the next of either pricier
/// by the same step, and the order they are bought in changes the total by
/// at most the ratio of their bases. Efficiency keeps its own counter.
///
/// Throws [ArgumentError] if the building's type has no such track.
Map<String, BigNum> upgradeCost(Content c, BuildingState b, UpgradeTrack t) {
  final upgrades = c.buildings[b.defId]!.upgrades;
  final curve = upgrades[t];
  if (curve == null) {
    throw ArgumentError.value(t, 't', 'building ${b.defId} has no such track');
  }
  return {
    _credits:
        curve.baseCredits *
        BigNum.from(curve.growth).powInt(upgradeCounter(c, b, t)),
  };
}

/// The level count track [t]'s price on [b] grows with: the speed and
/// capacity levels together for either of those tracks when the building's
/// type has both ([upgradeCost]), else the track's own level.
int upgradeCounter(Content c, BuildingState b, UpgradeTrack t) {
  final upgrades = c.buildings[b.defId]!.upgrades;
  final shared =
      t != UpgradeTrack.efficiency &&
      upgrades.containsKey(UpgradeTrack.speed) &&
      upgrades.containsKey(UpgradeTrack.capacity);
  return shared
      ? b.levels[UpgradeTrack.speed]! + b.levels[UpgradeTrack.capacity]!
      : b.levels[t]!;
}

/// Why the next level of track [t] on [b] would do nothing, or null if it
/// would help (or the building's type has no such track).
///
/// A short phrase for the player, such as "its inputs are at the 25%
/// floor". A track is maxed at the highest level a save holds, and when
/// it cannot help: speed on a building that runs no recipe, efficiency on
/// one that uses no inputs or whose inputs are already at
/// `efficiencyFloor`, and capacity where it adds no crew slot, housing or
/// storage. `UpgradeCommand` refuses a maxed track.
String? upgradeMaxedReason(Content c, BuildingState b, UpgradeTrack t) {
  final def = c.buildings[b.defId]!;
  if (!def.upgrades.containsKey(t)) return null;
  final r = c.rules;
  final level = b.levels[t]!;
  if (level >= SaveCodec.maxLevel) {
    return 'it is at the highest level (${SaveCodec.maxLevel})';
  }
  switch (t) {
    case UpgradeTrack.speed:
      if (!runsRecipe(def)) return 'it runs no recipe';
    case UpgradeTrack.efficiency:
      if (!runsRecipe(def) || def.inputs.isEmpty) return 'it uses no inputs';
      if (efficiencyMultiplier(r, level + 1) >=
          efficiencyMultiplier(r, level)) {
        return 'its inputs are at the '
            '${(r.efficiencyFloor * 100).round()}% floor';
      }
    case UpgradeTrack.capacity:
      final addsCrew = def.crewSlots > 0 && r.capacityCrewPerLevel > 0;
      final addsHousing =
          def.kind == BuildingKind.habitat && r.capacityHousingPerLevel > 0;
      if (!addsCrew && !addsHousing && r.capacityStoragePerLevel == 0) {
        return 'it adds no crew slots, housing or storage here';
      }
  }
  return null;
}

/// Cost for [factionId] to claim its next body.
///
/// With `n` bodies owned or being claimed ([bodiesOwnedOrClaiming]):
/// `claimBaseCredits × claimGrowth^(n−1)` credits, plus
/// `claimKitsBase + claimKitsPerOwned × (n − 1)` outpost kits once more
/// than the home body is owned, so the first claim costs credits only and
/// each later one [RulesDef.claimKitsPerOwned] kits more. Kits are listed
/// only when needed. Claims under way count, so claims started side by
/// side cost what they would one after another.
Map<String, BigNum> claimCost(GameState s, Content c, String factionId) {
  final owned = bodiesOwnedOrClaiming(s, factionId);
  final extra = math.max(0, owned - 1);
  final r = c.rules;
  final kits = r.claimKitsBase + r.claimKitsPerOwned * extra;
  return {
    _credits: r.claimBaseCredits * BigNum.from(r.claimGrowth).powInt(extra),
    if (extra > 0 && kits > 0) r.outpostKitResource: BigNum.from(kits),
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

CommandResult _build(GameState s, Content c, FactionState f, BuildCommand cmd) {
  final body = _findBody(s, f, cmd.bodyId);
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
      String names(Iterable<String> ids) =>
          ids.map((id) => _resourceName(c, id)).join(', ');
      final has = body.deposits.isEmpty
          ? '${body.name} has no deposits'
          : '${body.name} has ${names(body.deposits.map((d) => d.resourceId))}';
      // Name what this extractor mines when the body has the deposit but
      // another kind of extractor works it.
      final mines = deposit != null && !def.extracts.contains(deposit)
          ? '; ${def.name} mines ${names(def.extracts)}'
          : '';
      return _fail(
        CommandError.depositMissing,
        deposit == null
            ? '${def.name} needs a deposit to mine ($has)'
            : "${def.name} can't mine ${_resourceName(c, deposit)} "
                  'on ${body.name} ($has$mines)',
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
      'Needs $delta more crew (you have $free free)',
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
  if (b.levels[cmd.track]! >= SaveCodec.maxLevel) {
    return _fail(
      CommandError.invalidAmount,
      '${_buildingName(c, body, b)} is at the highest ${cmd.track.name} '
      'level (${SaveCodec.maxLevel})',
    );
  }
  if (upgradeMaxedReason(c, b, cmd.track) case final why?) {
    return _fail(
      CommandError.invalidAmount,
      '${_buildingName(c, body, b)} is already at its best '
      '${cmd.track.name}: $why',
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
  final from = _findBody(s, f, cmd.fromBodyId);
  if (from == null) return _unknownBody(cmd.fromBodyId);
  final to = _findBody(s, f, cmd.toBodyId);
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
  final body = _findBody(s, f, cmd.bodyId);
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
  final body = _findBody(s, f, cmd.bodyId);
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
  final target = _findBody(s, f, cmd.bodyId);
  if (target == null) return _unknownBody(cmd.bodyId);
  final source = _findBody(s, f, cmd.sourceBodyId);
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
  final running = projectOn(s, ProjectKind.claim, target.id);
  if (running != null) {
    return _fail(
      CommandError.projectInProgress,
      running.factionId == f.id
          ? 'You are already claiming ${target.name} '
                '(${_left(s, running)} left)'
          : '${_factionName(s, running.factionId)} is already claiming '
                '${target.name}',
    );
  }
  if (source.ownerId != f.id) return _notOwner(source.name);
  final cost = claimCost(s, c, f.id);
  final short = _checkCost(c, f, source, cost);
  if (short != null) return short;

  final seconds = claimSeconds(s, c, f.id);
  _pay(f, source, cost);
  final p = startProject(s, f.id, ProjectKind.claim, target.id, seconds);
  return CommandOk(createdId: p.id);
}

CommandResult _survey(
  GameState s,
  Content c,
  FactionState f,
  SurveyCommand cmd,
) {
  BodyState? hidden;
  for (final b in s.bodies) {
    if (b.id == cmd.bodyId) hidden = b;
  }
  if (hidden == null) return _unknownBody(cmd.bodyId);
  final source = _findBody(s, f, cmd.sourceBodyId);
  if (source == null) return _unknownBody(cmd.sourceBodyId);
  if (hidden.surveyed) {
    return _fail(
      CommandError.alreadySurveyed,
      '${hidden.name} is already surveyed',
    );
  }
  if (projectOn(s, ProjectKind.survey, hidden.id) != null) {
    return _fail(
      CommandError.projectInProgress,
      'A survey of that body is already under way',
    );
  }
  if (source.ownerId != f.id) return _notOwner(source.name);
  final cost = surveyCost(c);
  final short = _checkCost(c, f, source, cost);
  if (short != null) return short;

  _pay(f, source, cost);
  final p = startProject(
    s,
    f.id,
    ProjectKind.survey,
    hidden.id,
    surveySeconds(c),
  );
  return CommandOk(createdId: p.id);
}

CommandResult _expandSlots(
  GameState s,
  Content c,
  FactionState f,
  ExpandSlotsCommand cmd,
) {
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (body.ownerId != f.id) return _notOwner(body.name);
  final running = projectOn(s, ProjectKind.expandSlots, body.id);
  if (running != null) {
    return _fail(
      CommandError.projectInProgress,
      '${body.name} is already getting an extra build slot '
      '(${_left(s, running)} left)',
    );
  }
  if (body.extraSlots >= SaveCodec.maxExtraSlots) {
    return _fail(
      CommandError.invalidAmount,
      '${body.name} already has the most extra build slots '
      '(${SaveCodec.maxExtraSlots})',
    );
  }
  final cost = slotCost(c, body);
  final short = _checkCost(c, f, body, cost);
  if (short != null) return short;

  _pay(f, body, cost);
  final p = startProject(
    s,
    f.id,
    ProjectKind.expandSlots,
    body.id,
    c.rules.expandSlotsSeconds,
  );
  return CommandOk(createdId: p.id);
}

CommandResult _startMegaprojectStage(
  GameState s,
  Content c,
  FactionState f,
  StartMegaprojectStageCommand cmd,
) {
  final def = c.megaprojects[cmd.megaprojectId];
  if (def == null) {
    return _fail(
      CommandError.unknownDef,
      'There is no megaproject ${cmd.megaprojectId}',
    );
  }
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (body.ownerId != f.id) return _notOwner(body.name);
  final host = def.hostBodyType;
  if (host != null && body.typeId != host) {
    return _fail(
      CommandError.wrongBodyType,
      '${def.name} is built on ${c.bodyTypes[host]!.name} bodies, and '
      '${body.name} is not one',
    );
  }
  final running = megaprojectStageOf(s, f.id, def.id);
  if (running != null) {
    return _fail(
      CommandError.projectInProgress,
      'A stage of ${def.name} is already under way '
      '(${_left(s, running)} left)',
    );
  }
  final level = f.megaprojectLevels[def.id] ?? 0;
  if (level >= SaveCodec.maxMegaprojectLevel) {
    return _fail(
      CommandError.invalidAmount,
      '${def.name} is at its highest level (${SaveCodec.maxMegaprojectLevel})',
    );
  }
  final cost = megaprojectCost(c, def, level);
  final short = _checkCost(c, f, body, cost);
  if (short != null) return short;

  _pay(f, body, cost);
  final p = startProject(
    s,
    f.id,
    ProjectKind.megaprojectStage,
    def.id,
    megaprojectStageSeconds(def, level),
  );
  return CommandOk(createdId: p.id);
}

/// [f]'s contract [id], or null if its board has none.
ContractState? _findContract(FactionState f, String id) {
  for (final k in f.contracts) {
    if (k.id == id) return k;
  }
  return null;
}

CommandFailed _unknownContract(String id) =>
    _fail(CommandError.unknownContract, 'You have no contract $id');

CommandResult _deliverContract(
  GameState s,
  Content c,
  FactionState f,
  DeliverContractCommand cmd,
) {
  final k = _findContract(f, cmd.contractId);
  if (k == null) return _unknownContract(cmd.contractId);
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (body.ownerId != f.id) return _notOwner(body.name);
  if (cmd.amount <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Amount must be above 0');
  }
  final held = body.stock[k.resourceId] ?? const BigNum.zero();
  if (held <= const BigNum.zero()) {
    return _fail(
      CommandError.invalidAmount,
      '${body.name} has no ${_resourceName(c, k.resourceId)} to deliver',
    );
  }

  final amount = cmd.amount.min(held).min(k.remaining);
  body.take(k.resourceId, amount);
  k.delivered = k.delivered + amount;
  if (k.delivered >= k.quantity) {
    k.delivered = k.quantity;
    f.credits = f.credits + k.rewardCredits;
    f.contractsCompleted++;
    f.contracts.remove(k);
    freeContractSlot(f, c, s.time);
  }
  return const CommandOk();
}

CommandResult _discardContract(
  GameState s,
  Content c,
  FactionState f,
  DiscardContractCommand cmd,
) {
  final k = _findContract(f, cmd.contractId);
  if (k == null) return _unknownContract(cmd.contractId);

  f.contracts.remove(k);
  freeContractSlot(f, c, s.time);
  return const CommandOk();
}

/// Time left on project [p], such as `25m`.
String _left(GameState s, ProjectState p) =>
    formatDuration(p.finishAt - s.time);
