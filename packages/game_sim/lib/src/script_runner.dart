import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';

/// Command names that are not game commands.
const _metaCommands = {
  'advance',
  'away',
  'report',
  'state',
  'save',
  'load',
  'costs',
};

/// Command names `Command.fromJson` understands.
const _gameCommands = {
  'build',
  'demolish',
  'assignCrew',
  'upgrade',
  'createRoute',
  'updateRoute',
  'moveShips',
  'removeRoute',
  'sell',
  'setAutoSell',
  'claimBody',
  'survey',
  'expandSlots',
  'startMegaprojectStage',
  'deliverToMegaproject',
  'deliverContract',
  'discardContract',
};

/// Lowest resource tier whose stock `state` shows in whole units.
const int _wholeUnitTier = 2;

/// [v] rounded down to a whole number, when it is small enough to have a
/// fractional part.
BigNum _floor(BigNum v) {
  final d = v.toDouble();
  return d.abs() < 1e15 ? BigNum.from(d.floorToDouble()) : v;
}

/// A number as JSON: the raw `BigNum.toJson()` value and a display string.
Map<String, Object?> _num(BigNum v) => {
  'value': v.toJson(),
  'display': formatNumber(v),
};

Map<String, Object?> _nums(Map<String, BigNum> m) => {
  for (final e in m.entries) e.key: _num(e.value),
};

/// A bottleneck as JSON. With [awayFrom], the start of an absence, one
/// first seen before it also says since when it has been going on.
Map<String, Object?> _bottleneck(Bottleneck n, {double? awayFrom}) => {
  'kind': n.kind.name,
  'bodyId': n.bodyId,
  'buildingId': n.buildingId,
  'resourceId': n.resourceId,
  'runFraction': n.runFraction,
  'message': n.message,
  'firstSeenAt': n.firstSeenAt,
  'lostCreditsPerHour': switch (n.lostCreditsPerHour) {
    final v? => _num(v),
    null => null,
  },
  if (awayFrom != null && n.firstSeenAt < awayFrom)
    'ongoing': 'ongoing since ${(n.firstSeenAt / 3600).toStringAsFixed(1)}h',
};

Map<String, Object?> _fail(String error, String message) => {
  'ok': false,
  'error': error,
  'message': message,
};

/// Runs JSON command lines against a game.
final class ScriptRunner {
  /// Creates a runner that plays [state] with [engine].
  ScriptRunner(this.engine, this.state);

  /// The engine every command goes through.
  final GameEngine engine;

  /// The game being played; replaced by a `load` command.
  GameState state;

  /// Handles one decoded line and returns its JSON-ready result: `ok: true`
  /// plus details, or `ok: false` with `error` and `message`. Never throws.
  Map<String, Object?> handle(Map<String, Object?> line) {
    final cmd = line['cmd'];
    if (cmd is! String) {
      return _fail('badCommand', 'missing string field "cmd"');
    }
    try {
      if (_metaCommands.contains(cmd)) return _meta(cmd, line);
      if (!_gameCommands.contains(cmd)) {
        return _fail('unknownCommand', 'unknown command "$cmd"');
      }
      return _game(line);
    } on FormatException catch (e) {
      return _fail('badCommand', e.message);
    } on FileSystemException catch (e) {
      return _fail('ioError', '${e.message} ${e.path ?? ''}'.trim());
    }
  }

