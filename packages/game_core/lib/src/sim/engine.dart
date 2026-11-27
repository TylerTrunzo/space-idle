import 'dart:math' as math;

import '../commands/apply.dart';
import '../commands/command.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../report/flow_report.dart';
import '../state/game_state.dart';
import 'contracts.dart';
import 'crew.dart';
import 'logistics.dart';
import 'market.dart';
import 'megaproject_auto.dart';
import 'megaprojects.dart';
import 'milestones.dart';
import 'offline_summary.dart';
import 'production.dart';
import 'projects.dart';
import 'step_cache.dart';

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

  /// Builds the starting world, seeding its random generator with [seed],
  /// and posts the contracts already due ([stepContracts]), as a tick
  /// would, so a board does not wait for the first tick to fill what it
  /// can.
  GameState newGame(int seed) {
    final s = newGameState(content, seed);
    stepContracts(s, content, s.time);
    return s;
  }

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
  /// ([sendCargo]), goods auto-delivered to megaprojects once a game
  /// minute ([stepMegaprojectAuto]), market (recovery and auto-sell),
  /// credits auto-paid to megaprojects once a game minute
  /// ([stepMegaprojectCredits]), complete the projects due
  /// ([stepProjects]), [clampStorage], [noteBottlenecks], post the
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
  void tick(GameState s, double dt) => _tick(s, dt);

  /// [tick], returning what auto-delivery handed over in it.
  AutoDeliveries _tick(GameState s, double dt) {
    // `measuredSaleRevenue` (report/steady_revenue.dart) mirrors the
    // economy steps below for the report's credits per second: a step
    // added or moved here belongs there too.
    if (!dt.isFinite || dt <= 0) {
      throw ArgumentError.value(dt, 'dt', 'must be finite and > 0');
    }
    for (final b in s.bodies) {
      b.wastedThisStep.clear();
    }
    final kept = stockOverCap(s, content);
    deliverShipments(s);
    stepProduction(s, content, dt);
    // Crew, buildings and storage caps hold from here to the end of the
    // tick: the steps that move goods share what they read of them.
    final cache = StepCache(s, content);
    sendCargo(s, content, dt, cache: cache);
    final goods = stepMegaprojectAuto(s, content, dt, cache: cache);
    stepMarket(s, content, dt, cache: cache);
    final fed = mergeDeliveries(goods, stepMegaprojectCredits(s, content, dt));
    stepProjects(s, content);
    clampStorage(s, content, kept);
    noteBottlenecks(s, content, s.time);
    stepContracts(s, content, s.time + dt);
    _noteWaste(s, s.time + dt);
    _checkMilestones(s, dt);
    s.time += dt;
    landArrivals(s, content);
    return fed;
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

  /// [advance], calling [afterTick] after every tick with what
  /// auto-delivery handed over in it.
  void _advance(
    GameState s,
    double seconds,
    double maxStep, [
    void Function(AutoDeliveries fed)? afterTick,
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
      final fed = _tick(s, maxStep);
      afterTick?.call(fed);
    }
    final rest = seconds - whole * maxStep;
    if (rest > maxStep * 1e-9) {
      final fed = _tick(s, rest);
      afterTick?.call(fed);
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
    final housingBefore = crewTotals(s, content, player.id);
    // The report plays copies of the state, so its credits a second can be
    // read once the catch-up is done.
    final reportBefore = buildFlowReport(s, content, player.id);
    // Stages can start while away, as a stage paid for in full follows the
    // one under way, so completions are noted tick by tick.
    var running = runningProjects(s, player.id);
    final completed = <ProjectState>[];
    final levels = Map.of(player.megaprojectLevels);
    final stageLevels = <ProjectState, int>{};

    final wasted = <String, BigNum>{};
    final autoDelivered = <String, Map<String, BigNum>>{};
    _advance(s, simulated, _offlineStepSeconds, (fed) {
      addDeliveries(autoDelivered, fed[player.id] ?? const {});
      for (final b in s.bodies) {
        if (b.ownerId != player.id) continue;
        for (final MapEntry(key: id, value: v) in b.wastedThisStep.entries) {
          wasted[id] = (wasted[id] ?? const BigNum.zero()) + v;
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
    var totalWasted = const BigNum.zero();
    var wastedValue = const BigNum.zero();
    for (final id in content.resources.keys) {
      final v = wasted[id];
      if (v == null) continue;
      totalWasted = totalWasted + v;
      wastedValue = wastedValue + v * price(s, content, id);
    }
    final report = buildFlowReport(s, content, player.id);
    final top = [
      for (final (_, b) in _ranked(report.bottlenecks).take(topBottleneckCount))
        b,
    ];
    final before = {for (final b in reportBefore.bottlenecks) b.key: b};
    return OfflineSummary(
      awayFrom: awayFrom,
      secondsSimulated: simulated,
      secondsAway: secondsAway,
      capSeconds: cap,
      stockGained: gained,
      creditsGained: player.credits - creditsBefore,
      totalWasted: totalWasted,
      wastedValue: wastedValue,
      milestonesReached: [
        for (final m in content.milestones)
          if (player.reachedMilestones.contains(m.id) &&
              !reachedBefore.contains(m.id))
            m.id,
      ],
      topBottlenecks: top,
      ongoing: [
        for (final b in top)
          if (b.firstSeenAt < awayFrom)
            _ongoing(b, before[b.key]?.lostCreditsPerHour),
      ],
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
      housingBefore: housingBefore,
      housingAfter: crewTotals(s, content, player.id),
      creditsPerSecBefore: reportBefore.creditsPerSec,
      creditsPerSecAfter: report.creditsPerSec,
      nextGoal: nextGoal(s, content, player.id, report),
      autoDelivered: {
        for (final m in content.megaprojects.keys) m: ?autoDelivered[m],
      },
    );
  }

  /// [necks] with their report index, ranked for [OfflineSummary]: a crew
  /// shortage that costs credits first, then those with an estimate of the
  /// credits they lose an hour, most first, then the rest, each in report
  /// order on a tie.
  static List<(int, Bottleneck)> _ranked(List<Bottleneck> necks) {
    // The report shows a crew shortage only when housing truly falls short
    // (`overAssigned > 0`), and its loss is snapped to zero within float
    // residue, so this holds only for a real, costly shortage.
    bool crewFirst(Bottleneck b) =>
        b.kind == BottleneckKind.crewShortage &&
        (b.lostCreditsPerHour ?? const BigNum.zero()) > const BigNum.zero();
    return necks.indexed.toList()..sort((x, y) {
      final (a, b) = (x.$2, y.$2);
      if (crewFirst(a) != crewFirst(b)) return crewFirst(a) ? -1 : 1;
      final (la, lb) = (a.lostCreditsPerHour, b.lostCreditsPerHour);
      if (la != null && lb != null) {
        final byLoss = lb.compareTo(la);
        if (byLoss != 0) return byLoss;
      } else if (la != null || lb != null) {
        return la != null ? -1 : 1;
      }
      return x.$1.compareTo(y.$1);
    });
  }

  /// [b], there since before the absence, against [lostBefore], what it
  /// cost an hour as the absence began.
  static OngoingBottleneck _ongoing(Bottleneck b, BigNum? lostBefore) {
    final lost = b.lostCreditsPerHour;
    return OngoingBottleneck(
      key: b.key,
      since: b.firstSeenAt,
      lostBefore: lostBefore,
      worseThanBefore:
          lost != null &&
          lostBefore != null &&
          lost > lostBefore.mulDouble(OngoingBottleneck.worseGrowth),
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
