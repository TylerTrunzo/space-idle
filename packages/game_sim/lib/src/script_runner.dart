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
};

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
    final result = engine.apply(state, Command.fromJson(j));
    return switch (result) {
      CommandOk(:final createdId) => {'ok': true, 'createdId': ?createdId},
      CommandFailed(:final error, :final message) => _fail(error.name, message),
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
    final p = _player;
    final crew = crewTotals(state, engine.content, p.id);
    return {
      'ok': true,
      'time': state.time,
      'credits': _num(p.credits),
      'crew': {
        'base': crew.base,
        'supported': crew.supported,
        'assigned': crew.assigned,
        'free': crew.free,
      },
      'bodies': [
        for (final b in state.bodies)
          if (b.ownerId == p.id)
            {
              'id': b.id,
              'name': b.name,
              'buildings': b.buildings.length,
              'stock': _nums({
                for (final id in engine.content.resources.keys)
                  if (b.stock[id] case final v? when !v.isZero) id: v,
              }),
            },
      ],
    };
  }

  Map<String, Object?> _costs() {
    final c = engine.content;
    final p = _player;
    return {
      'ok': true,
      'claim': _nums(claimCost(state, c, p.id)),
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
