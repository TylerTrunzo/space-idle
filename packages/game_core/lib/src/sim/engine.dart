import 'dart:math' as math;

import '../commands/apply.dart';
import '../commands/command.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../report/flow_report.dart';
import '../state/game_state.dart';
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
  /// whose total did not change are left out.
  final Map<String, BigNum> stockGained;

  /// Change in the player's credits; negative if it fell.
  final BigNum creditsGained;

  /// Ids of milestones the player reached while away, in content order.
  final List<String> milestonesReached;

  /// The player's worst bottlenecks after catching up, at most three.
  final List<Bottleneck> topBottlenecks;
}

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
  void advance(GameState s, double seconds, {double maxStep = 60}) {
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
    }
    final rest = seconds - whole * maxStep;
    if (rest > maxStep * 1e-9) tick(s, rest);
  }

  /// Simulates the [secondsAway] the player was gone, up to [capSeconds]
  /// (default `rules.offlineCapSeconds`), and summarizes what changed for
  /// the player faction.
  ///
  /// A negative [secondsAway] (a clock set back) simulates nothing.
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

    advance(s, simulated);

    final stockAfter = _empireStock(s, player.id);
    final gained = <String, BigNum>{};
    for (final id in content.resources.keys) {
      final delta =
          (stockAfter[id] ?? const BigNum.zero()) -
          (stockBefore[id] ?? const BigNum.zero());
      if (!delta.isZero) gained[id] = delta;
    }
    return OfflineSummary(
      secondsSimulated: simulated,
      secondsAway: secondsAway,
      stockGained: gained,
      creditsGained: player.credits - creditsBefore,
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
