import 'dart:math' as math;

import '../commands/apply.dart';
import '../commands/command.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../report/flow_report.dart';
import '../state/game_state.dart';
import 'crew.dart';
import 'logistics.dart';
import 'market.dart';
import 'production.dart';

/// What happened to the player while the game was closed.
final class OfflineSummary {
  /// Creates a summary; the collections are copied unmodifiable.
  OfflineSummary({
    required this.secondsSimulated,
    required this.secondsAway,
    required Map<String, BigNum> stockGained,
    required this.creditsGained,
    required this.totalWasted,
    required List<String> milestonesReached,
    required List<Bottleneck> topBottlenecks,
  }) : stockGained = Map.unmodifiable(stockGained),
       milestonesReached = List.unmodifiable(milestonesReached),
       topBottlenecks = List.unmodifiable(topBottlenecks);

  /// Game seconds actually simulated: the time away, capped.
  final double secondsSimulated;

  /// Seconds the player was away, as passed in.
  final double secondsAway;

  /// Resource id to the change in the player's stock summed over the bodies
  /// it owns, in content order; negative for resources used up. Resources
  /// whose total did not change, or changed only by float residue (within
  /// a relative 1e-12), are left out.
  final Map<String, BigNum> stockGained;

  /// Change in the player's credits; negative if it fell.
  final BigNum creditsGained;

  /// Units lost on the player's bodies while away, every resource summed:
  /// cut by storage caps, or cargo lost with both its ends. Zero means
  /// nothing was wasted.
  final BigNum totalWasted;

  /// Ids of milestones the player reached while away, in content order.
  final List<String> milestonesReached;

  /// The player's worst bottlenecks after catching up, at most three.
  final List<Bottleneck> topBottlenecks;
}

/// Default and longest step of [GameEngine.advance] and
/// [GameEngine.catchUpOffline], in game seconds.
const double _offlineStepSeconds = 60;

/// Shortest step [GameEngine.offlineStepSeconds] picks, in game seconds.
const double _minOfflineStepSeconds = 1;

/// Runs the game: new games, commands and the passage of time.
final class GameEngine {
  /// Creates an engine for [content].
  GameEngine(this.content);

  /// The validated game content every call uses.
  final Content content;

  /// Bottlenecks [catchUpOffline] reports at most.
  static const int topBottleneckCount = 3;

  /// Builds the starting world, seeding its random generator with [seed].
  GameState newGame(int seed) => newGameState(content, seed);

  /// Validates [cmd] against [s] and applies it; see [applyCommand].
  CommandResult apply(GameState s, Command cmd) =>
      applyCommand(s, content, cmd);

  /// Moves [s] forward by one step of [dt] game seconds.
  ///
  /// In order: reset each body's [BodyState.wastedThisStep], production,
  /// logistics, market (recovery and auto-sell), [clampStorage], milestone
  /// check, then `time += dt`. Stock may pass the storage cap during the
  /// tick; cargo and auto-sell take from it before the clamp, so long steps
  /// lose no more to the cap than short ones. Because time moves last, a
  /// shipment due at exactly `time + dt` lands on the next tick.
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
    stepProduction(s, content, dt);
    stepLogistics(s, content, dt);
    stepMarket(s, content, dt);
    clampStorage(s, content, kept);
    _checkMilestones(s);
    s.time += dt;
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

  /// Longest tick, in whole game seconds from 1 to 60, in which no owned
  /// body's buildings would use more of a resource than the body holds
  /// between ticks.
  ///
  /// Inputs made in a tick are used in the next, so a chain on one body
  /// moves at most what the body holds between ticks: its storage cap, or
  /// the `keepAtLeast` of the owner's auto-sell rule for that resource if
  /// lower. At 60 s ticks a fast chain would run far below its live rate.
  /// Demand is each building's [fullRateFlow] at full supply; a resource
  /// auto-sold down to zero starves at any step and is ignored.
  /// [catchUpOffline] ticks at this step.
  double offlineStepSeconds(GameState s) {
    final crewEff = <String, double>{};
    final keep = <(String, String), BigNum>{
      for (final f in s.factions)
        for (final r in f.autoSell)
          if (s.body(r.bodyId).ownerId == f.id)
            (r.bodyId, r.resourceId): r.keepAtLeast,
    };
    var step = _offlineStepSeconds;
    for (final body in s.bodies) {
      final owner = body.ownerId;
      if (owner == null) continue;
      final eff = crewEff[owner] ??= crewEfficiency(s, content, owner);
      final demand = <String, BigNum>{};
      for (final b in body.buildings) {
        final inputs = fullRateFlow(content, body, b, 1, eff).inputs;
        for (final MapEntry(key: id, value: v) in inputs.entries) {
          demand[id] = (demand[id] ?? const BigNum.zero()) + v;
        }
      }
      final cap = storageCap(s, content, body);
      for (final MapEntry(key: id, value: need) in demand.entries) {
        final held = keep[(body.id, id)]?.min(cap) ?? cap;
        if (need.isZero || held.isZero) continue;
        step = math.min(step, (held / need).toDouble().floorToDouble());
      }
    }
    return math.max(_minOfflineStepSeconds, step);
  }

