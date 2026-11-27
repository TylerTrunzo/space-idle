import 'dart:math' as math;

import '../commands/apply.dart';
import '../commands/command.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../num/format.dart';
import '../report/flow_report.dart';
import '../state/game_state.dart';
import 'contracts.dart';
import 'logistics.dart';
import 'market.dart';
import 'megaprojects.dart';
import 'milestones.dart';
import 'production.dart';
import 'projects.dart';

/// A project that completed while the player was away.
final class CompletedProject {
  /// Creates a record.
  const CompletedProject({
    required this.kind,
    required this.targetId,
    required this.name,
    this.level,
  });

  /// What the project did.
  final ProjectKind kind;

  /// Body or megaproject it acted on.
  final String targetId;

  /// Display name of [targetId].
  final String name;

  /// For a megaproject stage, the level it brought the megaproject to;
  /// null for other kinds.
  final int? level;
}

/// What happened to the player while the game was closed.
final class OfflineSummary {
  /// Creates a summary; the collections are copied unmodifiable.
  OfflineSummary({
    required this.awayFrom,
    required this.secondsSimulated,
    required this.secondsAway,
    required this.capSeconds,
    required Map<String, BigNum> stockGained,
    required this.creditsGained,
    required this.totalWasted,
    required List<String> milestonesReached,
    required List<Bottleneck> topBottlenecks,
    required List<CompletedProject> projectsCompleted,
    List<String> contractsPosted = const [],
  }) : contractsPosted = List.unmodifiable(contractsPosted),
       stockGained = Map.unmodifiable(stockGained),
       milestonesReached = List.unmodifiable(milestonesReached),
       topBottlenecks = List.unmodifiable(topBottlenecks),
       projectsCompleted = List.unmodifiable(projectsCompleted);

  /// Game time in seconds at which the absence began; a bottleneck in
  /// [topBottlenecks] first seen before it was there all along.
  final double awayFrom;

  /// Game seconds actually simulated: the time away, capped.
  final double secondsSimulated;

  /// Seconds the player was away, as passed in.
  final double secondsAway;

  /// The offline cap this catch-up ran under, in seconds: the most of an
  /// absence it simulates.
  final double capSeconds;

  /// Whether the absence was longer than [capSeconds], so only part of it
  /// counted.
  bool get capped => secondsAway > capSeconds;

  /// The return in one line for the player, such as "Away 4d 2h; 12h
  /// counted (cap); +1.2M credits", or "Away 3h; +36K credits" when the
  /// whole absence counted, then the highest level each megaproject
  /// reached while away, such as "; Orbital Station reached level 3".
  String get headline {
    final counted = capped
        ? '; ${formatDuration(secondsSimulated)} counted (cap)'
        : '';
    final sign = creditsGained.isNegative ? '' : '+';
    final levels = <String, (String, int)>{};
    for (final p in projectsCompleted) {
      if (p.level case final level?) levels[p.targetId] = (p.name, level);
    }
    return 'Away ${formatDuration(secondsAway)}$counted; '
        '$sign${formatNumber(creditsGained)} credits'
        '${[for (final (name, level) in levels.values) '; $name reached level $level'].join()}';
  }

  /// Resource id to the change in the player's stock summed over the bodies
  /// it owns, in content order; negative for resources used up. Resources
  /// whose total did not change, or changed only by float residue (within
  /// a relative 1e-12), are left out.
  final Map<String, BigNum> stockGained;

  /// Change in the player's credits; negative if it fell.
  final BigNum creditsGained;

  /// Units cut by storage caps on the player's bodies while away, every
  /// resource summed. Zero means nothing was wasted.
  ///
  /// Cargo lost because the player no longer owns either end of its route
  /// is recorded on a body the player does not own, so it is not counted.
  final BigNum totalWasted;

  /// Ids of milestones the player reached while away, in content order.
  final List<String> milestonesReached;

  /// The player's worst bottlenecks after catching up, at most three: those
  /// with an estimate of the credits they lose an hour first, most first
  /// ([Bottleneck.lostCreditsPerHour]), then the rest in report order.
  final List<Bottleneck> topBottlenecks;

  /// The player's projects that completed while away, in the order they
  /// completed (`finishAt`, then the order they were started), stages that
  /// started while away included (`stepProjects`).
  final List<CompletedProject> projectsCompleted;

  /// Ids of the contracts posted to the player's board while away, in the
  /// order they were posted; they are on the board.
  final List<String> contractsPosted;
}

/// Step of [GameEngine.catchUpOffline] and default step of
/// [GameEngine.advance], in game seconds.
const double _offlineStepSeconds = 60;

/// Runs the game: new games, commands and the passage of time.
final class GameEngine {
  /// Creates an engine for [content].
  GameEngine(this.content) : _hiddenBodyIds = hiddenBodies(content);

  /// The validated game content every call uses.
  final Content content;

