import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import '../state/save_codec.dart';

/// The permanent bonuses a faction's megaproject levels add up to.
///
/// The one place a bonus becomes a multiplier: every formula a bonus
/// touches reads it from [bonusesFor] through the getters here.
final class EmpireBonuses {
  /// Creates bonus totals; each defaults to none. The factor lists hold
  /// one factor per resource tier, 0 to [ResourceDef.megaprojectTier].
  const EmpireBonuses({
    this.storagePercent = 0,
    this.housingPercent = 0,
    this.offlineCapSeconds = 0,
    this.outputPercent = 0,
    this.marketDepthPercent = 0,
    this.marketDepthFactors = _ones,
    this.productionSpeedFactors = _ones,
  });

  /// No bonuses, as for a faction with no megaproject levels or a body
  /// nobody owns.
  static const EmpireBonuses none = EmpireBonuses();

  /// The most a compounding bonus multiplies by, whatever the level: it
  /// keeps every multiplier finite at any level a save may hold.
  static const double maxMultiplier = 1e6;

  static const List<double> _ones = [1, 1, 1, 1, 1];

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

  /// Per resource tier, the compounded [BonusKind.marketDepthMultiplier]
  /// factors, each at most [maxMultiplier].
  final List<double> marketDepthFactors;

  /// Per building tier (the highest tier it makes), the compounded
  /// [BonusKind.productionSpeedMultiplier] factors, each at most
  /// [maxMultiplier].
  final List<double> productionSpeedFactors;

  /// Multiplier on a body's storage cap: `1 + storagePercent / 100`.
  double get storageMultiplier => 1 + storagePercent / 100;

  /// Multiplier on habitat housing: `1 + housingPercent / 100`.
  double get housingMultiplier => 1 + housingPercent / 100;

  /// Multiplier on what buildings make: `1 + outputPercent / 100`.
  double get outputMultiplier => 1 + outputPercent / 100;

  /// Multiplier on the market depth of this faction's sales of a resource
  /// of [tier]: `1 + marketDepthPercent / 100` times the
  /// [marketDepthFactors] of that tier.
  double marketDepthMultiplierFor(int tier) =>
      (1 + marketDepthPercent / 100) * marketDepthFactors[tier];

  /// Multiplier on the cycle rate of a building of [tier] (the highest
  /// tier it makes; see `buildingTier`): its [productionSpeedFactors]; 1
  /// for a null tier, a building that makes nothing.
  double productionSpeedFor(int? tier) =>
      tier == null ? 1 : productionSpeedFactors[tier];
}

/// The bonuses [factionId] has from its megaproject levels: each
/// megaproject's [MegaprojectDef.bonusesPerLevel] at its level, summed
/// over the megaprojects in content order. Percent and seconds bonuses add
/// up, `amount × level`; multiplier bonuses compound, `amount^level`, and
/// multiply together on each tier they apply to, at most
/// [EmpireBonuses.maxMultiplier] per tier.
///
/// A null [factionId] (an unowned body) and a faction that does not exist
/// have [EmpireBonuses.none].
EmpireBonuses bonusesFor(GameState s, Content c, String? factionId) {
  if (factionId == null || c.megaprojects.isEmpty) return EmpireBonuses.none;
  final levels = _levelsOf(s, factionId);
  if (levels == null || levels.isEmpty) return EmpireBonuses.none;
  // The totals depend on the levels alone, and the engine reads them many
  // times a tick: they are kept with the levels map until it changes.
  final ms = c.megaprojects.values;
  if (_bonusCache[levels] case (
    final Content of,
    final List<int> at,
    final EmpireBonuses cached,
  ) when identical(of, c)) {
    var i = 0;
    var same = true;
    for (final m in ms) {
      if ((levels[m.id] ?? 0) != at[i++]) {
        same = false;
        break;
      }
    }
    if (same) return cached;
  }
  final bonuses = _bonusesAt(c, levels);
  _bonusCache[levels] = (c, [for (final m in ms) levels[m.id] ?? 0], bonuses);
  return bonuses;
}

/// A faction's levels map to the content, the levels (in content order)
/// and the [bonusesFor] totals they were last worked out for.
final _bonusCache = Expando<(Content, List<int>, EmpireBonuses)>('bonuses');

/// [bonusesFor] a faction at megaproject [levels].
EmpireBonuses _bonusesAt(Content c, Map<String, int> levels) {
  var storage = 0.0;
  var housing = 0.0;
  var offline = 0.0;
  var output = 0.0;
  var depth = 0.0;
  // Natural logs of the compounded factors, per tier, so a high level
  // never overflows before the clamp.
  const tiers = ResourceDef.megaprojectTier + 1;
  final depthLogs = List<double>.filled(tiers, 0);
  final speedLogs = List<double>.filled(tiers, 0);
  for (final m in c.megaprojects.values) {
    final level = levels[m.id] ?? 0;
    if (level == 0) continue;
    for (final b in m.bonusesPerLevel) {
      final add = b.amount * level;
      void compound(List<double> logs) {
        final top = b.appliesToMaxTier ?? ResourceDef.megaprojectTier;
        for (var t = 0; t <= top; t++) {
          logs[t] += level * math.log(b.amount);
        }
      }

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
        case BonusKind.marketDepthMultiplier:
          compound(depthLogs);
        case BonusKind.productionSpeedMultiplier:
          compound(speedLogs);
      }
    }
  }
  return EmpireBonuses(
    storagePercent: storage,
    housingPercent: housing,
    offlineCapSeconds: offline,
    outputPercent: output,
    marketDepthPercent: depth,
    marketDepthFactors: _factors(depthLogs),
    productionSpeedFactors: _factors(speedLogs),
  );
}

