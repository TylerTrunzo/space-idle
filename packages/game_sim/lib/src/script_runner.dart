import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'away_headline.dart';

/// Command names that are not game commands.
const _metaCommands = {
  'advance',
  'away',
  'report',
  'state',
  'save',
  'load',
  'costs',
  'catalog',
};

/// Command names `Command.fromJson` understands.
const _gameCommands = {
  'build',
  'demolish',
  'assignCrew',
  'upgrade',
  'buyUpgrades',
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
  'setMegaprojectAuto',
  'setAutoPayReserve',
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

/// A number as JSON: the raw `BigNum.toJson()` value and a display string,
/// rounded the [rounding] way.
Map<String, Object?> _num(
  BigNum v, {
  NumberRounding rounding = NumberRounding.nearest,
}) => {'value': v.toJson(), 'display': formatNumber(v, rounding: rounding)};

Map<String, Object?> _nums(
  Map<String, BigNum> m, {
  NumberRounding rounding = NumberRounding.nearest,
}) => {for (final e in m.entries) e.key: _num(e.value, rounding: rounding)};

/// A rate a second for display: [formatNumber] from 1 up, else three
/// significant figures, so a slow rate such as 0.00333 does not read as 0.
String _rateText(BigNum v) {
  final d = v.toDouble();
  if (d == 0 || d.abs() >= 1) return formatNumber(v);
  final fixed = d.toStringAsPrecision(3);
  return fixed.contains('e')
      ? fixed
      : fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Rates a second as JSON: the raw value and [_rateText].
Map<String, Object?> _rates(Map<String, BigNum> m) => {
  for (final e in m.entries)
    e.key: {'value': e.value.toJson(), 'display': _rateText(e.value)},
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
        // A delivery from every body says what each gave.
        final spent = o is ContractProgress && o.bodyId == null
            ? {
                for (final MapEntry(key: b, value: v) in o.fromBodies.entries)
                  '$b/${o.resourceId}': v,
              }
            : keyed(o.spent);
        final gained = keyed(o.gained);
        final recipe = o is Built ? _builtRecipe(o) : null;
        return {
          'ok': true,
          'createdId': ?createdId,
          'message': ?_message(cmd, o),
          if (spent.isNotEmpty) 'spent': _nums(spent),
          if (gained.isNotEmpty) 'gained': _nums(gained),
          if (recipe != null && recipe.inputs.isNotEmpty)
            'inputsPerSec': _rates(recipe.inputs),
          if (recipe != null && recipe.outputs.isNotEmpty)
            'outputsPerSec': _rates(recipe.outputs),
          if (o case Upgraded(:final crewAdded) when crewAdded > 0)
            'crewAdded': crewAdded,
          if (o is UpgradesBought) ..._boughtJson(o),
        };
    }
  }

  /// A bottleneck as JSON, with a `message` built from its typed fields
  /// ([bottleneckText]). With [ongoing], its record in an away summary as
  /// one that was there before the absence, it adds `since` (the game time
  /// it began), `worseThanBefore`, and `ongoing`: how long it has gone on,
  /// such as "for 3h 10m", and ", and worse than before" when its credits
  /// lost an hour grew by more than a quarter.
  Map<String, Object?> _bottleneck(
    Bottleneck n, {
    OngoingBottleneck? ongoing,
  }) => {
    'kind': n.kind.name,
    'bodyId': n.bodyId,
    'buildingId': n.buildingId,
    'resourceId': n.resourceId,
    'runFraction': n.runFraction,
    'message': bottleneckText(n),
    'firstSeenAt': n.firstSeenAt,
    'lostCreditsPerHour': switch (n.lostCreditsPerHour) {
      final v? => _num(v),
      null => null,
    },
    'count': n.count,
    if (n.buildingIds.isNotEmpty) 'buildingIds': n.buildingIds,
    'megaprojectId': ?n.megaprojectId,
    'shareOfSales': ?n.shareOfSales,
    if (n.heldByKeep case final v?) 'heldByKeep': _num(v),
    'routeId': ?n.routeId,
    'binding': ?n.binding?.name,
    if (n.routePerSec case final v?) 'routePerSec': _num(BigNum.from(v)),
    if (ongoing != null) ...{
      'since': ongoing.since,
      'worseThanBefore': ongoing.worseThanBefore,
      'ongoing':
          'for ${formatDuration(state.time - ongoing.since)}'
          '${ongoing.worseThanBefore ? ', and worse than before' : ''}',
    },
  };

  /// What [n] says to the player: the engine's message for one building or
  /// store; for a group of buildings ([Bottleneck.count] above 1), "17
  /// Station Docks on Cinder are running at 40%: not enough Hull Plate";
  /// for the megaproject kinds, what is taken or held back, in numbers; for
  /// a route-limited shortage, the route's limit and what raises it.
  ///
  /// Public so the bot session's bottleneck log reads as the CLI does
  /// (`runBotSession`), and for tests.
  String bottleneckText(Bottleneck n) {
    final c = engine.content;
    String res(String id) => c.resources[id]!.name;
    switch (n.kind) {
      case BottleneckKind.megaprojectDiversion:
        final share = math.min(100, (n.shareOfSales! * 100).round());
        return '${_megaprojectName(n.megaprojectId!)} takes $share% of the '
            '${res(n.resourceId!)} that would sell: '
            '${formatNumber(n.lostCreditsPerHour!)} credits an hour not '
            'earned';
      case BottleneckKind.keepBlocksDelivery:
        final rule = _player.autoSell
            .where((r) => r.bodyId == n.bodyId && r.resourceId == n.resourceId)
            .firstOrNull;
        final keep = rule == null ? '' : ' ${formatNumber(rule.keepAtLeast)}';
        return '${_megaprojectName(n.megaprojectId!)} still needs '
            '${res(n.resourceId!)}, but ${state.body(n.bodyId!).name} '
            'keeps ${formatNumber(n.heldByKeep!)} of it back for its '
            'auto-sell keepAtLeast$keep';
      case BottleneckKind.storageFull when n.fromAbsence:
        return '${state.body(n.bodyId!).name} storage filled up with '
            '${res(n.resourceId!)} while you were away: output was wasted';
      case BottleneckKind.storageFull:
        return '${state.body(n.bodyId!).name} storage is full of '
            '${res(n.resourceId!)}: output is being wasted';
      case BottleneckKind.routeLimited:
        return '${_whoIsRunning(n)}: ${_routeLimitText(n)}';
      case _ when n.count > 1:
        return _groupText(n);
      case _:
        return n.message;
    }
  }

  /// "17 Station Docks on Cinder are running as low as 39%", or "Station
  /// Dock on Cinder is running at 39%" for one: who [n] holds back and how
  /// far, never 100% while held back.
  String _whoIsRunning(Bottleneck n) {
    final pct = math.min(99, (n.runFraction * 100).round());
    if (n.count > 1) return '${_groupWho(n)} are running as low as $pct%';
    final body = state.body(n.bodyId!);
    final b = body.buildings.where((x) => x.id == n.buildingId).firstOrNull;
    final what = b == null
        ? 'A building'
        : engine.content.buildings[b.defId]!.name;
    return '$what on ${body.name} is running at $pct%';
  }

  /// "Hull Plate into Cinder is limited by Cinder's storage (814/s); a Depot
  /// raises it": what holds [n]'s route ([Bottleneck.routeId]) back, at the
  /// most it carries a second, and what raises it.
  String _routeLimitText(Bottleneck n) {
    final c = engine.content;
    final to = state.body(n.bodyId!).name;
    final into = '${c.resources[n.resourceId!]!.name} into $to is limited by';
    final rate = '${formatNumber(BigNum.from(n.routePerSec!))}/s';
    final route = state.routes.where((r) => r.id == n.routeId).firstOrNull;
    final id = n.routeId!;
    switch (n.binding!) {
      case RouteLimit.rate:
        return "$into route $id's rate ($rate); raise its rate";
      case RouteLimit.ships:
        final ships = route == null ? 'cargo ships' : _ships(route.cargoShips);
        return "$into route $id's $ships ($rate); assign more ships";
      case RouteLimit.destinationRoom:
        final depot = c.buildings.values
            .where((d) => d.kind == BuildingKind.warehouse)
            .firstOrNull;
        final raise = depot == null
            ? 'more storage there raises it'
            : 'a ${depot.name} raises it';
        return "$into $to's storage ($rate); $raise";
      case RouteLimit.stopLevel:
        return "$into route $id's stop level ($rate); raise its stop level";
      case RouteLimit.sourceStock:
        final from = route == null
            ? 'its source'
            : state.body(route.fromBodyId).name;
        return '$into what $from has to send ($rate)';
    }
  }

  /// "17 Station Docks on Cinder": the [Bottleneck.count] buildings of a
  /// group on one body, named by type when they share one.
  String _groupWho(Bottleneck n) {
    final c = engine.content;
    final body = state.body(n.bodyId!);
    final types = {
      for (final id in n.buildingIds)
        if (body.buildings.where((b) => b.id == id).firstOrNull case final b?)
          b.defId,
    };
    final what = types.length == 1
        ? plural(c.buildings[types.single]!.name)
        : 'buildings';
    return '${n.count} $what on ${body.name}';
  }

  /// [bottleneckText] of a group of [Bottleneck.count] buildings on one
  /// body, named by type when they share one.
  String _groupText(Bottleneck n) {
    final c = engine.content;
    final who = _groupWho(n);
    return switch (n.kind) {
      // A group's run fraction is its lowest member's.
      BottleneckKind.input =>
        '$who are running as low as '
            '${math.min(99, (n.runFraction * 100).round())}%: '
            'not enough ${c.resources[n.resourceId!]!.name}',
      BottleneckKind.understaffed => '$who are understaffed',
      BottleneckKind.noCrew => '$who have no crew',
      _ => n.message,
    };
  }

  /// [name] in the plural: "Station Docks", "Plate Presses", "Fuel
  /// Refineries"; a name ending in "Works" stays as it is ("Reactor
  /// Works").
  static String plural(String name) {
    if (name.endsWith('Works')) return name;
    if (RegExp(r'[^aeiou]y$').hasMatch(name)) {
      return '${name.substring(0, name.length - 1)}ies';
    }
    if (RegExp(r'(s|x|ch|sh)$').hasMatch(name)) return '${name}es';
    return '${name}s';
  }

  /// "29.9K of 30K, 1 still owed": [done] of [whole], in whole units, the
  /// part done rounded down and what is owed rounded up, so it never reads
  /// "30K of 30K" while anything is owed.
  static String _progress(BigNum done, BigNum whole) {
    final got = done.floor();
    final owed = (whole - done).ceil();
    return '${formatNumber(got, rounding: NumberRounding.down)} of '
        '${formatNumber(whole)}, '
        '${formatNumber(owed, rounding: NumberRounding.up)} still owed';
  }

  /// "Smelter on Kora (b3)": building [buildingId], a [defId], on [bodyId].
  String _describe(String defId, String bodyId, String buildingId) =>
      '${engine.content.buildings[defId]!.name} on '
      '${state.body(bodyId).name} ($buildingId)';

  /// Credits and goods as "5K credits and 20 Steel", in [m]'s order, each
  /// amount rounded the [rounding] way: [NumberRounding.up] for what is
  /// still owed, so it never reads as less (or as nothing).
  String _list(
    Map<String, BigNum> m, {
    NumberRounding rounding = NumberRounding.nearest,
  }) => [
    for (final MapEntry(key: k, value: v) in m.entries)
      k == 'credits'
          ? '${formatNumber(v, rounding: rounding)} credits'
          : '${formatNumber(v, rounding: rounding)} '
                '${engine.content.resources[k]!.name}',
  ].join(' and ');

  /// Game seconds from now until [at], as "2h 5m".
  String _until(double at) => formatDuration(at - state.time);

  /// A sentence on what [cmd] did, from its outcome [o]; null for
  /// crew, upgrades other than capacity on a crewed building, sales,
  /// auto-sell rules and closed routes, whose `spent` and `gained` say it
  /// all.
  String? _message(Command cmd, CommandOutcome o) {
    final c = engine.content;
    String body(String id) => state.body(id).name;
    return switch (o) {
      Built() => _builtMessage(o),
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
            '${c.resources[o.resourceId]!.name} ${_fromText(o)} and '
            'completed contract ${o.contractId}; paid '
            '${formatNumber(rewardPaid)} credits. '
            '${_nextContract(o.nextContractAt, capital: true)}',
      ContractProgress() =>
        'Delivered ${formatNumber(o.delivered)} '
            '${c.resources[o.resourceId]!.name} ${_fromText(o)} to '
            'contract ${o.contractId} (${_progress(o.totalDelivered, o.quantity)})',
      ContractDiscarded() =>
        'Discarded contract ${o.contractId} for '
            '${formatNumber(o.quantity)} ${c.resources[o.resourceId]!.name}; '
            '${_nextContract(o.nextContractAt)}',
      MegaprojectAutoSet() => _autoText(o),
      AutoPayReserveSet(:final reserve) =>
        'Auto-pay now keeps ${formatNumber(reserve)} credits; the credits '
            'above it are shared out each game minute among the megaprojects '
            'taking credits on their own',
      Upgraded(track: UpgradeTrack.capacity) => _capacityMessage(o),
      UpgradesBought() => _boughtMessage(o),
      CrewAssigned() ||
      Upgraded() ||
      Sold() ||
      AutoSellSet() ||
      RouteRemoved() => null,
    };
  }

  /// A `buyUpgrades` reply's own fields: each building and track it
  /// raised (`upgrades`, with `crewAdded` when a capacity level filled new
  /// slots), why it stopped (`stop`) and what the cheapest level not
  /// bought costs (`nextCost`).
  Map<String, Object?> _boughtJson(UpgradesBought o) => {
    'upgrades': [
      for (final p in o.purchases)
        {
          'buildingId': p.buildingId,
          'bodyId': p.bodyId,
          'track': p.track.name,
          'levels': p.levels,
          'level': p.level,
          'cost': _num(p.cost),
          if (p.crewAdded > 0) 'crewAdded': p.crewAdded,
        },
    ],
    'stop': o.stop.name,
    if (o.nextCost case final v?) 'nextCost': _num(v),
  };

  /// "Bought 3 upgrade levels on 2 buildings for 159 credits; the next
  /// costs 58.5 credits, more than the budget allows": what [o] bought and
  /// why it stopped.
  String _boughtMessage(UpgradesBought o) {
    final why = switch (o.stop) {
      UpgradeBuyStop.budget =>
        '${o.levels == 0 ? 'the cheapest' : 'the next'} costs '
            '${formatNumber(o.nextCost!)} credits, more than the budget '
            'allows',
      UpgradeBuyStop.maxPurchases =>
        'stopped at ${o.levels} levels, the most this command buys',
      UpgradeBuyStop.nothingToBuy => 'nothing is left to upgrade',
    };
    if (o.levels == 0) return 'Bought no upgrades: $why';
    final buildings = {for (final p in o.purchases) p.buildingId}.length;
    final levels = o.levels == 1
        ? '1 upgrade level'
        : '${o.levels} upgrade levels';
    final on = buildings == 1 ? '1 building' : '$buildings buildings';
    return 'Bought $levels on $on for ${formatNumber(o.total)} credits; $why';
  }

  /// What a capacity level [o] did to its building's crew: "Mine on Kora
  /// (b1) is at capacity level 1; 1 free crew moved into its new slot (2
  /// of 2 crew)", or that the new slot is empty when no crew was free;
  /// null for a building without crew slots (a habitat's capacity adds
  /// housing).
  String? _capacityMessage(Upgraded o) {
    final c = engine.content;
    final b = state
        .body(o.bodyId)
        .buildings
        .firstWhere((x) => x.id == o.buildingId);
    final def = c.buildings[b.defId]!;
    final max = maxCrew(c.rules, def, b);
    if (max == 0) return null;
    final what =
        '${_describe(b.defId, o.bodyId, b.id)} is at capacity level '
        '${o.level}';
    final slots = c.rules.capacityCrewPerLevel == 1 ? 'slot' : 'slots';
    if (o.crewAdded > 0) {
      return '$what; ${o.crewAdded} free crew moved into its new $slots '
          '(${b.crew} of $max crew)';
    }
    return '$what; its new $slots ${slots == 'slot' ? 'is' : 'are'} empty '
        '(no free crew; ${b.crew} of $max crew)';
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

  /// "Built Shipyard on Kora (b9) with 2 of 2 crew. At full crew it uses
  /// 0.0333 Steel and 0.0133 Circuit a second and makes 0.00333 Cargo Ship
  /// a second": a new [defId], the [crew] it took of its base slots (which
  /// a building without crew slots leaves out) and its whole recipe
  /// ([_builtRecipe]), so no input shows up only once it runs short.
  String _builtMessage(Built o) {
    final def = engine.content.buildings[o.defId]!;
    final slots = def.crewSlots;
    final staff = slots == 0 ? '' : ' with ${o.crew} of $slots crew';
    final recipe = _builtRecipe(o);
    final runs = slots == 0 ? 'Running fully it' : 'At full crew it';
    final parts = [
      if (recipe.inputs.isNotEmpty) 'uses ${_rateList(recipe.inputs)}',
      if (recipe.outputs.isNotEmpty) 'makes ${_rateList(recipe.outputs)}',
      if (def.housing > 0) 'houses ${def.housing} crew',
    ];
    final what = parts.isEmpty ? '' : '. $runs ${parts.join(' and ')}';
    return 'Built ${_describe(o.defId, o.bodyId, o.buildingId)}$staff$what';
  }

  /// Resource id to units a second as "0.0333 Steel and 0.0133 Circuit a
  /// second", or "a, b and c a second" for more ([_rateText]).
  String _rateList(Map<String, BigNum> m) {
    final c = engine.content;
    final items = [
      for (final MapEntry(key: id, value: v) in m.entries)
        '${_rateText(v)} ${c.resources[id]!.name}',
    ];
    final last = items.removeLast();
    return '${items.isEmpty ? last : '${items.join(', ')} and $last'} '
        'a second';
  }

  /// What the building [o] put up takes and makes a second at its base
  /// level with its base crew slots full ([_recipe]): an extractor its
  /// deposit's resource at that deposit's richness.
  ({Map<String, BigNum> inputs, Map<String, BigNum> outputs}) _builtRecipe(
    Built o,
  ) {
    final def = engine.content.buildings[o.defId]!;
    final recipe = _recipe(def);
    if (def.kind != BuildingKind.extractor) return recipe;
    final body = state.body(o.bodyId);
    final b = body.buildings.firstWhere((x) => x.id == o.buildingId);
    final id = b.depositResourceId;
    final deposit = body.deposits.where((d) => d.resourceId == id).firstOrNull;
    final rate = recipe.outputs[id];
    return (
      inputs: recipe.inputs,
      outputs: {
        if (id != null && deposit != null && rate != null)
          id: rate.mulDouble(deposit.richness),
      },
    );
  }

  /// What a [def] building takes and makes a second at its base level with
  /// its base crew slots full: each recipe amount over its cycle seconds;
  /// for an extractor, every resource it can mine at richness 1; nothing
  /// for a building that runs no recipe.
  ({Map<String, BigNum> inputs, Map<String, BigNum> outputs}) _recipe(
    BuildingDef def,
  ) {
    if (!runsRecipe(def)) return (inputs: const {}, outputs: const {});
    Map<String, BigNum> perSecond(Map<String, double> perCycle) => {
      for (final MapEntry(key: id, value: v) in perCycle.entries)
        id: BigNum.from(v / def.cycleSeconds),
    };
    return (inputs: perSecond(def.inputs), outputs: perSecond(def.outputs));
  }

  /// Every building type in content order: what it costs, its crew slots,
  /// what it takes and makes a second ([_recipe]), housing or storage it
  /// adds, and the player's bodies that can host one now (a free build
  /// slot and, for an extractor, a deposit it can mine, with the rate
  /// there).
  Map<String, Object?> _catalog() {
    final c = engine.content;
    final owned = [
      for (final b in state.bodies)
        if (b.ownerId == _player.id) b,
    ];
    return {
      'ok': true,
      'buildings': [
        for (final d in c.buildings.values) _catalogEntry(d, owned),
      ],
    };
  }

  Map<String, Object?> _catalogEntry(BuildingDef d, List<BodyState> owned) {
    final c = engine.content;
    final recipe = _recipe(d);
    final hosts = <Map<String, Object?>>[];
    for (final body in owned) {
      if (body.buildings.length >= buildSlots(c, body)) continue;
      if (d.kind != BuildingKind.extractor) {
        hosts.add({'bodyId': body.id, 'name': body.name});
        continue;
      }
      final deposits = [
        for (final x in body.deposits)
          if (d.extracts.contains(x.resourceId))
            {
              'resourceId': x.resourceId,
              'name': c.resources[x.resourceId]!.name,
              'richness': x.richness,
              'outputPerSec': _rates({
                'rate': recipe.outputs[x.resourceId]!.mulDouble(x.richness),
              })['rate'],
            },
      ];
      if (deposits.isEmpty) continue;
      hosts.add({'bodyId': body.id, 'name': body.name, 'deposits': deposits});
    }
    return {
      'id': d.id,
      'name': d.name,
      'kind': d.kind.name,
      'cost': _nums(d.buildCost),
      'crewSlots': d.crewSlots,
      'inputsPerSec': _rates(recipe.inputs),
      'outputsPerSec': _rates(recipe.outputs),
      if (d.housing > 0) 'housing': d.housing,
      if (d.storageBonus > 0) 'storageBonus': d.storageBonus,
      'canBuildOn': hosts,
    };
  }

  /// Where a contract delivery's goods came from: "from Kora" for one
  /// body, "(2K from Kora, 500 from Brine)" for a delivery from every body.
  String _fromText(ContractProgress o) {
    if (o.bodyId case final id?) return 'from ${state.body(id).name}';
    final parts = [
      for (final MapEntry(key: b, value: v) in o.fromBodies.entries)
        '${formatNumber(v)} from ${state.body(b).name}',
    ];
    return '(${parts.join(', ')})';
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
            '${_list(o.remaining, rounding: NumberRounding.up)}',
    };
  }

  /// How [o] left a megaproject fed: "Orbital Station now takes goods
  /// from every body each game minute, above what each keeps for its own
  /// use and open contracts, and a share of the credits above the
  /// auto-pay reserve (5M)"; with goods near ready, "… now takes goods
  /// from every body each game minute once a stage is near ready (its
  /// credits due within 12h), …"; "… and no credits", "… takes a share of
  /// the credits above the auto-pay reserve (5M) each game minute, and no
  /// goods", or "Orbital Station is fed by hand only". A weight other than
  /// 1 reads "a share, at weight 3, of the credits …"; weight 0 "the
  /// credits … only when nothing else takes them (weight 0)".
  String _autoText(MegaprojectAutoSet o) {
    final name = _megaprojectName(o.megaprojectId);
    final credits = o.credits ? _creditShare(o.creditWeight) : 'no credits';
    final goods = switch (o.goods) {
      GoodsFeedMode.off => null,
      GoodsFeedMode.always => 'goods from every body each game minute',
      GoodsFeedMode.nearReady =>
        'goods from every body each game minute once a stage is near '
            'ready (${_nearReadyText()})',
    };
    if (goods != null) {
      return '$name now takes $goods, above what each keeps for its own '
          'use and open contracts, and $credits';
    }
    if (o.credits) {
      return '$name now takes $credits each game minute, and no goods';
    }
    return '$name is fed by hand only';
  }

  /// "its credits due within 12h", the rules' near-ready horizon.
  String _nearReadyText() =>
      'its credits due within '
      '${formatDuration(engine.content.rules.nearReadyHorizonSeconds)}';

  /// "a share of the credits above the auto-pay reserve (5M)", the
  /// player's reserve; "a share, at weight 3, of the credits …" for a
  /// [weight] other than 1, and "the credits above the auto-pay reserve
  /// (5M) only when nothing else takes them (weight 0)" for 0.
  String _creditShare([int weight = 1]) {
    final above =
        'the credits above the auto-pay reserve '
        '(${formatNumber(_player.autoPayReserve)})';
    return switch (weight) {
      0 => '$above only when nothing else takes them (weight 0)',
      1 => 'a share of $above',
      _ => 'a share, at weight $weight, of $above',
    };
  }

  /// Display name of megaproject [id]; the id itself for one the content
  /// does not have.
  String _megaprojectName(String id) =>
      engine.content.megaprojects[id]?.name ?? id;

  /// What [m]'s bonuses add up to at [level], from the typed
  /// [megaprojectBonusesAt]: "level 3: storage +30%, housing +15%, offline
  /// cap +3h, market depth ×1.73", with " (tiers 0-1)" on a bonus limited
  /// to some tiers; "level 0: no bonus yet".
  String _bonusText(MegaprojectDef m, int level) {
    if (level == 0) return 'level 0: no bonus yet';
    String pct(double v) => '+${_short(v)}%';
    String times(double v) => '×${_short(v)}';
    final parts = [
      for (final b in megaprojectBonusesAt(m, level))
        '${switch (b.kind) {
          BonusKind.storagePercent => 'storage ${pct(b.value)}',
          BonusKind.housingPercent => 'housing ${pct(b.value)}',
          BonusKind.offlineCapSeconds => 'offline cap +${formatDuration(b.value)}',
          BonusKind.outputPercent => 'output ${pct(b.value)}',
          BonusKind.marketDepthPercent => 'market depth ${pct(b.value)}',
          BonusKind.marketDepthMultiplier => 'market depth ${times(b.value)}',
          BonusKind.productionSpeedMultiplier => 'production speed ${times(b.value)}',
          BonusKind.salePriceMultiplier => 'sale price ${times(b.value)}',
        }}${_tiersText(b.appliesToMinTier ?? 0, b.appliesToMaxTier)}',
    ];
    return 'level $level: ${parts.join(', ')}';
  }

  /// The tiers a bonus applies to, [from] to [to] (null for the top), as
  /// " (tier 0)", " (tiers 0-2)", " (tiers 1-2)", " (tiers 2 and up)", or
  /// nothing for every tier.
  static String _tiersText(int from, int? to) => switch ((from, to)) {
    (0, null) => '',
    (_, null) => ' (tiers $from and up)',
    (_, final t?) when t == from => ' (tier $t)',
    (_, final t?) => ' (tiers $from-$t)',
  };

  /// [v] with at most two decimals, trailing zeros dropped: 1.728 as
  /// "1.73", 1.1 as "1.1", 30 as "30".
  static String _short(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// Why the player cannot deliver to [m] yet: "opens at Orbital Station
  /// level 2 (now 1)"; null once it is open.
  String? _lockedText(MegaprojectDef m) {
    final lock = megaprojectLockedBy(state, engine.content, _player.id, m);
    if (lock == null) return null;
    final name = engine.content.megaprojects[lock.megaprojectId]!.name;
    return 'opens at $name level ${lock.level} '
        '(now ${_level(_player.id, lock.megaprojectId)})';
  }

  /// [auto] as "goods from every body, and a share of the credits above
  /// the auto-pay reserve (1M)", "goods from every body once a stage is
  /// near ready (its credits due within 12h), and …" (with ", fed now" or
  /// ", not fed yet" after the bracket), "goods from every body, and no
  /// credits" or "a share of the credits above the auto-pay reserve (1M),
  /// and no goods"; the weight as in [_creditShare].
  String _autoSetting(MegaprojectDef m, MegaprojectAuto auto) {
    final credits = auto.credits
        ? _creditShare(auto.creditWeight)
        : 'no credits';
    return switch (auto.goods) {
      GoodsFeedMode.off => '$credits, and no goods',
      GoodsFeedMode.always => 'goods from every body, and $credits',
      GoodsFeedMode.nearReady =>
        'goods from every body once a stage is near ready '
            '(${_nearReadyText()}), '
            '${megaprojectGoodsFed(state, _player, m) ? 'fed now' : 'not fed yet'}'
            ', and $credits',
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
        'catalog' => _catalog(),
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
      'headline': awayHeadline(sum, engine.content),
      'secondsAway': sum.secondsAway,
      'secondsSimulated': sum.secondsSimulated,
      'capSeconds': sum.capSeconds,
      'capped': sum.capped,
      'creditsGained': _num(sum.creditsGained),
      'creditsEarned': _num(sum.creditsEarned),
      'creditsPaidIn': _num(sum.creditsPaidIn),
      'stockGained': _nums(sum.stockGained),
      'totalWasted': _num(sum.totalWasted),
      'wastedValue': _num(sum.wastedValue),
      'housingBefore': sum.housingBefore.toJson(),
      'housingAfter': sum.housingAfter.toJson(),
      'creditsPerSecBefore': _num(sum.creditsPerSecBefore),
      'creditsPerSecAfter': _num(sum.creditsPerSecAfter),
      'milestonesReached': [
        for (final id in sum.milestonesReached) {'id': id, 'name': names[id]},
      ],
      'topBottlenecks': [
        for (final n in sum.topBottlenecks)
          _bottleneck(n, ongoing: sum.ongoingFor(n)),
      ],
      if (sum.nextGoal case final goal?) 'nextGoal': _goal(goal),
      'autoDelivered': [
        for (final MapEntry(key: id, value: got) in sum.autoDelivered.entries)
          {
            'id': id,
            'name': _megaprojectName(id),
            'delivered': _nums(got),
            'message': '${_megaprojectName(id)} got ${_list(got)}',
          },
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

  /// [goal] as JSON, with a `message` for the player such as "Next: First
  /// Foundry (Make 30 Steel), 12 of 30, in 1m 30s" or "Next: Orbital
  /// Station level 1 still needs 5M credits and 200 Station Segment; in
  /// 40m".
  Map<String, Object?> _goal(NextGoal goal) {
    final c = engine.content;
    final eta = switch (goal.etaSeconds) {
      null => 'not in reach at the current rates',
      final t when t <= 0 => 'you can start it now',
      final t => 'in ${formatDuration(t)}',
    };
    switch (goal) {
      case MilestoneGoal(:final milestoneId, :final current, :final target):
        final m = c.milestones.firstWhere((m) => m.id == milestoneId);
        return {
          'kind': 'milestone',
          'id': milestoneId,
          'name': m.name,
          'etaSeconds': goal.etaSeconds,
          'message':
              'Next: ${m.name} (${milestoneGoalText(c, m)}), '
              '${formatNumber(current, rounding: NumberRounding.down)} of '
              '${formatNumber(target)}, $eta',
        };
      case MegaprojectGoal(:final megaprojectId, :final level):
        final name = c.megaprojects[megaprojectId]!.name;
        return {
          'kind': 'megaproject',
          'id': megaprojectId,
          'name': name,
          'level': level,
          'etaSeconds': goal.etaSeconds,
          'message':
              'Next: $name level $level still needs '
              '${_list(goal.remaining, rounding: NumberRounding.up)}; $eta',
        };
    }
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
      if (r.autoDeliveredPerSec.isNotEmpty) ...{
        'autoDeliveredPerSec': {
          for (final MapEntry(key: m, value: got)
              in r.autoDeliveredPerSec.entries)
            m: _rates(got),
        },
        'autoDeliveredValuePerSec': _num(r.autoDeliveredValuePerSec),
      },
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
      // By cause: one entry for every building held back the same way on a
      // body, with the megaproject kinds.
      'bottlenecks': [for (final n in r.groupedBottlenecks) _bottleneck(n)],
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
    final throughput = routeThroughputs(state, c);
    return {
      'ok': true,
      'time': state.time,
      'credits': _num(p.credits),
      'autoPayReserve': _num(p.autoPayReserve),
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
            'bonuses': _bonusText(m, _level(p.id, m.id)),
            'nextLevel': _bonusText(m, _level(p.id, m.id) + 1),
            'locked': ?_lockedText(m),
            if (p.megaprojectAuto[m.id] case final auto?)
              'auto': {
                'goods': auto.goods.name,
                'credits': auto.credits,
                'creditWeight': auto.creditWeight,
                if (auto.goods == GoodsFeedMode.nearReady)
                  'goodsFedNow': megaprojectGoodsFed(state, p, m),
                'text': _autoSetting(m, auto),
              },
            if (p.megaprojectProgress[m.id] case final got?) ...{
              'delivered': _nums(got, rounding: NumberRounding.down),
              'stillNeeded': _nums(
                megaprojectRemaining(state, c, p.id, m),
                rounding: NumberRounding.up,
              ),
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
            'delivered': _num(k.delivered, rounding: NumberRounding.down),
            'reward': _num(k.rewardCredits),
          },
      ],
      // A refill already due waits for something a contract can ask for;
      // it is counted apart rather than shown due in "0s".
      'contractRefills': [
        for (final t in p.contractRefillAt)
          if (t > state.time)
            {'at': t, 'timeLeft': formatDuration(t - state.time)},
      ],
      if (p.contractRefillAt.where((t) => t <= state.time).length case final due
          when due > 0)
        'contractsDue': {
          'count': due,
          'note': 'Posted as soon as you make something a contract can ask for',
        },
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
              if (routeStopTarget(state, c, r) case final target?) ...{
                // The stock the store keeps, cargo on its way included,
                // shared by every stop-level route into it and timed by
                // the farthest of them.
                'stopTarget': _num(target),
                'stopSharedWith': [
                  for (final o in state.routes)
                    if (o != r &&
                        o.stopAtDestination != null &&
                        o.toBodyId == r.toBodyId &&
                        o.resourceId == r.resourceId)
                      o.id,
                ],
              },
              'paused': routePaused(state, c, r),
              // The most it carries a second now, and what holds it there.
              'throughput': _num(BigNum.from(throughput[r.id]!.perSec)),
              'limitedBy': throughput[r.id]!.binding.name,
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
            // A survey's hidden target stays unnamed until it is found.
            if (pr.kind != ProjectKind.survey ||
                state.body(pr.targetId).surveyed)
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
              // What the player's sales earn: the price with the sale
              // bonuses its megaproject levels give.
              'salePrice': _num(salePrice(state, c, p.id, id)),
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
  /// ([autoSellKeep]): "keeps 34 (keepAtLeast 10 + 24 local use)", with
  /// " + 200 for open contracts" when the rule's body holds back what open
  /// contracts still need, " + 20K for megaprojects" for what megaprojects
  /// fed on their own still need, and ", cut to the storage cap" inside
  /// the brackets when the cap cut it.
  Map<String, Object?> _autoSellRule(AutoSellRule rule) {
    final k = autoSellKeep(state, engine.content, rule, 60);
    final held = k.contractHold.isZero
        ? ''
        : ' + ${formatNumber(k.contractHold)} for open contracts';
    final fed = k.megaprojectHold.isZero
        ? ''
        : ' + ${formatNumber(k.megaprojectHold)} for megaprojects';
    final cut = k.cappedAtStorage ? ', cut to the storage cap' : '';
    return {
      'bodyId': rule.bodyId,
      'resourceId': rule.resourceId,
      'keepAtLeast': _num(k.keepAtLeast),
      'localUse': _num(k.localUse),
      'contractHold': _num(k.contractHold),
      'megaprojectHold': _num(k.megaprojectHold),
      'keeps': _num(k.keeps),
      'text':
          'keeps ${formatNumber(k.keeps)} (keepAtLeast '
          '${formatNumber(k.keepAtLeast)} + ${formatNumber(k.localUse)} '
          'local use$held$fed$cut)',
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
    if (_lockedText(m) case final why?) return 'locked: $why';
    final level = megaprojectDeliveryLevel(state, p.id, m);
    final running = megaprojectStageOf(state, p.id, m.id);
    if (level >= SaveCodec.maxMegaprojectLevel) {
      return running == null
          ? 'at its highest level'
          : 'busy: level $level, its highest, is under way, done in '
                '${_until(running.finishAt)}';
    }
    if (running != null && megaprojectStageQueued(state, c, p.id, m)) {
      return 'busy: level ${level + 1} is paid for and starts when level '
          '$level is done, in ${_until(running.finishAt)}';
    }
    return {
      'nextLevel': level + 1,
      'cost': _nums(megaprojectCost(c, m, level)),
      if (p.megaprojectProgress.containsKey(m.id))
        'stillNeeded': _nums(
          megaprojectRemaining(state, c, p.id, m),
          rounding: NumberRounding.up,
        ),
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
