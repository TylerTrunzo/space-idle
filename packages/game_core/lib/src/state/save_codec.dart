import 'dart:convert';
import 'dart:math' as math;

import '../commands/apply.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import 'game_state.dart';

/// Upgrades an older save map by one version.
typedef SaveMigration = Map<String, Object?> Function(Map<String, Object?>);

/// Built-in migrations keyed by the version they upgrade *from*.
///
/// Version 1 is current, so there are none yet.
const Map<int, SaveMigration> migrations = {};

/// Why a save could not be loaded.
enum SaveErrorKind {
  /// The text is not a JSON object.
  notJson,

  /// The save version is newer than, or cannot be migrated to, the current one.
  unknownVersion,

  /// A required field is missing or has the wrong type.
  missingField,

  /// The save names a content id that does not exist.
  unknownContentId,

  /// A value is out of range or the save contradicts itself, such as a
  /// body owned by a faction it does not list or crew above a building's
  /// slots; the engine could not run it.
  invalidValue,
}

/// Outcome of [SaveCodec.decode].
sealed class SaveResult {
  const SaveResult();
}

/// The save loaded.
final class SaveOk extends SaveResult {
  /// Wraps the loaded state.
  const SaveOk(this.state);

  /// The loaded state.
  final GameState state;
}

/// The save could not be loaded.
final class SaveError extends SaveResult {
  /// Creates an error.
  const SaveError(this.kind, this.message);

  /// Category of the failure.
  final SaveErrorKind kind;

  /// Human-readable detail.
  final String message;
}

/// Writes and reads versioned saves.
final class SaveCodec {
  const SaveCodec._();

  /// Serializes [s] to JSON text.
  static String encode(GameState s) => jsonEncode(s.toJson());