  /// Parses [text] as a JSON object line and handles it; text that is not a
  /// JSON object gives `badJson` and leaves the game untouched.
  Map<String, Object?> handleLine(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return _fail('badJson', e.message);
    }
    if (decoded is! Map<String, Object?>) {
      return _fail('badJson', 'line is not a JSON object');
    }
    return handle(decoded);
  }

  Map<String, Object?> _game(Map<String, Object?> line) {
    final j = {...line};
    j['factionId'] ??= _player.id;
    final cmd = Command.fromJson(j);
    switch (engine.apply(state, cmd)) {
      case CommandFailed(:final error, :final message):
        return _fail(error.name, message);
      case CommandOk(:final createdId, :final outcome):
        // `applyCommand` gives every success an outcome.
        final o = outcome!;
        String key(String id) => id == 'credits' ? id : '${o.bodyId}/$id';
        Map<String, BigNum> keyed(Map<String, BigNum> m) => {
          for (final MapEntry(key: id, value: v) in m.entries)
            if (!v.isZero) key(id): v,
        };
        final spent = keyed(o.spent);
        final gained = keyed(o.gained);
        return {
          'ok': true,
          'createdId': ?createdId,
          'message': ?_message(cmd, o),
          if (spent.isNotEmpty) 'spent': _nums(spent),
          if (gained.isNotEmpty) 'gained': _nums(gained),
        };
    }
  }

  /// "Smelter on Kora (b3)": building [buildingId], a [defId], on [bodyId].
  String _describe(String defId, String bodyId, String buildingId) =>
      '${engine.content.buildings[defId]!.name} on '
      '${state.body(bodyId).name} ($buildingId)';

  /// Credits and goods as "5K credits and 20 Steel", in [m]'s order.
  String _list(Map<String, BigNum> m) => [
    for (final MapEntry(key: k, value: v) in m.entries)
      k == 'credits'
          ? '${formatNumber(v)} credits'
          : '${formatNumber(v)} ${engine.content.resources[k]!.name}',
  ].join(' and ');

  /// Game seconds from now until [at], as "2h 5m".
  String _until(double at) => formatDuration(at - state.time);

  /// A sentence on what [cmd] did, from its outcome [o]; null for
  /// crew, upgrades, sales, auto-sell rules and closed routes, whose
  /// `spent` and `gained` say it all.
  String? _message(Command cmd, CommandOutcome o) {
    final c = engine.content;
    String body(String id) => state.body(id).name;
    return switch (o) {
      Built(:final bodyId, :final buildingId, :final defId, :final crew) =>
        _builtMessage(defId, bodyId, buildingId, crew),
      Demolished(:final bodyId, :final buildingId, :final defId) =>
        'Demolished ${_describe(defId, bodyId, buildingId)}'
            '${o.gained.isEmpty ? '' : '; got back ${_list(o.gained)}'}',
      ProjectStarted(kind: ProjectKind.claim, :final targetId) =>
        'Started claiming ${body(targetId)} for ${_list(o.spent)}'
            '${o.noKitsNeeded ? ' (no kits needed)' : ''}'
            '; done in ${_until(o.finishAt)}',
      ProjectStarted(kind: ProjectKind.survey) =>
        'Started a survey for ${_list(o.spent)}; done in '
            '${_until(o.finishAt)}',
      ProjectStarted(kind: ProjectKind.expandSlots, :final targetId) =>
        'Started an extra build slot on ${body(targetId)} for '
            '${_list(o.spent)}; done in ${_until(o.finishAt)}',
      // Megaproject stages start from deliveries, not as projects here.
      ProjectStarted(kind: ProjectKind.megaprojectStage) => null,
      MegaprojectDelivered() => _deliveredMessage(
        o,
        start: cmd is StartMegaprojectStageCommand,
      ),
      RouteCreated(:final routeId, :final stopClampedTo) =>
        'Created route $routeId: ${_routeText(routeId)}'
            '${_clampedText(routeId, stopClampedTo)}',
      RouteUpdated(:final routeId, :final stopClampedTo) =>
        'Updated route $routeId: ${_routeText(routeId)}'
            '${_clampedText(routeId, stopClampedTo)}',
      ShipsSent(:final bodyId, :final toBodyId, :final count) =>
        'Sent ${_ships(count)} from ${body(bodyId)} to ${body(toBodyId)}; '
            '${count == 1 ? 'it lands' : 'they land'} in '
            '${_until(o.arriveAt)}',
      ContractProgress(:final rewardPaid?) =>
        'Delivered ${formatNumber(o.delivered)} '
            '${c.resources[o.resourceId]!.name} from ${body(o.bodyId)} and '
            'completed contract ${o.contractId}; paid '
            '${formatNumber(rewardPaid)} credits. '
            '${_nextContract(o.nextContractAt, capital: true)}',
      ContractProgress() =>
        'Delivered ${formatNumber(o.delivered)} '
            '${c.resources[o.resourceId]!.name} from ${body(o.bodyId)} to '
            'contract ${o.contractId} (${formatNumber(o.totalDelivered)} of '
            '${formatNumber(o.quantity)})',
      ContractDiscarded() =>
        'Discarded contract ${o.contractId} for '
            '${formatNumber(o.quantity)} ${c.resources[o.resourceId]!.name}; '
            '${_nextContract(o.nextContractAt)}',
      CrewAssigned() ||
      Upgraded() ||
      Sold() ||
      AutoSellSet() ||
      RouteRemoved() => null,
    };
  }

  /// When the board's next contract arrives, from its soonest refill [at]:
  /// "a new contract arrives in 4h", or "is due now" once that time has
  /// come (it waits for something it can ask for).
  String _nextContract(double? at, {bool capital = false}) {
    final text = at == null
        ? 'no new contract is due'
        : at <= state.time
        ? 'a new contract is due now'
        : 'a new contract arrives in ${_until(at)}';
    return capital ? '${text[0].toUpperCase()}${text.substring(1)}' : text;
  }

  /// "Built Shipyard on Kora (b9) with 2 of 2 crew": a new [defId] and the
  /// [crew] it took of its base slots, which a building without crew slots
  /// leaves out.
  String _builtMessage(String defId, String bodyId, String id, int crew) {
    final slots = engine.content.buildings[defId]!.crewSlots;
    final staff = slots == 0 ? '' : ' with $crew of $slots crew';
    return 'Built ${_describe(defId, bodyId, id)}$staff';
  }

  /// [n] cargo ships by their display name, such as "2 Cargo Ships".
  String _ships(int n) {
    final c = engine.content;
    final name = c.resources[c.rules.cargoShipResource]!.name;
    return '$n $name${n == 1 ? '' : 's'}';
  }

  /// Route [id] as a phrase: "Steel from Kora to Brine at 0.2/s with
  /// 1 Cargo Ship", plus ", pausing while Brine holds 500" when it has a
  /// stop level.
  String _routeText(String id) {
    final c = engine.content;
    final r = state.routes.firstWhere((x) => x.id == id);
    final to = state.body(r.toBodyId).name;
    final stop = switch (r.stopAtDestination) {
      final v? => ', pausing while $to holds ${formatNumber(v)}',
      null => '',
    };
    return '${c.resources[r.resourceId]!.name} from '
        '${state.body(r.fromBodyId).name} to $to at '
        '${formatNumber(r.ratePerSecond)}/s with ${_ships(r.cargoShips)}$stop';
  }

  /// ". The stop level was cut to Brine's storage cap: stock above it is
  /// wasted" when route [id]'s stop level was [clamped]; else empty.
  String _clampedText(String id, BigNum? clamped) {
    if (clamped == null) return '';
    final r = state.routes.firstWhere((x) => x.id == id);
    return ". The stop level was cut to ${state.body(r.toBodyId).name}'s "
        'storage cap: stock above it is wasted';
  }

  /// What a delivery to a megaproject did: "Delivered 30 Hull Plate to
  /// Orbital Station level 2; it still needs …", "…; level 2 started, done
  /// in 2h", or "…; level 3 starts when level 2 is done, in 25m" while the
  /// stage before it is under way. A [start] (`startMegaprojectStage`)
  /// says "Started Orbital Station level 1 on Kora for …; done in 2h", or
  /// "Paid for Orbital Station level 3 from Kora with …; it starts when
  /// level 2 is done, in 25m".
  String _deliveredMessage(MegaprojectDelivered o, {required bool start}) {
    final name = engine.content.megaprojects[o.megaprojectId]!.name;
    final level = o.level;
    final from = state.body(o.bodyId).name;
    final paid = _list(o.delivered);
    return switch (o) {
      MegaprojectDelivered(stageStarted: true, :final finishAt?) when start =>
        'Started $name level $level on $from for $paid; done in '
            '${_until(finishAt)}',
      MegaprojectDelivered(queued: true, :final finishAt?) when start =>
        'Paid for $name level $level from $from with $paid; it starts when '
            'level ${level - 1} is done, in ${_until(finishAt)}',
      MegaprojectDelivered(stageStarted: true, :final finishAt?) =>
        'Delivered $paid to $name level $level; level $level started, done '
            'in ${_until(finishAt)}',
      MegaprojectDelivered(queued: true, :final finishAt?) =>
        'Delivered $paid to $name level $level; level $level starts when '
            'level ${level - 1} is done, in ${_until(finishAt)}',
      _ =>
        'Delivered $paid to $name level $level; it still needs '
            '${_list(o.remaining)}',
    };
  }

  /// [factionId]'s level of megaproject [id]; 0 before its first stage.
  int _level(String factionId, String id) =>
      state.faction(factionId).megaprojectLevels[id] ?? 0;

  Map<String, Object?> _meta(String cmd, Map<String, Object?> line) =>
      switch (cmd) {
        'advance' => _advance(line),
        'away' => _away(line),
        'report' => _report(),
        'state' => _state(),
        'save' => _save(line),
        'load' => _load(line),
        _ => _costs(),
      };

  FactionState get _player => state.factions.firstWhere((f) => f.isPlayer);

  Map<String, Object?> _advance(Map<String, Object?> line) {
    final s = line['seconds'];
    if (s is! num) {
      return _fail('badCommand', 'field "seconds" must be a number');
    }
    try {
      engine.advance(state, s.toDouble());
    } on ArgumentError catch (e) {
      return _fail('badCommand', '${e.message}');
    }
    return {'ok': true, 'time': state.time};
  }

  /// Simulates the player being away for `seconds` with
  /// [GameEngine.catchUpOffline], offline cap included, and returns its
  /// summary.
  Map<String, Object?> _away(Map<String, Object?> line) {
    final s = line['seconds'];
    if (s is! num) {
      return _fail('badCommand', 'field "seconds" must be a number');
    }
    final OfflineSummary sum;
    try {
      sum = engine.catchUpOffline(state, s.toDouble());
    } on ArgumentError catch (e) {
      return _fail('badCommand', '${e.message}');
    }
    final names = {for (final m in engine.content.milestones) m.id: m.name};
    return {
      'ok': true,
      'time': state.time,
      'headline': sum.headline,
      'secondsAway': sum.secondsAway,
      'secondsSimulated': sum.secondsSimulated,
      'capSeconds': sum.capSeconds,
      'capped': sum.capped,
      'creditsGained': _num(sum.creditsGained),
      'stockGained': _nums(sum.stockGained),
      'totalWasted': _num(sum.totalWasted),
      'milestonesReached': [
        for (final id in sum.milestonesReached) {'id': id, 'name': names[id]},
      ],
      'topBottlenecks': [
        for (final n in sum.topBottlenecks)
          _bottleneck(n, awayFrom: sum.awayFrom),
      ],
      'projectsCompleted': [
        for (final p in sum.projectsCompleted)
          {
            'kind': p.kind.name,
            'targetId': p.targetId,
            'name': p.name,
            'level': ?p.level,
            'message': _completedText(p),
          },
      ],
      'contractsPosted': [
        for (final id in sum.contractsPosted)
          if (_player.contracts.where((k) => k.id == id).firstOrNull
              case final k?)
            {
              'id': k.id,
              'resourceId': k.resourceId,
              'resource': engine.content.resources[k.resourceId]!.name,
              'quantity': _num(k.quantity),
              'reward': _num(k.rewardCredits),
            },
      ],
    };
  }

  /// What a project completed while away did, such as "Brine claimed" or
  /// "Orbital Station reached level 3".
  String _completedText(CompletedProject p) => switch (p.kind) {
    ProjectKind.claim => '${p.name} claimed',
    ProjectKind.survey => '${p.name} surveyed',
    ProjectKind.expandSlots => 'Extra build slot on ${p.name}',
    ProjectKind.megaprojectStage => '${p.name} reached level ${p.level}',
  };

  Map<String, Object?> _report() {
    final r = buildFlowReport(state, engine.content, _player.id);
    return {
      'ok': true,
      'empireNet': _nums(r.empireNet),
      'creditsPerSec': _num(r.creditsPerSec),
      'bodies': [
        for (final b in r.bodies)
          {
            'bodyId': b.bodyId,
            'produced': _nums(b.producedPerSec),
            'consumed': _nums(b.consumedPerSec),
            'net': _nums(b.netPerSec),
            'wasted': _nums(b.wastedPerSec),
            'buildings': [
              for (final s in b.buildings)
                {
                  'buildingId': s.buildingId,
                  'defId': s.defId,
                  'runFraction': s.runFraction,
                  'effectiveFraction': s.effectiveFraction,
                  'limitReason': s.limitReason,
                  'crew': s.crew,
                  'slots': s.slots,
                  'inputs': _nums(s.inputsPerSec),
                  'outputs': _nums(s.outputsPerSec),
                },
            ],
          },
      ],
      'bottlenecks': [for (final n in r.bottlenecks) _bottleneck(n)],
    };
  }

  Map<String, Object?> _state() {
    final c = engine.content;
    final p = _player;
    final crew = crewTotals(state, c, p.id);
    final held = <String>{
      for (final b in state.bodies)
        if (b.ownerId == p.id)
          for (final MapEntry(key: id, value: v) in b.stock.entries)
            if (!v.isZero) id,
    };
    return {
      'ok': true,
      'time': state.time,
      'credits': _num(p.credits),
      'crew': {
        'base': crew.base,
        'supported': crew.supported,
        'assigned': crew.assigned,
        'free': crew.free,
        'overAssigned': crew.overAssigned,
      },
      'milestones': [
        for (final m in c.milestones)
          if (p.reachedMilestones.contains(m.id)) {'id': m.id, 'name': m.name},
      ],
      'megaprojects': [
        for (final m in c.megaprojects.values)
          {
            'id': m.id,
            'name': m.name,
            'level': _level(p.id, m.id),
            if (p.megaprojectProgress[m.id] case final got?) ...{
              'delivered': _nums(got),
              'stillNeeded': _nums(megaprojectRemaining(state, c, p.id, m)),
            },
          },
      ],
      'contracts': [
        for (final k in p.contracts)
          {
            'id': k.id,
            'issuer': c.contractTemplates[k.templateId]!.issuer,
            'resourceId': k.resourceId,
            'resource': c.resources[k.resourceId]!.name,
            'quantity': _num(k.quantity),
            'delivered': _num(k.delivered),
            'reward': _num(k.rewardCredits),
          },
      ],
      'contractRefills': [
        for (final t in p.contractRefillAt)
          {'at': t, 'timeLeft': formatDuration(t - state.time)},
      ],
      'bodies': [
        for (final b in visibleBodies(state, p.id))
          {
            'id': b.id,
            'name': b.name,
            'type': c.bodyTypes[b.typeId]!.name,
            'owner': b.ownerId,
            'deposits': [
              for (final d in b.deposits)
                {
                  'resourceId': d.resourceId,
                  'name': c.resources[d.resourceId]!.name,
                  'richness': d.richness,
                },
            ],
            'slots': {'used': b.buildings.length, 'total': buildSlots(c, b)},
            'storageCap': _num(storageCap(state, c, b)),
            if (b.ownerId == p.id)
              'stock': _nums({
                for (final id in c.resources.keys)
                  if (b.stock[id] case final v? when !v.isZero)
                    id: c.resources[id]!.tier >= _wholeUnitTier ? _floor(v) : v,
              }),
          },
      ],
      'unsurveyedSignals': [
        for (final sys in c.galaxy.systems)
          if (state.bodies.any(
            (b) => b.systemId == sys.id && b.ownerId == p.id,
          ))
            {
              'systemId': sys.id,
              'name': sys.name,
              'count': unsurveyedSignals(state, c, p.id, sys.id),
            },
      ],
      'routes': [
        for (final r in state.routes)
          if (r.ownerId == p.id)
            {
              'id': r.id,
              'from': r.fromBodyId,
              'to': r.toBodyId,
              'resourceId': r.resourceId,
              'ratePerSecond': _num(r.ratePerSecond),
              'cargoShips': r.cargoShips,
              'stopAtDestination': switch (r.stopAtDestination) {
                final v? => _num(v),
                null => null,
              },
              'paused': routePaused(state, r),
              'inFlight': _num(routeInFlight(state, r)),
              'travelTime': formatDuration(
                travelSeconds(
                  state,
                  c,
                  state.body(r.fromBodyId),
                  state.body(r.toBodyId),
                ),
              ),
            },
      ],
      'autoSell': [for (final rule in p.autoSell) _autoSellRule(rule)],
      'projects': [
        for (final pr in engine.projectsFor(state, p.id))
          {
            'id': pr.id,
            'kind': pr.kind.name,
            'targetId': pr.targetId,
            'name': projectTargetName(state, c, pr),
            'startedAt': pr.startedAt,
            'finishAt': pr.finishAt,
            'secondsLeft': pr.finishAt - state.time,
            'timeLeft': formatDuration(pr.finishAt - state.time),
          },
      ],
      'market': {
        for (final id in c.resources.keys)
          if (held.contains(id))
            id: {
              'price': _num(price(state, c, id)),
              'saturation': state.market.saturation[id] ?? 1.0,
            },
      },
      'notes': [
        'Stock of tier $_wholeUnitTier and up (components such as cargo '
            'ships and outpost kits) shows whole units; the part-made unit '
            'is kept and finishes later.',
      ],
    };
  }

  /// Auto-sell [rule] as JSON, with what it keeps back in a 60 s step
  /// ([autoSellKeep]): "keeps 34 (keepAtLeast 10 + 24 local use)", plus
  /// ", cut to the storage cap" inside the brackets when the cap cut it.
  Map<String, Object?> _autoSellRule(AutoSellRule rule) {
    final k = autoSellKeep(state, engine.content, rule, 60);
    final cut = k.cappedAtStorage ? ', cut to the storage cap' : '';
    return {
      'bodyId': rule.bodyId,
      'resourceId': rule.resourceId,
      'keepAtLeast': _num(k.keepAtLeast),
      'localUse': _num(k.localUse),
      'keeps': _num(k.keeps),
      'text':
          'keeps ${formatNumber(k.keeps)} (keepAtLeast '
          '${formatNumber(k.keepAtLeast)} + ${formatNumber(k.localUse)} '
          'local use$cut)',
    };
  }

  /// What the player's timed actions and upgrades cost now. An action that
  /// cannot be taken now says why, as `"busy: …"` (or what it is at)
  /// instead of a cost.
  Map<String, Object?> _costs() {
    final c = engine.content;
    final p = _player;
    return {
      'ok': true,
      'claim': _claimCost(),
      'survey': _surveyCost(),
      'extraSlot': {
        for (final b in state.bodies)
          if (b.ownerId == p.id) b.id: _slotCost(b),
      },
      'megaprojects': {
        for (final m in c.megaprojects.values) m.id: _megaprojectCost(m),
      },
      'upgradeNote': _upgradeNote(c),
      'upgrades': [
        for (final body in state.bodies)
          if (body.ownerId == p.id)
            for (final b in body.buildings)
              {
                'bodyId': body.id,
                'buildingId': b.id,
                'defId': b.defId,
                'tracks': {
                  for (final t in c.buildings[b.defId]!.upgrades.keys)
                    t.name: switch (upgradeMaxedReason(c, b, t)) {
                      final why? => {
                        'level': b.levels[t],
                        'maxed': true,
                        'reason': why,
                      },
                      null => {
                        'level': b.levels[t],
                        'cost': _nums(upgradeCost(c, b, t)),
                      },
                    },
                },
              },
      ],
    };
  }

  /// The next claim's cost, or why there is none to start: no body left,
  /// or every one left already being claimed.
  Object _claimCost() {
    final p = _player;
    final free = visibleBodies(
      state,
      p.id,
    ).where((b) => b.ownerId == null).toList();
    if (free.isEmpty) return 'no bodies left to claim';
    if (free.every((b) => projectOn(state, ProjectKind.claim, b.id) != null)) {
      return 'busy: every body left is being claimed';
    }
    return _nums(claimCost(state, engine.content, p.id));
  }

  /// A survey's cost and time, or why none can start in the player's
  /// systems.
  Object _surveyCost() {
    final c = engine.content;
    final systems = {
      for (final b in state.bodies)
        if (b.ownerId == _player.id) b.systemId,
    };
    final hidden = state.bodies.where(
      (b) => systems.contains(b.systemId) && !b.surveyed,
    );
    if (hidden.isEmpty) return 'nothing left to survey';
    if (hidden.every(
      (b) => projectOn(state, ProjectKind.survey, b.id) != null,
    )) {
      return 'busy: every unsurveyed signal is being surveyed';
    }
    return {
      'cost': _nums(surveyCost(c)),
      'timeTaken': formatDuration(surveySeconds(c)),
    };
  }

  /// [body]'s next extra build slot's cost, or why it cannot be bought now.
  Object _slotCost(BodyState body) {
    if (projectOn(state, ProjectKind.expandSlots, body.id) case final p?) {
      return 'busy: an extra slot arrives in ${_until(p.finishAt)}';
    }
    if (body.extraSlots >= SaveCodec.maxExtraSlots) {
      return 'at the most extra slots (${SaveCodec.maxExtraSlots})';
    }
    return _nums(slotCost(engine.content, body));
  }

  /// The cost of the stage of [m] deliveries pay for (while one is under
  /// way, the one after it), with what it still needs once part-paid; or
  /// why nothing more can be delivered.
  Object _megaprojectCost(MegaprojectDef m) {
    final c = engine.content;
    final p = _player;
    final level = megaprojectDeliveryLevel(state, p.id, m);
    if (level >= SaveCodec.maxMegaprojectLevel) return 'at its highest level';
    final running = megaprojectStageOf(state, p.id, m.id);
    if (running != null && megaprojectStageQueued(state, c, p.id, m)) {
      return 'busy: level ${level + 1} is paid for and starts when level '
          '$level is done, in ${_until(running.finishAt)}';
    }
    return {
      'nextLevel': level + 1,
      'cost': _nums(megaprojectCost(c, m, level)),
      if (p.megaprojectProgress.containsKey(m.id))
        'stillNeeded': _nums(megaprojectRemaining(state, c, p.id, m)),
      'timeTaken': formatDuration(megaprojectStageSeconds(m, level)),
      if (running != null)
        'note':
            'level $level is under way (done in '
            '${_until(running.finishAt)}); deliveries pay for level '
            '${level + 1}, which starts when level $level is done if it is '
            'paid for by then',
    };
  }

  /// How speed and capacity prices grow ([upgradeCost]), with the step as
  /// a percentage when every building shares the same one.
  String _upgradeNote(Content c) {
    final steps = {
      for (final d in c.buildings.values)
        if (d.upgrades[UpgradeTrack.speed] case final speed?
            when d.upgrades.containsKey(UpgradeTrack.capacity))
          speed.growth,
    };
    final pricier = steps.length == 1
        ? '${((steps.single - 1) * 100).round()}% pricier'
        : 'pricier by its speed growth';
    return 'Speed and capacity on a building share one counter: each speed '
        'or capacity upgrade makes the next one $pricier. Efficiency counts '
        'on its own.';
  }

  String _path(Map<String, Object?> line) {
    final p = line['path'];
    if (p is! String) {
      throw const FormatException('field "path" must be a string');
    }
    return p;
  }

  Map<String, Object?> _save(Map<String, Object?> line) {
    final path = _path(line);
    File(path).writeAsStringSync(SaveCodec.encode(state));
    return {'ok': true, 'path': path};
  }

  Map<String, Object?> _load(Map<String, Object?> line) {
    final path = _path(line);
    switch (SaveCodec.decode(File(path).readAsStringSync(), engine.content)) {
      case SaveOk(state: final s):
        state = s;
        return {'ok': true, 'time': s.time};
      case SaveError(:final kind, :final message):
        return _fail(kind.name, message);
    }
  }
}
