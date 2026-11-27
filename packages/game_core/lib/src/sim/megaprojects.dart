import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';

/// The permanent bonuses a faction's megaproject levels add up to.
///
/// The one place a bonus becomes a multiplier: every formula a bonus
/// touches reads it from [bonusesFor] through the getters here.
final class EmpireBonuses {
  /// Creates bonus totals; each defaults to none.
  const EmpireBonuses({
    this.storagePercent = 0,
    this.housingPercent = 0,
    this.offlineCapSeconds = 0,
    this.outputPercent = 0,
    this.marketDepthPercent = 0,
  });

  /// No bonuses, as for a faction with no megaproject levels or a body
  /// nobody owns.
  static const EmpireBonuses none = EmpireBonuses();

  /// Percent added to every body's storage cap ([BonusKind.storagePercent]).
  final double storagePercent;

  /// Percent added to habitat housing ([BonusKind.housingPercent]).
  final double housingPercent;

  /// Seconds added to the offline cap ([BonusKind.offlineCapSeconds]),
  /// before the cap's clamp; see [offlineCapFor].
  final double offlineCapSeconds;

  /// Percent added to building output ([BonusKind.outputPercent]).
  final double outputPercent;

  /// Percent added to market depth on sales ([BonusKind.marketDepthPercent]).
  final double marketDepthPercent;

  /// Multiplier on a body's storage cap: `1 + storagePercent / 100`.
  double get storageMultiplier => 1 + storagePercent / 100;

  /// Multiplier on habitat housing: `1 + housingPercent / 100`.
  double get housingMultiplier => 1 + housingPercent / 100;

  /// Multiplier on what buildings make: `1 + outputPercent / 100`.
  double get outputMultiplier => 1 + outputPercent / 100;

  /// Multiplier on a resource's market depth for this faction's sales:
  /// `1 + marketDepthPercent / 100`.
  double get marketDepthMultiplier => 1 + marketDepthPercent / 100;
}

/// The bonuses [factionId] has from its megaproject levels: each
/// megaproject's [MegaprojectDef.bonusesPerLevel] times its level, summed
/// over the megaprojects in content order.
///
/// A null [factionId] (an unowned body) and a faction that does not exist
/// have [EmpireBonuses.none].
EmpireBonuses bonusesFor(GameState s, Content c, String? factionId) {
  if (factionId == null || c.megaprojects.isEmpty) return EmpireBonuses.none;
  final levels = _levelsOf(s, factionId);
  if (levels == null || levels.isEmpty) return EmpireBonuses.none;
  var storage = 0.0;
  var housing = 0.0;
  var offline = 0.0;
  var output = 0.0;
  var depth = 0.0;
  for (final m in c.megaprojects.values) {
    final level = levels[m.id] ?? 0;
    if (level == 0) continue;
    for (final b in m.bonusesPerLevel) {
      final add = b.amount * level;
      switch (b.kind) {
        case BonusKind.storagePercent:
          storage += add;
        case BonusKind.housingPercent:
          housing += add;
        case BonusKind.offlineCapSeconds:
          offline += add;
        case BonusKind.outputPercent:
          output += add;
        case BonusKind.marketDepthPercent:
          depth += add;
      }
    }
  }
  return EmpireBonuses(
    storagePercent: storage,
    housingPercent: housing,
    offlineCapSeconds: offline,
    outputPercent: output,
    marketDepthPercent: depth,
  );
}

Map<String, int>? _levelsOf(GameState s, String factionId) {
  for (final f in s.factions) {
    if (f.id == factionId) return f.megaprojectLevels;
  }
  return null;
}

/// Longest offline catch-up for [factionId], in seconds:
/// `rules.offlineCapSeconds` plus its [EmpireBonuses.offlineCapSeconds],
/// at most [RulesDef.maxOfflineCapSeconds].
double offlineCapFor(GameState s, Content c, String factionId) => math.min(
  RulesDef.maxOfflineCapSeconds,
  c.rules.offlineCapSeconds + bonusesFor(s, c, factionId).offlineCapSeconds,
);

/// Cost of the stage that takes [m] from [level] to `level + 1`:
/// `baseCost × costGrowth^level`, each entry; the key `credits` or a
/// resource id, as in [MegaprojectDef.baseCost].
///
/// [BigNum] keeps it finite at any level a save may hold.
Map<String, BigNum> megaprojectCost(Content c, MegaprojectDef m, int level) {
  final growth = BigNum.from(m.costGrowth).powInt(level);
  return {
    for (final MapEntry(key: id, value: base) in m.baseCost.entries)
      id: base * growth,
  };
}

/// The level from which the stage [factionId]'s deliveries to [m] pay
/// for starts: its level of [m], or one more while a stage of [m] is under
/// way, since that stage is paid for and deliveries go to the one after
/// it. A faction that does not exist is at level 0.
int megaprojectDeliveryLevel(GameState s, String factionId, MegaprojectDef m) {
  final level = _levelsOf(s, factionId)?[m.id] ?? 0;
  return megaprojectStageOf(s, factionId, m.id) == null ? level : level + 1;
}

/// What [factionId] still owes toward the stage of [m] its deliveries pay
/// for (from [megaprojectDeliveryLevel]): each entry of that level's
/// [megaprojectCost] less what has been delivered toward it
/// (`FactionState.megaprojectProgress`), in cost order; entries delivered
/// in full are left out, so it is empty once nothing is owed. While a
/// stage is under way, that is the stage after it, which starts when the
/// one under way completes if it is paid for in full by then. A faction
/// that does not exist owes level 0's full cost.
Map<String, BigNum> megaprojectRemaining(
  GameState s,
  Content c,
  String factionId,
  MegaprojectDef m,
) {
  FactionState? f;
  for (final x in s.factions) {
    if (x.id == factionId) f = x;
  }
  final level = megaprojectDeliveryLevel(s, factionId, m);
  final got = f?.megaprojectProgress[m.id] ?? const <String, BigNum>{};
  return {
    for (final MapEntry(key: id, value: need) in megaprojectCost(
      c,
      m,
      level,
    ).entries)
      if (need - (got[id] ?? const BigNum.zero()) case final left
          when left > const BigNum.zero())
        id: left,
  };
}

/// Whether [factionId]'s next stage of [m] is paid for in full while one
/// is still under way, so it starts when that one completes.
bool megaprojectStageQueued(
  GameState s,
  Content c,
  String factionId,
  MegaprojectDef m,
) {
  if (megaprojectStageOf(s, factionId, m.id) == null) return false;
  final f = s.factions.where((x) => x.id == factionId).firstOrNull;
  return f != null &&
      f.megaprojectProgress.containsKey(m.id) &&
      megaprojectRemaining(s, c, factionId, m).isEmpty;
}

/// Seconds the stage that takes [m] from [level] to `level + 1` takes:
/// `stageSeconds × stageSecondsGrowth^level`, clamped to
/// [[RulesDef.minProjectSeconds], [RulesDef.maxProjectSeconds]].
double megaprojectStageSeconds(MegaprojectDef m, int level) =>
    (m.stageSeconds * math.pow(m.stageSecondsGrowth, level).toDouble()).clamp(
      RulesDef.minProjectSeconds,
      RulesDef.maxProjectSeconds,
    );

/// The stage of megaproject [megaprojectId] [factionId] has under way, or
/// null.
ProjectState? megaprojectStageOf(
  GameState s,
  String factionId,
  String megaprojectId,
) {
  for (final p in s.projects) {
    if (p.kind == ProjectKind.megaprojectStage &&
        p.factionId == factionId &&
        p.targetId == megaprojectId) {
      return p;
    }
  }
  return null;
}