  /// Ids of the bodies content hides until surveyed.
  final Set<String> _hiddenBodyIds;

  /// Seconds between checks of production-rate milestones.
  static const double _rateCheckSeconds = 60;

  /// Bottlenecks [catchUpOffline] reports at most.
  static const int topBottleneckCount = 3;

  /// Builds the starting world, seeding its random generator with [seed].
  GameState newGame(int seed) => newGameState(content, seed);

  /// Validates [cmd] against [s] and applies it; see [applyCommand].
  CommandResult apply(GameState s, Command cmd) =>
      applyCommand(s, content, cmd);

  /// [factionId]'s projects under way, soonest to finish first; see
  /// [runningProjects].
  List<ProjectState> projectsFor(GameState s, String factionId) =>
      runningProjects(s, factionId);

  /// Moves [s] forward by one step of [dt] game seconds.
  ///
  /// In order: reset each body's [BodyState.wastedThisStep], land the
  /// shipments due ([deliverShipments]), production, send cargo
  /// ([sendCargo]), market (recovery and auto-sell), complete the projects
  /// due ([stepProjects]), [clampStorage], [noteBottlenecks], post the
  /// contracts due by `time + dt` ([stepContracts]), waste tracking,
  /// milestone check, `time += dt`, then land the shipments due by the new
  /// time that fit below the cap ([landArrivals]). Stock may pass the
  /// storage cap
  /// during the tick; production uses landed cargo, and cargo and
  /// auto-sell take from what is made, before the clamp, so long steps
  /// lose no more to the cap than short ones. Routes take their share
  /// before auto-sell does: a rule selling a body's whole surplus never
  /// starves a route out of it. A shipment due by `time + dt` is usable
  /// once the tick ends, so ships are there at the arrival time a command
  /// reported; only cargo that would pass the cap waits for the start of
  /// the next tick, whose buildings use it before the clamp. A project due
  /// at exactly `time + dt` completes at the start of the next tick; a
  /// contract refill due then is posted in this one, from the state the
  /// tick leaves, which is the state at `time + dt`.
  ///
  /// Throws [ArgumentError], changing nothing, if [dt] is not finite and
  /// above zero.
  void tick(GameState s, double dt) {
    if (!dt.isFinite || dt <= 0) {
      throw ArgumentError.value(dt, 'dt', 'must be finite and > 0');
    }
    for (final b in s.bodies) {
      b.wastedThisStep.clear();
    }
    final kept = stockOverCap(s, content);
    deliverShipments(s);
    stepProduction(s, content, dt);
    sendCargo(s, content, dt);
    stepMarket(s, content, dt);
    stepProjects(s, content);
    clampStorage(s, content, kept);
    noteBottlenecks(s, content, s.time);
    stepContracts(s, content, s.time + dt);
    _noteWaste(s, s.time + dt);
    _checkMilestones(s, dt);
    s.time += dt;
    landArrivals(s, content);
  }

  /// Moves [s] forward by [seconds] in ticks of [maxStep] seconds, the last
  /// tick taking the remainder.
  ///
  /// Zero [seconds] does nothing. Throws [ArgumentError] if [seconds] is
  /// negative or not finite, or [maxStep] is not above zero and finite.
  void advance(
    GameState s,
    double seconds, {
    double maxStep = _offlineStepSeconds,
  }) => _advance(s, seconds, maxStep);

