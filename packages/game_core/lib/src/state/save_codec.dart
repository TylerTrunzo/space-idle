import 'dart:convert';
import 'dart:math' as math;

import '../commands/apply.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../report/flow_report.dart';
import '../sim/production.dart';
import '../sim/market.dart';
import '../sim/megaprojects.dart';
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
    _snapStockResidue(state, content);
    final invalid = _invalidValue(state, content);
    if (invalid != null) return SaveError(SaveErrorKind.invalidValue, invalid);
    return SaveOk(state);
  }

  /// Largest number an engine-made id such as `b7` may end in: 2^53 − 1,
  /// the largest integer exact on every platform.
  static const int _maxIdNumber = 9007199254740991;

  /// Most extra build slots a save may hold on one body.
  static const int maxExtraSlots = 1000;

  /// Highest upgrade level a save may hold on any track.
  static const int maxLevel = 1000;

  /// Highest level a save may hold of any megaproject; no stage starts
  /// from it.
  static const int maxMegaprojectLevel = 1000;

  /// Names a [SeenBottleneck.kind] may take.
  static final Set<String> bottleneckKinds = {
    for (final k in BottleneckKind.values) k.name,
  };

  /// Sets to zero each stock in [s] that lies below zero by no more than
  /// [takeResidue] times its body's [storageCap] (at least 1): float
  /// residue that older engine builds wrote, which [_invalidValue] would
  /// otherwise reject. A larger negative is left for it to reject.
  static void _snapStockResidue(GameState s, Content c) {
    for (final b in s.bodies) {
      final scale = storageCap(s, c, b).max(BigNum.from(1));
      final limit = -scale.mulDouble(takeResidue);
      for (final MapEntry(key: id, value: v) in b.stock.entries.toList()) {
        if (v.isNegative && v >= limit) b.stock[id] = const BigNum.zero();
      }
    }
  }

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
      for (final MapEntry(key: id, value: v) in f.salesRevenue.entries) {
        if (v < zero) return 'faction ${f.id}: negative sales revenue of $id';
      }
      if (f.lifetimeCredits < zero) {
        return 'faction ${f.id}: negative lifetime credits';
      }
      for (final MapEntry(key: id, value: v) in f.lifetimeProduced.entries) {
        if (v < zero) return 'faction ${f.id}: negative lifetime $id made';
      }
      final seen = <String>{};
      for (final b in f.seenBottlenecks) {
        if (!bottleneckKinds.contains(b.kind)) {
          return 'faction ${f.id}: unknown bottleneck kind ${b.kind}';
        }
        if (!seen.add(b.key)) {
          return 'faction ${f.id}: bottleneck ${b.key} listed twice';
        }
        if (!(b.firstSeenAt >= 0 && b.firstSeenAt <= s.time)) {
          return 'faction ${f.id}: bottleneck ${b.key} first seen at '
              '${b.firstSeenAt}, outside [0, ${s.time}]';
        }
      }
      for (final MapEntry(key: id, value: level)
          in f.megaprojectLevels.entries) {
        if (level < 0 || level > maxMegaprojectLevel) {
          return 'faction ${f.id}: $id level $level outside '
              '[0, $maxMegaprojectLevel]';
        }
      }
      for (final id in f.megaprojectProgress.keys) {
        final why = _invalidProgress(s, c, f, c.megaprojects[id]!);
        if (why != null) return 'faction ${f.id}: $id progress $why';
      }
      if (!f.wasteFreeSince.isFinite ||
          f.wasteFreeSince < 0 ||
          f.wasteFreeSince > s.time) {
        return 'faction ${f.id}: waste-free since ${f.wasteFreeSince}, '
            'outside [0, ${s.time}]';
      }
      if (f.contractsCompleted < 0) {
        return 'faction ${f.id}: negative contracts completed';
      }
      if (f.contracts.length > RulesDef.contractSlots) {
        return 'faction ${f.id}: ${f.contracts.length} contracts, at most '
            '${RulesDef.contractSlots}';
      }
      if (f.contractRefillAt.length > RulesDef.contractSlots) {
        return 'faction ${f.id}: ${f.contractRefillAt.length} contract '
            'refills, at most ${RulesDef.contractSlots}';
      }
      if (f.contracts.length + f.contractRefillAt.length >
          RulesDef.contractSlots) {
        return 'faction ${f.id}: ${f.contracts.length} contracts and '
            '${f.contractRefillAt.length} refills, at most '
            '${RulesDef.contractSlots} together';
      }
      double? previousRefill;
      for (final t in f.contractRefillAt) {
        if (!(t.isFinite && t >= 0)) {
          return 'faction ${f.id}: contract refill at $t';
        }
        if (previousRefill != null && t < previousRefill) {
          return 'faction ${f.id}: contract refills not in ascending order '
              '($previousRefill then $t)';
        }
        previousRefill = t;
      }
      for (final k in f.contracts) {
        final problem = _invalidContract(s, k);
        if (problem != null) return 'contract ${k.id}: $problem';
      }
      final rules = <(String, String)>{};
      for (final r in f.autoSell) {
        if (r.keepAtLeast < zero) {
          return 'faction ${f.id}: negative keepAtLeast for ${r.resourceId}';
        }
        if (!rules.add((r.bodyId, r.resourceId))) {
          return 'faction ${f.id}: two auto-sell rules for ${r.resourceId} '
              'on ${r.bodyId}';
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
      if (!b.surveyed &&
          (owner != null ||
              b.buildings.isNotEmpty ||
              b.stock.values.any((v) => !v.isZero))) {
        return 'body ${b.id}: unsurveyed, yet owned or built on';
      }
      if (b.extraSlots < 0 || b.extraSlots > maxExtraSlots) {
        return 'body ${b.id}: extra slots ${b.extraSlots} outside '
            '[0, $maxExtraSlots]';
      }
      final slots = buildSlots(c, b);
      if (b.buildings.length > slots) {
        return 'body ${b.id}: ${b.buildings.length} buildings in $slots slots';
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
      if (r.stopAtDestination case final stop? when stop <= zero) {
        return 'route ${r.id}: stop level not above 0';
      }
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
    final contractIds = <String>{};
    for (final f in s.factions) {
      for (final k in f.contracts) {
        final dup = checkId(contractIds, 'contract', k.id);
        if (dup != null) return dup;
      }
    }
    final projectIds = <String>{};
    // A body has at most one claim, one survey and one slot expansion under
    // way, and a faction at most one stage of each megaproject.
    final underWay = <(ProjectKind, String, String?)>{};
    for (final p in s.projects) {
      final dup = checkId(projectIds, 'project', p.id);
      if (dup != null) return dup;
      final problem = _invalidProject(s, factionIds, p);
      if (problem != null) return 'project ${p.id}: $problem';
      final key = switch (p.kind) {
        ProjectKind.claim ||
        ProjectKind.expandSlots => (p.kind, p.targetId, null),
        ProjectKind.megaprojectStage => (p.kind, p.targetId, p.factionId),
        ProjectKind.survey => (p.kind, p.targetId, null),
      };
      if (!underWay.add(key)) {
        return 'project ${p.id}: a second ${p.kind.name} of ${p.targetId}';
      }
    }
    if (s.nextId <= highestSuffix) {
      return 'nextId ${s.nextId} is not above id suffix $highestSuffix';
    }

    for (final MapEntry(key: id, value: v) in s.market.saturation.entries) {
      final floor = marketFloorOf(c, id);
      if (!(v >= floor && v <= 1)) {
        return 'market: saturation of $id is $v, outside [$floor, 1]';
      }
    }
    return null;
  }

  /// What is wrong with project [p] in [s], whose faction ids are
  /// [factionIds], or null if nothing is. Its target is known to exist.
  static String? _invalidProject(
    GameState s,
    Set<String> factionIds,
    ProjectState p,
  ) {
    if (!factionIds.contains(p.factionId)) {
      return 'owner ${p.factionId} is not a faction';
    }
    if (!(p.startedAt >= 0 && p.startedAt <= s.time)) {
      return 'started at ${p.startedAt}, outside [0, ${s.time}]';
    }
    if (!(p.finishAt.isFinite && p.finishAt >= p.startedAt)) {
      return 'finishes at ${p.finishAt}, not at or after its start';
    }
    switch (p.kind) {
      case ProjectKind.claim:
        final target = s.body(p.targetId);
        if (target.ownerId != null) {
          return 'claims ${p.targetId}, owned by ${target.ownerId}';
        }
        if (!target.surveyed) return 'claims ${p.targetId}, unsurveyed';
      case ProjectKind.expandSlots:
        final body = s.body(p.targetId);
        if (body.ownerId != p.factionId) {
          return 'expands ${body.id}, which ${p.factionId} does not own';
        }
        if (body.extraSlots >= maxExtraSlots) {
          return 'expands ${body.id} past $maxExtraSlots extra slots';
        }
      case ProjectKind.megaprojectStage:
        final level = s.faction(p.factionId).megaprojectLevels[p.targetId] ?? 0;
        if (level >= maxMegaprojectLevel) {
          return 'builds ${p.targetId} past level $maxMegaprojectLevel';
        }
      case ProjectKind.survey:
        if (s.body(p.targetId).surveyed) {
          return 'surveys ${p.targetId}, which is surveyed already';
        }
    }
    return null;
  }

  /// What is wrong with what [f] has delivered toward [m]'s next stage, or
  /// null if nothing is: every amount a key of the cost of the stage
  /// deliveries pay for (`megaprojectDeliveryLevel`: the one after a stage
  /// under way), at least zero and at most the cost, and a level below the
  /// highest. Complete progress is valid only while a stage is under way,
  /// which the paid-for stage follows.
  static String? _invalidProgress(
    GameState s,
    Content c,
    FactionState f,
    MegaprojectDef m,
  ) {
    final level = megaprojectDeliveryLevel(s, f.id, m);
    if (level >= maxMegaprojectLevel) return 'past level $maxMegaprojectLevel';
    final cost = megaprojectCost(c, m, level);
    for (final MapEntry(key: id, value: v)
        in f.megaprojectProgress[m.id]!.entries) {
      final need = cost[id];
      if (need == null) return 'in $id, which the stage does not take';
      if (v < const BigNum.zero() || v > need) {
        return 'of $id is $v, outside [0, $need]';
      }
    }
    if (megaprojectStageOf(s, f.id, m.id) == null &&
        megaprojectRemaining(s, c, f.id, m).isEmpty) {
      return 'complete with no stage started';
    }
    return null;
  }

  /// What is wrong with contract [k] in [s], or null if nothing is.
  static String? _invalidContract(GameState s, ContractState k) {
    const zero = BigNum.zero();
    if (k.quantity < zero) return 'negative quantity';
    if (k.delivered < zero) return 'negative delivery';
    if (k.delivered > k.quantity) {
      return 'delivered ${k.delivered} of ${k.quantity}';
    }
    if (k.rewardCredits < zero) return 'negative reward';
    if (!(k.postedAt >= 0 && k.postedAt <= s.time)) {
      return 'posted at ${k.postedAt}, outside [0, ${s.time}]';
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
      for (final id in f.salesRevenue.keys) {
        if (!resource(id)) {
          return 'faction ${f.id}: sales revenue of unknown resource $id';
        }
      }
      for (final id in f.lifetimeProduced.keys) {
        if (!resource(id)) {
          return 'faction ${f.id}: lifetime produced of unknown resource $id';
        }
      }
      for (final b in f.seenBottlenecks) {
        if (!resource(b.resourceId)) {
          return 'faction ${f.id}: bottleneck of unknown resource '
              '${b.resourceId}';
        }
        if (b.bodyId case final id? when !bodyIds.contains(id)) {
          return 'faction ${f.id}: bottleneck on unknown body $id';
        }
      }
      for (final k in f.contracts) {
        if (!resource(k.resourceId)) {
          return 'contract ${k.id}: unknown resource ${k.resourceId}';
        }
        if (!c.contractTemplates.containsKey(k.templateId)) {
          return 'contract ${k.id}: unknown template ${k.templateId}';
        }
      }
      for (final id in f.megaprojectLevels.keys) {
        if (!c.megaprojects.containsKey(id)) {
          return 'faction ${f.id}: level of unknown megaproject $id';
        }
      }
      for (final MapEntry(key: id, value: got)
          in f.megaprojectProgress.entries) {
        if (!c.megaprojects.containsKey(id)) {
          return 'faction ${f.id}: progress on unknown megaproject $id';
        }
        for (final k in got.keys) {
          if (k != 'credits' && !resource(k)) {
            return 'faction ${f.id}: $id progress in unknown resource $k';
          }
        }
      }
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
    for (final id in s.market.saturation.keys) {
      if (!resource(id)) return 'market: saturation of unknown resource $id';
    }
    for (final r in s.routes) {
      if (!resource(r.resourceId)) {
        return 'route ${r.id}: unknown resource ${r.resourceId}';
      }
      for (final id in [r.fromBodyId, r.toBodyId]) {
        if (!bodyIds.contains(id)) return 'route ${r.id}: unknown body $id';
      }
    }
    for (final p in s.projects) {
      final known = switch (p.kind) {
        ProjectKind.claim ||
        ProjectKind.expandSlots ||
        ProjectKind.survey => bodyIds.contains(p.targetId),
        ProjectKind.megaprojectStage => c.megaprojects.containsKey(p.targetId),
      };
      if (!known) {
        return 'project ${p.id}: unknown ${p.kind.name} target ${p.targetId}';
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
