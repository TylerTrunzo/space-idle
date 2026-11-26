import '../content/content.dart';
import '../num/big_num.dart';
import '../num/format.dart';
import '../state/game_state.dart';
import 'crew.dart';
import 'production.dart';

/// How far a faction is toward a milestone: [current] of [target] in the
/// milestone's own unit (units, credits, bodies, buildings, contracts,
/// units a second, crew, levels or seconds), and whether it is [met].
typedef MilestoneProgress = ({BigNum current, BigNum target, bool met});

/// How far [factionId] is toward [m] in [s], measured now; throws
/// [StateError] if there is no such faction.
///
/// [MilestoneProgress.met] is the engine's test for reaching it, the one
/// definition the engine's milestone check uses, so the two always agree:
/// - stock: units held over the faction's owned bodies;
/// - produced: units its buildings have made since the game began;
/// - credits: credits held; credits earned: credits earned in all;
/// - bodies owned, buildings of a type, building types, contracts
///   completed, supported crew, a megaproject's level and hidden bodies
///   surveyed: counts;
/// - production rate: the empire's steady net rate a second
///   ([netProductionRate]); the engine tests it only once a game minute;
/// - zero waste: seconds since the faction last wasted anything
///   (`FactionState.wasteFreeSince`).
///
/// A milestone already reached stays reached even if its progress later
/// falls (credits spent, say): [GameState] keeps the reached set.
MilestoneProgress milestoneProgress(
  GameState s,
  Content c,
  String factionId,
  MilestoneDef m,
) => milestoneProgressAt(s, c, s.faction(factionId), m, now: s.time);

/// [milestoneProgress] for faction [f] as of game time [now], which the
/// engine sets to the end of the tick it checks.
///
/// [empireStock] and [hiddenBodyIds], when given, stand in for the
/// faction's stock summed over its owned bodies and the ids of the bodies
/// content hides, so a caller checking many milestones builds them once.
MilestoneProgress milestoneProgressAt(
  GameState s,
  Content c,
  FactionState f,
  MilestoneDef m, {
  required double now,
  Map<String, BigNum> Function()? empireStock,
  Set<String>? hiddenBodyIds,
}) {
  MilestoneProgress big(BigNum current, BigNum target) =>
      (current: current, target: target, met: current >= target);
  MilestoneProgress count(int current, int target) => (
    current: BigNum.from(current),
    target: BigNum.from(target),
    met: current >= target,
  );
  Iterable<BodyState> owned() => s.bodies.where((b) => b.ownerId == f.id);
  return switch (m.condition) {
    StockCondition(:final resourceId, :final amount) => big(
      (empireStock?.call() ?? factionStock(s, f.id))[resourceId] ??
          const BigNum.zero(),
      amount,
    ),
    ProducedCondition(:final resourceId, :final amount) => big(
      f.lifetimeProduced[resourceId] ?? const BigNum.zero(),
      amount,
    ),
    CreditsCondition(:final amount) => big(f.credits, amount),
    CreditsEarnedCondition(:final amount) => big(f.lifetimeCredits, amount),
    BodiesOwnedCondition(count: final n) => count(owned().length, n),
    BuildingCountCondition(:final defId, count: final n) => count(
      owned().expand((b) => b.buildings).where((b) => b.defId == defId).length,
      n,
    ),
    ContractsCompletedCondition(count: final n) => count(
      f.contractsCompleted,
      n,
    ),
    ProductionRateCondition(:final resourceId, :final perSec) => big(
      netProductionRate(s, c, f.id, resourceId),
      perSec,
    ),
    BuildingTypesBuiltCondition(count: final n) => count(
      {
        for (final b in owned())
          for (final x in b.buildings) x.defId,
      }.length,
      n,
    ),
    CrewTotalCondition(count: final n) => count(
      crewTotals(s, c, f.id).supported,
      n,
    ),
    MegaprojectLevelCondition(:final megaprojectId, :final level) => count(
      f.megaprojectLevels[megaprojectId] ?? 0,
      level,
    ),
    ZeroWasteForCondition(:final seconds) => (
      current: BigNum.from(now - f.wasteFreeSince),
      target: BigNum.from(seconds),
      met: now - f.wasteFreeSince >= seconds,
    ),
    BodiesSurveyedCondition(count: final n) => count(
      s.bodies
          .where(
            (b) =>
                b.surveyed && (hiddenBodyIds ?? hiddenBodies(c)).contains(b.id),
          )
          .length,
      n,
    ),
  };
}

/// Ids of the bodies [c]'s galaxy hides until surveyed.
Set<String> hiddenBodies(Content c) => {
  for (final sys in c.galaxy.systems)
    for (final b in sys.bodies)
      if (b.hidden) b.id,
};

/// Resource id to units held over every body [factionId] owns.
Map<String, BigNum> factionStock(GameState s, String factionId) {
  final total = <String, BigNum>{};
  for (final b in s.bodies) {
    if (b.ownerId != factionId) continue;
    for (final MapEntry(key: id, value: v) in b.stock.entries) {
      total[id] = (total[id] ?? const BigNum.zero()) + v;
    }
  }
  return total;
}

/// What [m] asks for, as a short English goal for the player, such as
/// "Make 30 Steel", "Own 3 bodies" or "Reach 1M credits".
String milestoneGoalText(Content c, MilestoneDef m) {
  String res(String id) => c.resources[id]?.name ?? id;
  String n(BigNum v) => formatNumber(v);
  String several(int count, String one, String many) =>
      count == 1 ? one : '$count $many';
  return switch (m.condition) {
    StockCondition(:final resourceId, :final amount) =>
      'Hold ${n(amount)} ${res(resourceId)}',
    ProducedCondition(:final resourceId, :final amount) =>
      'Make ${n(amount)} ${res(resourceId)}',
    CreditsCondition(:final amount) => 'Reach ${n(amount)} credits',
    CreditsEarnedCondition(:final amount) => 'Earn ${n(amount)} credits',
    BodiesOwnedCondition(:final count) =>
      'Own ${several(count, 'a body', 'bodies')}',
    BuildingCountCondition(:final defId, :final count) =>
      switch (c.buildings[defId]?.name) {
        final name? when count == 1 => 'Build ${_article(name)} $name',
        final name => 'Own $count ${name ?? defId} buildings',
      },
    ContractsCompletedCondition(:final count) =>
      'Complete ${several(count, 'a contract', 'contracts')}',
    ProductionRateCondition(:final resourceId, :final perSec) =>
      'Make ${n(perSec)} ${res(resourceId)} a second',
    BuildingTypesBuiltCondition(:final count) =>
      'Build ${several(count, 'a building', 'kinds of building')}',
    CrewTotalCondition(:final count) => 'House $count crew',
    MegaprojectLevelCondition(:final megaprojectId, :final level) =>
      'Reach ${c.megaprojects[megaprojectId]?.name ?? megaprojectId} '
          'level $level',
    ZeroWasteForCondition(:final seconds) =>
      'Waste nothing for ${formatDuration(seconds)}',
    BodiesSurveyedCondition(:final count) =>
      'Survey ${several(count, 'a hidden body', 'hidden bodies')}',
  };
}

/// "a" or "an", for [word] mid-sentence.
String _article(String word) => 'AEIOUaeiou'.contains(word[0]) ? 'an' : 'a';
