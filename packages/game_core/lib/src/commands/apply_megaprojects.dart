part of 'apply.dart';

// Megaproject stages: deliveries toward them and starting them.

CommandResult _startMegaprojectStage(
  GameState s,
  Content c,
  FactionState f,
  StartMegaprojectStageCommand cmd,
) {
  final failed = _checkMegaproject(s, c, f, cmd.megaprojectId, cmd.bodyId);
  if (failed != null) return failed;
  final def = c.megaprojects[cmd.megaprojectId]!;
  final body = _findBody(s, f, cmd.bodyId)!;
  final owed = megaprojectRemaining(s, c, f.id, def);
  final short = _checkCost(c, f, body, owed);
  if (short != null) return short;

  _pay(f, body, owed);
  f.megaprojectProgress[def.id] = Map.of(
    megaprojectCost(c, def, megaprojectDeliveryLevel(s, f.id, def)),
  );
  return _delivered(s, c, f, def, body, owed);
}

CommandResult _deliverToMegaproject(
  GameState s,
  Content c,
  FactionState f,
  DeliverToMegaprojectCommand cmd,
) {
  final failed = _checkMegaproject(s, c, f, cmd.megaprojectId, cmd.bodyId);
  if (failed != null) return failed;
  final def = c.megaprojects[cmd.megaprojectId]!;
  final body = _findBody(s, f, cmd.bodyId)!;
  if (cmd.amounts.isEmpty) {
    return _fail(CommandError.invalidAmount, 'Nothing to deliver');
  }
  final cost = megaprojectCost(c, def, megaprojectDeliveryLevel(s, f.id, def));
  final owed = megaprojectRemaining(s, c, f.id, def);
  for (final MapEntry(key: id, value: amount) in cmd.amounts.entries) {
    if (id != _credits && !c.resources.containsKey(id)) {
      return _fail(CommandError.unknownDef, 'There is no resource $id');
    }
    if (!cost.containsKey(id)) {
      return _fail(
        CommandError.invalidAmount,
        '${def.name} takes no ${_costName(c, id)}',
      );
    }
    if (amount <= const BigNum.zero()) {
      return _fail(CommandError.invalidAmount, 'Amounts must be above 0');
    }
    if (amount < _oneUnit) return _wholeUnitsOnly();
  }
  final wanted = [
    for (final id in cmd.amounts.keys)
      if (owed.containsKey(id)) id,
  ];
  if (wanted.isEmpty) {
    final names = [for (final id in cmd.amounts.keys) _costName(c, id)];
    return _fail(
      CommandError.invalidAmount,
      '${def.name} already has all the ${_and(names)} its next stage needs',
    );
  }
  final take = <String, BigNum>{};
  var someHeld = false;
  for (final id in wanted) {
    final held = id == _credits
        ? f.credits
        : body.stock[id] ?? const BigNum.zero();
    // Whole units only; what is owed is whole, so it stays whole.
    final n = cmd.amounts[id]!.min(owed[id]!).min(held).floor();
    if (n > const BigNum.zero()) take[id] = n;
    if (held > const BigNum.zero()) someHeld = true;
  }
  if (take.isEmpty) {
    final names = [for (final id in wanted) _costName(c, id)];
    final where = wanted.every((id) => id == _credits)
        ? ''
        : ' on ${body.name}';
    return _fail(
      CommandError.cannotAfford,
      someHeld
          ? 'There is less than one whole ${_or(names)}$where to deliver'
          : 'There is no ${_or(names)}$where to deliver',
    );
  }

  _pay(f, body, take);
  final got = f.megaprojectProgress.putIfAbsent(def.id, () => {});
  for (final MapEntry(key: id, value: n) in take.entries) {
    final total = (got[id] ?? const BigNum.zero()) + n;
    // What is owed and what is taken came from the same numbers, so a
    // full delivery lands on the cost exactly, float residue aside.
    got[id] = take[id] == owed[id] ? cost[id]! : total.min(cost[id]!);
  }
  return _delivered(s, c, f, def, body, take);
}

/// The result of [f] handing [delivered] from [body] to [def]'s stage
/// being paid for. Once that is paid in full, the stage starts now, or,
/// while one is under way, waits in `megaprojectProgress` and starts when
/// that one completes (`stepProjects`).
CommandOk _delivered(
  GameState s,
  Content c,
  FactionState f,
  MegaprojectDef def,
  BodyState body,
  Map<String, BigNum> delivered,
) {
  final level = megaprojectDeliveryLevel(s, f.id, def) + 1;
  final remaining = megaprojectRemaining(s, c, f.id, def);
  final running = megaprojectStageOf(s, f.id, def.id);
  if (remaining.isNotEmpty || running != null) {
    return CommandOk(
      outcome: MegaprojectDelivered(
        bodyId: body.id,
        megaprojectId: def.id,
        level: level,
        delivered: delivered,
        remaining: remaining,
        queued: remaining.isEmpty,
        finishAt: remaining.isEmpty ? running!.finishAt : null,
      ),
    );
  }
  final p = _startStage(s, f, def);
  return CommandOk(
    createdId: p.id,
    outcome: MegaprojectDelivered(
      bodyId: body.id,
      megaprojectId: def.id,
      level: level,
      delivered: delivered,
      remaining: remaining,
      stageStarted: true,
      projectId: p.id,
      finishAt: p.finishAt,
    ),
  );
}