  /// Parses save [text], migrating old versions with [migrations], checking
  /// every content id against [content], every body reference against the
  /// save's own bodies, and that the state is one the engine can run (see
  /// [SaveErrorKind.invalidValue]); never throws.
  static SaveResult decode(
    String text,
    Content content, {
    Map<int, SaveMigration> migrations = migrations,
  }) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException catch (e) {
      return SaveError(SaveErrorKind.notJson, e.message);
    }
    if (raw is! Map) {
      return const SaveError(SaveErrorKind.notJson, 'not a JSON object');
    }
    var map = raw.cast<String, Object?>();
    var version = map['saveVersion'];
    if (version is! int) {
      return const SaveError(SaveErrorKind.missingField, 'saveVersion');
    }
    while (version != GameState.currentSaveVersion) {
      final step = migrations[version];
      if (step == null) {
        return SaveError(
          SaveErrorKind.unknownVersion,
          'cannot load save version $version',
        );
      }
      try {
        map = step(map);
      } on Object catch (e) {
        return SaveError(SaveErrorKind.missingField, 'migration failed: $e');
      }
      final next = map['saveVersion'];
      if (next is! int || next <= (version as int)) {
        return SaveError(
          SaveErrorKind.unknownVersion,
          'migration from $version did not advance the version',
        );
      }
      version = next;
    }
    for (final k in const ['bodies', 'factions']) {
      if (map[k] is! List) return SaveError(SaveErrorKind.missingField, k);
    }
    final GameState state;
    try {
      state = GameState.fromJson(map);
    } on Object catch (e) {
      return SaveError(SaveErrorKind.missingField, 'malformed save: $e');
    }
    final bad = _unknownId(state, content);
    if (bad != null) return SaveError(SaveErrorKind.unknownContentId, bad);
    final invalid = _invalidValue(state, content);
    if (invalid != null) return SaveError(SaveErrorKind.invalidValue, invalid);
    return SaveOk(state);
  }

  /// Largest number an engine-made id such as `b7` may end in: 2^53 − 1,
  /// the largest integer exact on every platform.
  static const int _maxIdNumber = 9007199254740991;

  /// Highest upgrade level a save may hold on any track.
  static const int maxLevel = 1000;

  /// The first broken integrity rule of [s], or null when it has none.
  ///
  /// Runs after [_unknownId], so every content id and body reference is
  /// known to resolve.
  static String? _invalidValue(GameState s, Content c) {
    const zero = BigNum.zero();
    if (!s.time.isFinite || s.time < 0) return 'time ${s.time}';

    final factionIds = <String>{};
    for (final f in s.factions) {
      if (!factionIds.add(f.id)) return 'duplicate faction ${f.id}';
      if (f.credits < zero) return 'faction ${f.id}: negative credits';
      if (f.baseCrew < 0) return 'faction ${f.id}: negative base crew';
      for (final r in f.autoSell) {
        if (r.keepAtLeast < zero) {
          return 'faction ${f.id}: negative keepAtLeast for ${r.resourceId}';
        }
      }
    }
    final players = s.factions.where((f) => f.isPlayer).length;
    if (players != 1) return '$players player factions, need exactly 1';

    // Ids the engine hands out, such as `b7`, must stay below nextId.
    var highestSuffix = 0;
    final suffix = RegExp(r'(\d+)$');
    String? checkId(Set<String> seen, String kind, String id) {
      if (!seen.add(id)) return 'duplicate $kind id $id';
      final m = suffix.firstMatch(id);
      if (m != null) {
        // Above 2^53 an id number is not exact on the web, and past 64 bits
        // it does not parse at all; no engine-made id gets near either.
        final n = int.tryParse(m.group(1)!);
        if (n == null || n > _maxIdNumber) {
          return '$kind id $id: number too large';
        }
        highestSuffix = math.max(highestSuffix, n);
      }
      return null;
    }

    final bodyIds = <String>{};
    final buildingIds = <String>{};
    for (final b in s.bodies) {
      if (!bodyIds.add(b.id)) return 'duplicate body id ${b.id}';
      final owner = b.ownerId;
      if (owner != null && !factionIds.contains(owner)) {
        return 'body ${b.id}: owner $owner is not a faction';
      }
      for (final d in b.deposits) {
        if (!(d.richness > 0) || !d.richness.isFinite) {
          return 'body ${b.id}: deposit ${d.resourceId} richness '
              '${d.richness}';
        }
      }
      for (final MapEntry(key: id, value: v) in b.stock.entries) {
        if (v < zero) return 'body ${b.id}: negative stock of $id';
      }
      for (final bl in b.buildings) {
        final dup = checkId(buildingIds, 'building', bl.id);
        if (dup != null) return dup;
        final problem = _invalidBuilding(c, b, bl);
        if (problem != null) return 'building ${bl.id}: $problem';
      }
    }

    final routeIds = <String>{};
    for (final r in s.routes) {
      final dup = checkId(routeIds, 'route', r.id);
      if (dup != null) return dup;
      if (!factionIds.contains(r.ownerId)) {
        return 'route ${r.id}: owner ${r.ownerId} is not a faction';
      }
      if (r.cargoShips < 1) return 'route ${r.id}: no cargo ships';
      if (r.ratePerSecond <= zero) return 'route ${r.id}: rate not above 0';
    }
    for (final sh in s.shipments) {
      if (!factionIds.contains(sh.ownerId)) {
        return 'shipment on ${sh.routeId}: owner ${sh.ownerId} is not a '
            'faction';
      }
      if (sh.amount < zero) return 'shipment on ${sh.routeId}: negative amount';
      if (!sh.departAt.isFinite || !sh.arriveAt.isFinite) {
        return 'shipment on ${sh.routeId}: time not finite';
      }
    }
    if (s.nextId <= highestSuffix) {
      return 'nextId ${s.nextId} is not above id suffix $highestSuffix';
    }

    final floor = c.rules.marketFloor;
    for (final MapEntry(key: id, value: v) in s.market.saturation.entries) {
      if (!(v >= floor && v <= 1)) {
        return 'market: saturation of $id is $v, outside [$floor, 1]';
      }
    }
    return null;
  }

  /// What is wrong with building [b] on [body], or null if nothing is.
  static String? _invalidBuilding(Content c, BodyState body, BuildingState b) {
    final def = c.buildings[b.defId]!;
    final max = maxCrew(c.rules, def, b);
    if (b.crew < 0 || b.crew > max) return 'crew ${b.crew} outside [0, $max]';
    for (final MapEntry(key: track, value: level) in b.levels.entries) {
      if (level < 0 || level > maxLevel) {
        return '${track.name} level $level outside [0, $maxLevel]';
      }
    }
    if (!(b.lastRunFraction >= 0 && b.lastRunFraction <= 1)) {
      return 'run fraction ${b.lastRunFraction} outside [0, 1]';
    }
    if (def.kind == BuildingKind.extractor) {
      final dep = b.depositResourceId;
      if (dep == null ||
          !def.extracts.contains(dep) ||
          !body.deposits.any((d) => d.resourceId == dep)) {
        return '${def.id} cannot mine ${dep ?? 'nothing'} on ${body.id}';
      }
    }
    return null;
  }

  static String? _unknownId(GameState s, Content c) {
    bool resource(String? id) => id == null || c.resources.containsKey(id);
    final bodyIds = {for (final b in s.bodies) b.id};
    final systemIds = {for (final sys in c.galaxy.systems) sys.id};
    for (final b in s.bodies) {
      if (!c.bodyTypes.containsKey(b.typeId)) {
        return 'body ${b.id}: unknown body type ${b.typeId}';
      }
      if (!systemIds.contains(b.systemId)) {
        return 'body ${b.id}: unknown system ${b.systemId}';
      }
      for (final d in b.deposits) {
        if (!resource(d.resourceId)) {
          return 'body ${b.id}: unknown deposit ${d.resourceId}';
        }
      }
      for (final r in b.stock.keys) {
        if (!resource(r)) return 'body ${b.id}: unknown resource $r';
      }
      for (final bl in b.buildings) {
        if (!c.buildings.containsKey(bl.defId)) {
          return 'building ${bl.id}: unknown building ${bl.defId}';
        }
        if (!resource(bl.depositResourceId)) {
          return 'building ${bl.id}: unknown deposit ${bl.depositResourceId}';
        }
      }
    }
    for (final f in s.factions) {
      for (final r in f.autoSell) {
        if (!bodyIds.contains(r.bodyId)) {
          return 'faction ${f.id}: auto-sell on unknown body ${r.bodyId}';
        }
        if (!resource(r.resourceId)) {
          return 'faction ${f.id}: auto-sell of unknown resource '
              '${r.resourceId}';
        }
      }
    }
    for (final r in s.routes) {
      if (!resource(r.resourceId)) {
        return 'route ${r.id}: unknown resource ${r.resourceId}';
      }
      for (final id in [r.fromBodyId, r.toBodyId]) {
        if (!bodyIds.contains(id)) return 'route ${r.id}: unknown body $id';
      }
    }
    for (final sh in s.shipments) {
      if (!bodyIds.contains(sh.toBodyId)) {
        return 'shipment on ${sh.routeId}: unknown body ${sh.toBodyId}';
      }
      if (!bodyIds.contains(sh.fromBodyId)) {
        return 'shipment on ${sh.routeId}: unknown body ${sh.fromBodyId}';
      }
      if (!resource(sh.resourceId)) {
        return 'shipment on ${sh.routeId}: unknown resource ${sh.resourceId}';
      }
    }
    return null;
  }
}