  /// Simulates the [secondsAway] the player was gone, up to [capSeconds]
  /// (default `rules.offlineCapSeconds`), and summarizes what changed for
  /// the player faction.
  ///
  /// Ticks at [offlineStepSeconds], so a fast empire earns about what live
  /// play would. A negative [secondsAway] (a clock set back) simulates
  /// nothing.
  OfflineSummary catchUpOffline(
    GameState s,
    double secondsAway, {
    double? capSeconds,
  }) {
    final cap = capSeconds ?? content.rules.offlineCapSeconds;
    final simulated = math.max(0.0, math.min(secondsAway, cap));
    final player = s.factions.firstWhere((f) => f.isPlayer);
    final stockBefore = _empireStock(s, player.id);
    final creditsBefore = player.credits;
    final reachedBefore = Set.of(player.reachedMilestones);

    var wasted = const BigNum.zero();
    _advance(s, simulated, offlineStepSeconds(s), () {
      for (final b in s.bodies) {
        if (b.ownerId != player.id) continue;
        for (final v in b.wastedThisStep.values) {
          wasted = wasted + v;
        }
      }
    });

    final stockAfter = _empireStock(s, player.id);
    final gained = <String, BigNum>{};
    for (final id in content.resources.keys) {
      final delta = changeBetween(
        stockAfter[id] ?? const BigNum.zero(),
        stockBefore[id] ?? const BigNum.zero(),
      );
      if (!delta.isZero) gained[id] = delta;
    }
    return OfflineSummary(
      secondsSimulated: simulated,
      secondsAway: secondsAway,
      stockGained: gained,
      creditsGained: player.credits - creditsBefore,
      totalWasted: wasted,
      milestonesReached: [
        for (final m in content.milestones)
          if (player.reachedMilestones.contains(m.id) &&
              !reachedBefore.contains(m.id))
            m.id,
      ],
      topBottlenecks: buildFlowReport(
        s,
        content,
        player.id,
      ).bottlenecks.take(topBottleneckCount).toList(),
    );
  }

  /// Adds every milestone each faction now meets to its reached set,
  /// factions and milestones in content order.
  void _checkMilestones(GameState s) {
    for (final f in s.factions) {
      // Built on first use: most ticks have every milestone already reached
      // or no stock condition to test.
      Map<String, BigNum>? stock;
      for (final m in content.milestones) {
        if (f.reachedMilestones.contains(m.id)) continue;
        final met = switch (m.condition) {
          StockCondition(:final resourceId, :final amount) =>
            ((stock ??= _empireStock(s, f.id))[resourceId] ??
                    const BigNum.zero()) >=
                amount,
          CreditsCondition(:final amount) => f.credits >= amount,
          BodiesOwnedCondition(:final count) =>
            s.bodies.where((b) => b.ownerId == f.id).length >= count,
          BuildingCountCondition(:final defId, :final count) =>
            s.bodies
                    .where((b) => b.ownerId == f.id)
                    .expand((b) => b.buildings)
                    .where((b) => b.defId == defId)
                    .length >=
                count,
        };
        if (met) f.reachedMilestones.add(m.id);
      }
    }
  }
}

/// Resource id to units held over every body [factionId] owns.
Map<String, BigNum> _empireStock(GameState s, String factionId) {
  final total = <String, BigNum>{};
  for (final b in s.bodies) {
    if (b.ownerId != factionId) continue;
    for (final MapEntry(key: id, value: v) in b.stock.entries) {
      total[id] = (total[id] ?? const BigNum.zero()) + v;
    }
  }
  return total;
}
