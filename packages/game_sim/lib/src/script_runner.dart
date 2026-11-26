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
  'removeRoute',
  'sell',
  'setAutoSell',
  'claimBody',
  'expandSlots',
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

Map<String, Object?> _bottleneck(Bottleneck n) => {
  'kind': n.kind.name,
  'bodyId': n.bodyId,
  'buildingId': n.buildingId,
  'resourceId': n.resourceId,
  'runFraction': n.runFraction,
  'message': n.message,
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
    final before = _holdings(cmd.factionId);
    // Read before a demolish removes the building.
    final demolished = cmd is DemolishCommand
        ? _describe(cmd.buildingId)
        : null;
    final result = engine.apply(state, cmd);
    switch (result) {
      case CommandFailed(:final error, :final message):
        return _fail(error.name, message);
      case CommandOk(:final createdId):
        final after = _holdings(cmd.factionId);
        final spent = <String, BigNum>{};
        final gained = <String, BigNum>{};
        for (final k in {...before.keys, ...after.keys}) {
          final d = changeBetween(
            after[k] ?? const BigNum.zero(),
            before[k] ?? const BigNum.zero(),
          );
          if (d.isNegative) spent[k] = -d;
          if (d > const BigNum.zero()) gained[k] = d;
        }
        final message = _message(cmd, createdId, spent, gained, demolished);
        return {
          'ok': true,
          'createdId': ?createdId,
          'message': ?message,
          if (spent.isNotEmpty) 'spent': _nums(spent),
          if (gained.isNotEmpty) 'gained': _nums(gained),
        };
    }
  }

  /// `credits` and `<body>/<resource>` to what [factionId] holds on its
  /// bodies, for showing what a command took and gave.
  Map<String, BigNum> _holdings(String factionId) {
    final f = state.factions.where((x) => x.id == factionId).firstOrNull;
    return {
      if (f != null) 'credits': f.credits,
      for (final b in state.bodies)
        if (b.ownerId == factionId)
          for (final MapEntry(key: id, value: v) in b.stock.entries)
            '${b.id}/$id': v,
    };
  }

  /// "Smelter on Kora (b3)", or null if there is no such building.
  String? _describe(String buildingId) {
    final c = engine.content;
    for (final body in state.bodies) {
      for (final b in body.buildings) {
        if (b.id == buildingId) {
          return '${c.buildings[b.defId]!.name} on ${body.name} ($buildingId)';
        }
      }
    }
    return null;
  }

  /// A sentence on what a claim, demolish or new route did; null for other
  /// commands.
  String? _message(
    Command cmd,
    String? createdId,
    Map<String, BigNum> spent,
    Map<String, BigNum> gained,
    String? demolished,
  ) {
    final c = engine.content;
    String list(Map<String, BigNum> m) => [
      for (final MapEntry(key: k, value: v) in m.entries)
        k == 'credits'
            ? '${formatNumber(v)} credits'
            : '${formatNumber(v)} ${c.resources[k.split('/').last]!.name}',
    ].join(' and ');
    return switch (cmd) {
      ClaimBodyCommand(:final bodyId) =>
        'Claimed ${state.body(bodyId).name} for ${list(spent)}',
      DemolishCommand() =>
        'Demolished $demolished'
            '${gained.isEmpty ? '' : '; got back ${list(gained)}'}',
      CreateRouteCommand(
        :final fromBodyId,
        :final toBodyId,
        :final resourceId,
        :final ratePerSecond,
        :final cargoShips,
      ) =>
        'Created route $createdId: ${c.resources[resourceId]!.name} from '
            '${state.body(fromBodyId).name} to ${state.body(toBodyId).name} '
            'at ${formatNumber(ratePerSecond)}/s with $cargoShips '
            '${c.resources[c.rules.cargoShipResource]!.name}'
            '${cargoShips == 1 ? '' : 's'}',
      _ => null,
    };
  }

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
      'secondsAway': sum.secondsAway,
      'secondsSimulated': sum.secondsSimulated,
      'creditsGained': _num(sum.creditsGained),
      'stockGained': _nums(sum.stockGained),
      'totalWasted': _num(sum.totalWasted),
      'milestonesReached': [
        for (final id in sum.milestonesReached) {'id': id, 'name': names[id]},
      ],
      'topBottlenecks': [for (final n in sum.topBottlenecks) _bottleneck(n)],
    };
  }

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
      'bodies': [
        for (final b in state.bodies)
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

  Map<String, Object?> _costs() {
    final c = engine.content;
    final p = _player;
    return {
      'ok': true,
      'claim': state.bodies.any((b) => b.ownerId == null)
          ? _nums(claimCost(state, c, p.id))
          : 'no bodies left to claim',
      'extraSlot': {
        for (final b in state.bodies)
          if (b.ownerId == p.id) b.id: _nums(slotCost(c, b)),
      },
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
                    t.name: {
                      'level': b.levels[t],
                      'cost': _nums(upgradeCost(c, b, t)),
                    },
                },
              },
      ],
    };
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
