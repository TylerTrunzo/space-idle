part of 'apply.dart';

// Buildings: building, demolishing, crewing and upgrading them, and what
// upgrades, slots and crew allow.

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

/// Buildings [body] can hold: its type's build slots plus the extra
/// slots bought for it.
int buildSlots(Content c, BodyState body) =>
    c.bodyTypes[body.typeId]!.buildSlots + body.extraSlots;

/// Most crew [b], a building of type [def], can hold: base slots plus
/// `capacityCrewPerLevel` per capacity level. Buildings with no base slots
/// (warehouses) hold none.
int maxCrew(RulesDef r, BuildingDef def, BuildingState b) => def.crewSlots == 0
    ? 0
    : def.crewSlots + r.capacityCrewPerLevel * b.levels[UpgradeTrack.capacity]!;

CommandResult _build(GameState s, Content c, FactionState f, BuildCommand cmd) {
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  final def = c.buildings[cmd.defId];
  if (def == null) {
    return _fail(
      CommandError.unknownDef,
      'There is no building type ${cmd.defId}. ${body.name} can build: '
      '${_buildable(c, body)}',
    );
  }
  if (body.ownerId != f.id) return _notYours(s, f, body);
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

  final crew = cmd.autoCrew
      ? math.min(def.crewSlots, availableCrew(s, c, f.id))
      : 0;
  _pay(f, body, def.buildCost);
  final b = BuildingState(
    id: s.newId('b'),
    defId: def.id,
    depositResourceId: deposit,
    crew: crew,
  );
  body.buildings.add(b);
  return CommandOk(
    createdId: b.id,
    outcome: Built(
      bodyId: body.id,
      buildingId: b.id,
      defId: def.id,
      crew: crew,
      spent: def.buildCost,
    ),
  );
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
  final refund = paid?.mulDouble(0.5);
  if (refund != null) f.credits = f.credits + refund;
  body.buildings.remove(b);
  return CommandOk(
    outcome: Demolished(
      bodyId: body.id,
      buildingId: b.id,
      defId: b.defId,
      gained: {_credits: ?refund},
    ),
  );
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
  final crew = crewTotals(s, c, f.id);
  final free = crew.free;
  if (delta > 0 && free < delta) {
    // Over-assigned, free crew stays 0 until that many are unassigned.
    final over = crew.overAssigned == 0
        ? ''
        : ': ${crew.overAssigned} crew are assigned beyond the '
              '${crew.supported} your housing supports';
    return _fail(
      CommandError.crewUnavailable,
      'Needs $delta more crew (you have $free free$over)',
    );
  }

  final previous = b.crew;
  b.crew = cmd.crew;
  return CommandOk(
    outcome: CrewAssigned(
      buildingId: b.id,
      previousCrew: previous,
      crew: b.crew,
    ),
  );
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
      CommandError.noSuchTrack,
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
  return CommandOk(
    outcome: Upgraded(
      bodyId: body.id,
      buildingId: b.id,
      track: cmd.track,
      level: b.levels[cmd.track]!,
      spent: cost,
    ),
  );
}
