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
    // Habitats built in the same batch house no one until they run: the
    // next tick fills what is still empty (`fillAwaitingCrew`).
    awaitingCrew: cmd.autoCrew && crew < def.crewSlots,
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
  // Crew set by hand is the player's choice: the building no longer waits
  // for crew whatever it now holds.
  setBuildingCrew(b, c.buildings[b.defId]!, cmd.crew);
  b.awaitingCrew = false;
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
  // A capacity level's new crew slots fill from the free crew, as a build
  // with autoCrew does; base slots left empty stay so.
  final added = cmd.track == UpgradeTrack.capacity
      ? math.max(
          0,
          [
            c.rules.capacityCrewPerLevel,
            availableCrew(s, c, f.id),
            maxCrew(c.rules, def, b) - b.crew,
          ].reduce(math.min),
        )
      : 0;
  setBuildingCrew(b, def, b.crew + added);
  return CommandOk(
    outcome: Upgraded(
      bodyId: body.id,
      buildingId: b.id,
      track: cmd.track,
      level: b.levels[cmd.track]!,
      spent: cost,
      crewAdded: added,
    ),
  );
}

/// A level [_buyUpgrades] could buy next: track [track] of [b] on [body]
/// at [cost] credits.
typedef _Offer = ({
  BigNum cost,
  BodyState body,
  BuildingState b,
  UpgradeTrack track,
});

/// Cheapest first, ties by building id, then track order.
int _byCost(_Offer x, _Offer y) {
  final byCost = x.cost.compareTo(y.cost);
  if (byCost != 0) return byCost;
  final byId = x.b.id.compareTo(y.b.id);
  return byId != 0 ? byId : x.track.index.compareTo(y.track.index);
}

CommandResult _buyUpgrades(
  GameState s,
  Content c,
  FactionState f,
  BuyUpgradesCommand cmd,
) {
  if (cmd.budget < const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'The budget must be at least 0');
  }
  if (cmd.maxPurchases < 1 ||
      cmd.maxPurchases > BuyUpgradesCommand.defaultMaxPurchases) {
    return _fail(
      CommandError.invalidAmount,
      'Buy from 1 to ${BuyUpgradesCommand.defaultMaxPurchases} levels at '
      'a time',
    );
  }
  final limit = cmd.budget.min(f.credits);
  final offers = SplayTreeSet<_Offer>(_byCost);
  // Each building's offers in [offers], to replace once a level is bought.
  final byBuilding = <BuildingState, List<_Offer>>{};
  void offer(BodyState body, BuildingState b) {
    final mine = byBuilding[b] ??= [];
    offers.removeAll(mine);
    mine.clear();
    for (final t in c.buildings[b.defId]!.upgrades.keys) {
      if (upgradeMaxedReason(c, b, t) != null) continue;
      final o = (
        cost: upgradeCost(c, b, t)[_credits]!,
        body: body,
        b: b,
        track: t,
      );
      mine.add(o);
      offers.add(o);
    }
  }

  for (final body in s.bodies) {
    if (body.ownerId != f.id) continue;
    for (final b in body.buildings) {
      offer(body, b);
    }
  }
  final bought = <(BuildingState, UpgradeTrack), UpgradePurchase>{};
  var total = const BigNum.zero();
  var count = 0;
  UpgradeBuyStop? stop;
  while (stop == null) {
    if (offers.isEmpty) {
      stop = UpgradeBuyStop.nothingToBuy;
    } else if (count >= cmd.maxPurchases) {
      stop = UpgradeBuyStop.maxPurchases;
    } else if (total + offers.first.cost > limit ||
        // The upgrade's own test, on the credits left: summed costs and
        // credits paid down can differ by an ulp at the budget's edge.
        f.credits < offers.first.cost) {
      stop = UpgradeBuyStop.budget;
    } else {
      final o = offers.first;
      final r = _upgrade(s, c, f, UpgradeCommand(f.id, o.b.id, o.track));
      // The offer passed every check the command makes, so it buys; were
      // it refused all the same, the levels bought stand and the budget
      // is what stopped it.
      if (r case CommandOk(outcome: final Upgraded up)) {
        total = total + o.cost;
        count++;
        final key = (o.b, o.track);
        final was = bought[key];
        bought[key] = UpgradePurchase(
          bodyId: o.body.id,
          buildingId: o.b.id,
          track: o.track,
          levels: (was?.levels ?? 0) + 1,
          level: up.level,
          cost: (was?.cost ?? const BigNum.zero()) + o.cost,
          crewAdded: (was?.crewAdded ?? 0) + up.crewAdded,
        );
        offer(o.body, o.b);
      } else {
        stop = UpgradeBuyStop.budget;
      }
    }
  }
  return CommandOk(
    outcome: UpgradesBought(
      purchases: bought.values.toList(),
      total: total,
      stop: stop,
      nextCost: offers.isEmpty ? null : offers.first.cost,
    ),
  );
}