/// Why a stage command on megaproject [megaprojectId] from body [bodyId]
/// cannot go ahead, or null if it can: an unknown megaproject or body, a
/// body [f] does not own, a megaproject not open yet, a host body type [f]
/// owns none of, the next
/// stage already paid for while one is under way, or the highest level
/// reached.
CommandFailed? _checkMegaproject(
  GameState s,
  Content c,
  FactionState f,
  String megaprojectId,
  String bodyId,
) {
  final def = c.megaprojects[megaprojectId];
  if (def == null) {
    return _fail(
      CommandError.unknownDef,
      'There is no megaproject $megaprojectId',
    );
  }
  final body = _findBody(s, f, bodyId);
  if (body == null) return _unknownBody(bodyId);
  if (body.ownerId != f.id) return _notYours(s, f, body);
  if (megaprojectLockedBy(s, c, f.id, def) case (
    :final megaprojectId,
    :final level,
  )) {
    final need = c.megaprojects[megaprojectId]!.name;
    return _fail(
      CommandError.megaprojectLocked,
      '${def.name} opens at $need level $level (you have level '
      '${f.megaprojectLevels[megaprojectId] ?? 0})',
    );
  }
  final host = def.hostBodyType;
  if (host != null &&
      !s.bodies.any((b) => b.ownerId == f.id && b.typeId == host)) {
    final name = c.bodyTypes[host]!.name;
    return _fail(
      CommandError.wrongBodyType,
      '${def.name} is built at ${_article(name).toLowerCase()} $name, and '
      'you own none',
    );
  }
  final level = megaprojectDeliveryLevel(s, f.id, def);
  final running = megaprojectStageOf(s, f.id, def.id);
  if (level >= SaveCodec.maxMegaprojectLevel) {
    // While the last stage runs, the level is not reached yet: say so.
    return running != null
        ? _fail(
            CommandError.projectInProgress,
            '${def.name} level $level, its highest, is under way '
            '(${_left(s, running)} left); there is nothing more to deliver',
          )
        : _fail(
            CommandError.invalidAmount,
            '${def.name} is at its highest level '
            '(${SaveCodec.maxMegaprojectLevel})',
          );
  }
  if (running != null && megaprojectStageQueued(s, c, f.id, def)) {
    return _fail(
      CommandError.projectInProgress,
      '${def.name} level ${level + 1} is paid for; it starts when level '
      '$level is done (${_left(s, running)} left)',
    );
  }
  return null;
}

/// Starts the timer of [def]'s next stage for [f], everything for it
/// delivered, and clears what was delivered toward it.
ProjectState _startStage(GameState s, FactionState f, MegaprojectDef def) {
  f.megaprojectProgress.remove(def.id);
  return startProject(
    s,
    f.id,
    ProjectKind.megaprojectStage,
    def.id,
    megaprojectStageSeconds(def, f.megaprojectLevels[def.id] ?? 0),
  );
}

CommandResult _setMegaprojectAuto(
  GameState s,
  Content c,
  FactionState f,
  SetMegaprojectAutoCommand cmd,
) {
  final def = c.megaprojects[cmd.megaprojectId];
  if (def == null) {
    return _fail(
      CommandError.unknownDef,
      'There is no megaproject ${cmd.megaprojectId}',
    );
  }
  if (cmd.creditWeight < MegaprojectAuto.minCreditWeight ||
      cmd.creditWeight > MegaprojectAuto.maxCreditWeight) {
    return _fail(
      CommandError.invalidAmount,
      'A credit weight must be ${MegaprojectAuto.minCreditWeight} to '
      '${MegaprojectAuto.maxCreditWeight}',
    );
  }
  f.megaprojectAutoSet.add(def.id);
  if (cmd.goods == GoodsFeedMode.off && !cmd.credits) {
    f.megaprojectAuto.remove(def.id);
  } else {
    // A stage fed near ready stays fed while goods stay near ready.
    final was = f.megaprojectAuto[def.id];
    f.megaprojectAuto[def.id] = MegaprojectAuto(
      goods: cmd.goods,
      credits: cmd.credits,
      creditWeight: cmd.creditWeight,
      feedingLevel:
          cmd.goods == GoodsFeedMode.nearReady &&
              was?.goods == GoodsFeedMode.nearReady
          ? was?.feedingLevel
          : null,
    );
  }
  return CommandOk(
    outcome: MegaprojectAutoSet(
      megaprojectId: def.id,
      goods: cmd.goods,
      credits: cmd.credits,
      creditWeight: cmd.creditWeight,
    ),
  );
}

CommandResult _setAutoPayReserve(
  GameState s,
  Content c,
  FactionState f,
  SetAutoPayReserveCommand cmd,
) {
  if (cmd.credits < const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'A reserve must be 0 or more');
  }
  f.autoPayReserve = cmd.credits;
  return CommandOk(outcome: AutoPayReserveSet(reserve: cmd.credits));
}
