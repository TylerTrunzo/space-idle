part of 'apply.dart';

// Timed work on bodies: claims, surveys and extra build slots.

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

/// Cost of [body]'s next extra build slot:
/// `slotBaseCredits × slotGrowth^extraSlots` credits.
Map<String, BigNum> slotCost(Content c, BodyState body) => {
  _credits:
      c.rules.slotBaseCredits *
      BigNum.from(c.rules.slotGrowth).powInt(body.extraSlots),
};

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
  if (source.ownerId != f.id) return _notYours(s, f, source);
  final cost = claimCost(s, c, f.id);
  final kit = c.rules.outpostKitResource;
  final short = _checkCost(
    c,
    f,
    source,
    cost,
    hint: (id) => id == kit ? _howToMake(c, kit) : null,
  );
  if (short != null) return short;

  final seconds = claimSeconds(s, c, f.id);
  _pay(f, source, cost);
  final p = startProject(s, f.id, ProjectKind.claim, target.id, seconds);
  return _started(source, p, cost, noKitsNeeded: !cost.containsKey(kit));
}

/// The next body to survey in [source]'s system: the first in content
/// order neither surveyed nor under survey, or the failure if none is.
(BodyState?, CommandFailed?) _nextToSurvey(
  GameState s,
  Content c,
  BodyState source,
) {
  var underWay = false;
  for (final b in s.bodies) {
    if (b.systemId != source.systemId || b.surveyed) continue;
    if (projectOn(s, ProjectKind.survey, b.id) == null) return (b, null);
    underWay = true;
  }
  final system = c.galaxy.systems
      .firstWhere((x) => x.id == source.systemId)
      .name;
  return (
    null,
    underWay
        ? _fail(
            CommandError.projectInProgress,
            'Every unsurveyed signal in $system is already being surveyed',
          )
        : _fail(
            CommandError.alreadySurveyed,
            'There is nothing left to survey in $system',
          ),
  );
}

CommandResult _survey(
  GameState s,
  Content c,
  FactionState f,
  SurveyCommand cmd,
) {
  final id = cmd.bodyId;
  BodyState? hidden;
  for (final b in s.bodies) {
    if (b.id == id) hidden = b;
  }
  if (id != null && hidden == null) return _unknownBody(id);
  final source = _findBody(s, f, cmd.sourceBodyId);
  if (source == null) return _unknownBody(cmd.sourceBodyId);
  if (hidden == null) {
    if (source.ownerId != f.id) return _notYours(s, f, source);
    final (next, none) = _nextToSurvey(s, c, source);
    if (next == null) return none!;
    hidden = next;
  }
  // The system first: a body out of reach is told nothing more about.
  if (hidden.systemId != source.systemId) {
    return _fail(
      CommandError.routeInvalid,
      "Survey drones from ${source.name} can't reach that body: it is in "
      'another system',
    );
  }
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
  if (source.ownerId != f.id) return _notYours(s, f, source);
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
  return _started(source, p, cost);
}

/// The result of starting project [p], paid [cost] from [payer].
CommandOk _started(
  BodyState payer,
  ProjectState p,
  Map<String, BigNum> cost, {
  bool noKitsNeeded = false,
}) => CommandOk(
  createdId: p.id,
  outcome: ProjectStarted(
    bodyId: payer.id,
    projectId: p.id,
    kind: p.kind,
    targetId: p.targetId,
    finishAt: p.finishAt,
    noKitsNeeded: noKitsNeeded,
    spent: cost,
  ),
);

CommandResult _expandSlots(
  GameState s,
  Content c,
  FactionState f,
  ExpandSlotsCommand cmd,
) {
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (body.ownerId != f.id) return _notYours(s, f, body);
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
  return _started(body, p, cost);
}
