import 'dart:convert';

import '../content/content.dart';
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
  /// every content id against [content] and every body reference against the
  /// save's own bodies; never throws.
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
    return SaveOk(state);
  }

  static String? _unknownId(GameState s, Content c) {
    bool resource(String? id) => id == null || c.resources.containsKey(id);
    final bodyIds = {for (final b in s.bodies) b.id};
    for (final b in s.bodies) {
      if (!c.bodyTypes.containsKey(b.typeId)) {
        return 'body ${b.id}: unknown body type ${b.typeId}';
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
      if (!s.factions.any((f) => f.id == sh.ownerId)) {
        return 'shipment on ${sh.routeId}: unknown faction ${sh.ownerId}';
      }
      if (!resource(sh.resourceId)) {
        return 'shipment on ${sh.routeId}: unknown resource ${sh.resourceId}';
      }
    }
    return null;
  }
}