/// The factors whose natural logs are [logs], each at most
/// [EmpireBonuses.maxMultiplier].
List<double> _factors(List<double> logs) =>
    List.unmodifiable([for (final l in logs) _compounded(l)]);

/// `e^log`, at most [EmpireBonuses.maxMultiplier].
double _compounded(double log) =>
    math.exp(math.min(log, math.log(EmpireBonuses.maxMultiplier)));

/// One bonus a megaproject's levels grant, as the app shows it: its
/// [kind], its [value] at the level (percent for the `…Percent` kinds,
/// seconds for [BonusKind.offlineCapSeconds], the compounded factor for
/// the `…Multiplier` kinds, at most [EmpireBonuses.maxMultiplier]), and
/// the highest tier it [appliesToMaxTier], null for every tier.
typedef BonusAtLevel = ({BonusKind kind, double value, int? appliesToMaxTier});

/// What [m]'s bonuses add up to at [level], in content order: each bonus
/// as it stands at that level ([BonusAtLevel]), for the app to word.
List<BonusAtLevel> megaprojectBonusesAt(MegaprojectDef m, int level) => [
  for (final b in m.bonusesPerLevel)
    (
      kind: b.kind,
      value: b.isMultiplier
          ? _compounded(level * math.log(b.amount))
          : b.amount * level,
      appliesToMaxTier: b.appliesToMaxTier,
    ),
];

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
/// `baseCost × costGrowth^level`, each entry rounded up to whole units
/// ([BigNum.ceil]); the key `credits` or a resource id, as in
/// [MegaprojectDef.baseCost].
///
/// [BigNum] keeps it finite at any level a save may hold.
///
/// The map is not to be changed: it is worked out once per megaproject and
/// level.
Map<String, BigNum> megaprojectCost(Content c, MegaprojectDef m, int level) {
  final known = _costs[m] ??= {};
  if (known[level] case final cost?) return cost;
  if (known.length >= _costsKept) known.clear();
  final growth = BigNum.from(m.costGrowth).powInt(level);
  return known[level] = Map.unmodifiable({
    for (final MapEntry(key: id, value: base) in m.baseCost.entries)
      id: (base * growth).ceil(),
  });
}

/// Each megaproject's [megaprojectCost] by level.
final _costs = Expando<Map<int, Map<String, BigNum>>>('costs');

/// Levels [_costs] keeps per megaproject before it starts over.
const int _costsKept = 64;

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
/// in full are left out, so it is empty once nothing is owed. Each entry
/// is whole: deliveries move whole units, and a fraction left by an older
/// save is rounded up, so delivering what it shows completes the entry.
/// While a
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
      if ((need - (got[id] ?? const BigNum.zero())).ceil() case final left
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

/// The first requirement of [m] ([MegaprojectDef.requiresMegaproject],
/// content order) that [factionId] has not reached: the megaproject and
/// the level it needs; null once [m] is open to it. A faction that does
/// not exist is at level 0 of every megaproject.
({String megaprojectId, int level})? megaprojectLockedBy(
  GameState s,
  Content c,
  String factionId,
  MegaprojectDef m,
) {
  if (m.requiresMegaproject.isEmpty) return null;
  final levels = _levelsOf(s, factionId) ?? const {};
  for (final MapEntry(key: id, value: need) in m.requiresMegaproject.entries) {
    if ((levels[id] ?? 0) < need) return (megaprojectId: id, level: need);
  }
  return null;
}

/// Whether [factionId] can deliver toward [m] now: it is open
/// ([megaprojectLockedBy]), the faction owns a body of its host type if it
/// has one, the stage deliveries pay for is below
/// [SaveCodec.maxMegaprojectLevel], and that stage is not already paid for
/// while one is under way ([megaprojectStageQueued]).
bool megaprojectTakesDeliveries(
  GameState s,
  Content c,
  String factionId,
  MegaprojectDef m,
) {
  if (megaprojectLockedBy(s, c, factionId, m) != null) return false;
  final host = m.hostBodyType;
  if (host != null &&
      !s.bodies.any((b) => b.ownerId == factionId && b.typeId == host)) {
    return false;
  }
  return megaprojectDeliveryLevel(s, factionId, m) <
          SaveCodec.maxMegaprojectLevel &&
      !megaprojectStageQueued(s, c, factionId, m);
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

/// Key of the credits entry in a megaproject cost
/// ([MegaprojectDef.baseCost]); every other key is a resource id.
const String creditsKey = 'credits';