  /// [advance], calling [afterTick] after every tick.
  void _advance(
    GameState s,
    double seconds,
    double maxStep, [
    void Function()? afterTick,
  ]) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'must be finite and >= 0');
    }
    if (!maxStep.isFinite || maxStep <= 0) {
      throw ArgumentError.value(maxStep, 'maxStep', 'must be finite and > 0');
    }
    // Counting whole steps (rather than subtracting maxStep from a running
    // total) keeps float error from adding a sliver of a step at the end.
    final whole = (seconds / maxStep).floor();
    for (var i = 0; i < whole; i++) {
      tick(s, maxStep);
      afterTick?.call();
    }
    final rest = seconds - whole * maxStep;
    if (rest > maxStep * 1e-9) {
      tick(s, rest);
      afterTick?.call();
    }
  }

  /// Simulates the [secondsAway] the player was gone, up to [capSeconds]
  /// (default the player's [offlineCapFor] when it left: the rules' cap plus
  /// its megaproject bonuses, at most 48 h), and summarizes what changed
  /// for the player faction.
  ///
  /// Ticks exactly as [advance] does by default, in 60 s steps; within a
  /// tick every chain on a body runs through and landed cargo is used (see
  /// [tick]), so this earns what live play in short steps would. A
  /// negative [secondsAway] (a clock set back) simulates nothing.
  OfflineSummary catchUpOffline(
    GameState s,
    double secondsAway, {
    double? capSeconds,
  }) {
    final player = s.factions.firstWhere((f) => f.isPlayer);
    final cap = capSeconds ?? offlineCapFor(s, content, player.id);
    final simulated = math.max(0.0, math.min(secondsAway, cap));
    final stockBefore = factionStock(s, player.id);
    final creditsBefore = player.credits;
    final reachedBefore = Set.of(player.reachedMilestones);
    final contractsBefore = {for (final k in player.contracts) k.id};
    final awayFrom = s.time;
    // Stages can start while away, as a stage paid for in full follows the
    // one under way, so completions are noted tick by tick.
    var running = runningProjects(s, player.id);
    final completed = <ProjectState>[];
    final levels = Map.of(player.megaprojectLevels);
    final stageLevels = <ProjectState, int>{};

    var wasted = const BigNum.zero();
    _advance(s, simulated, _offlineStepSeconds, () {
      for (final b in s.bodies) {
        if (b.ownerId != player.id) continue;
        for (final v in b.wastedThisStep.values) {
          wasted = wasted + v;
        }
      }
      final now = runningProjects(s, player.id);
      for (final p in running) {
        if (now.contains(p)) continue;
        completed.add(p);
        if (p.kind == ProjectKind.megaprojectStage) {
          stageLevels[p] = levels[p.targetId] = (levels[p.targetId] ?? 0) + 1;
        }
      }
      running = now;
    });

    final stockAfter = factionStock(s, player.id);
    final gained = <String, BigNum>{};
    for (final id in content.resources.keys) {
      final delta = changeBetween(
        stockAfter[id] ?? const BigNum.zero(),
        stockBefore[id] ?? const BigNum.zero(),
      );
      if (!delta.isZero) gained[id] = delta;
    }
    final necks =
        buildFlowReport(s, content, player.id).bottlenecks.indexed.toList()
          ..sort((x, y) {
            final (a, b) = (x.$2.lostCreditsPerHour, y.$2.lostCreditsPerHour);
            if (a != null && b != null) {
              final byLoss = b.compareTo(a);
              if (byLoss != 0) return byLoss;
            } else if (a != null || b != null) {
              return a != null ? -1 : 1;
            }
            return x.$1.compareTo(y.$1);
          });
    return OfflineSummary(
      awayFrom: awayFrom,
      secondsSimulated: simulated,
      secondsAway: secondsAway,
      capSeconds: cap,
      stockGained: gained,
      creditsGained: player.credits - creditsBefore,
      totalWasted: wasted,
      milestonesReached: [
        for (final m in content.milestones)
          if (player.reachedMilestones.contains(m.id) &&
              !reachedBefore.contains(m.id))
            m.id,
      ],
      topBottlenecks: [for (final (_, b) in necks.take(topBottleneckCount)) b],
      projectsCompleted: [
        for (final p in completed)
          CompletedProject(
            kind: p.kind,
            targetId: p.targetId,
            name: projectTargetName(s, content, p),
            level: stageLevels[p],
          ),
      ],
      contractsPosted: [
        for (final k in player.contracts)
          if (!contractsBefore.contains(k.id)) k.id,
      ],
    );
  }

  /// Moves each faction's [FactionState.wasteFreeSince] to [end], the time
  /// this tick ends, if it wasted anything this tick or owns no building.
  void _noteWaste(GameState s, double end) {
    for (final f in s.factions) {
      var built = false;
      var wasted = false;
      for (final b in s.bodies) {
        if (b.ownerId != f.id) continue;
        built = built || b.buildings.isNotEmpty;
        wasted =
            wasted ||
            b.wastedThisStep.values.any((v) => v > const BigNum.zero());
      }
      if (wasted || !built) f.wasteFreeSince = end;
    }
  }

  /// Adds every milestone each faction now meets ([milestoneProgressAt]
  /// as of the tick's end) to its reached set, factions and milestones in
  /// content order. [dt] is this tick's length.
  ///
  /// Production-rate milestones read the steady rates ([netProductionRate])
  /// and are tested only in ticks that cross a whole game minute.
  void _checkMilestones(GameState s, double dt) {
    final end = s.time + dt;
    final rateDue =
        (s.time / _rateCheckSeconds).floor() !=
        (end / _rateCheckSeconds).floor();
    for (final f in s.factions) {
      // Built on first use: most ticks have every milestone already reached
      // or no stock condition to test.
      Map<String, BigNum>? stock;
      for (final m in content.milestones) {
        if (f.reachedMilestones.contains(m.id)) continue;
        if (m.condition is ProductionRateCondition && !rateDue) continue;
        final progress = milestoneProgressAt(
          s,
          content,
          f,
          m,
          now: end,
          empireStock: () => stock ??= factionStock(s, f.id),
          hiddenBodyIds: _hiddenBodyIds,
        );
        if (progress.met) f.reachedMilestones.add(m.id);
      }
    }
  }
}
