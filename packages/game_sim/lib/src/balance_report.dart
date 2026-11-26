import 'dart:math' as math;

import 'package:game_core/game_core.dart';

import 'bots/bot.dart';

/// Game seconds between bot decisions while the player is checked in.
const double decisionEverySeconds = 10;

/// When a milestone was first seen.
final class MilestoneHit {
  /// Creates a milestone hit.
  const MilestoneHit({
    required this.id,
    required this.name,
    required this.gameHours,
    required this.checkInIndex,
  });

  /// Milestone id.
  final String id;

  /// Milestone display name.
  final String name;

  /// Hours since the session started when the player first saw it: during
  /// a check-in, or on returning to the check-in after the time away in
  /// which it was reached.
  final double gameHours;

  /// Index of that check-in, from 0; one past the last check-in for a
  /// milestone reached in the time away after it.
  final int checkInIndex;

  /// Serializes this hit.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'gameHours': gameHours,
    'checkInIndex': checkInIndex,
  };
}

/// A check-in in which the bot found nothing to do.
final class DeadZone {
  /// Creates a dead zone.
  const DeadZone({required this.checkInIndex, required this.gameHours});

  /// Index of the check-in, from 0.
  final int checkInIndex;

  /// Hours since the session started when the check-in began.
  final double gameHours;

  /// Serializes this dead zone.
  Map<String, Object?> toJson() => {
    'checkInIndex': checkInIndex,
    'gameHours': gameHours,
  };
}

/// What a bot session reached and where it got stuck.
final class BalanceReport {
  /// Creates a report; the collections are copied unmodifiable.
  BalanceReport({
    required this.botName,
    required this.seed,
    required this.hours,
    required this.checkIns,
    required List<MilestoneHit> milestones,
    required List<MilestoneDef> milestonesNotReached,
    required List<DeadZone> deadZones,
    required List<String> unusedResources,
    required Map<String, String> finalStock,
    required this.finalCredits,
    required List<String> bottleneckLog,
    required this.rejectedCommands,
  }) : milestones = List.unmodifiable(milestones),
       milestonesNotReached = List.unmodifiable(milestonesNotReached),
       deadZones = List.unmodifiable(deadZones),
       unusedResources = List.unmodifiable(unusedResources),
       finalStock = Map.unmodifiable(finalStock),
       bottleneckLog = List.unmodifiable(bottleneckLog);

  /// [Bot.name] of the bot that played.
  final String botName;

  /// Seed of the new game played.
  final int seed;

  /// Session length in hours.
  final double hours;

  /// Check-ins the bot made.
  final int checkIns;

  /// Milestones reached, in the order seen; content order within one
  /// check-in.
  final List<MilestoneHit> milestones;

  /// Milestones not reached, in content order.
  final List<MilestoneDef> milestonesNotReached;

  /// Check-ins in which the bot issued no command, in order.
  final List<DeadZone> deadZones;

  /// Ids, in content order, of resources never produced, or produced but
  /// never used (by a building, a build, a route or a claim) or sold.
  final List<String> unusedResources;

  /// Resource id to the faction's formatted stock over all its bodies at
  /// the end, in content order; zero stocks left out.
  final Map<String, String> finalStock;

  /// The faction's credits at the end, formatted.
  final String finalCredits;

  /// The worst bottleneck at the start of each check-in that had one, as
  /// `"#<check-in> <hours>h: <message>"`.
  final List<String> bottleneckLog;

  /// Bot commands the engine rejected; above zero means a bot bug.
  final int rejectedCommands;

  /// Serializes this report.
  Map<String, Object?> toJson() => {
    'bot': botName,
    'seed': seed,
    'hours': hours,
    'checkIns': checkIns,
    'milestones': [for (final m in milestones) m.toJson()],
    'milestonesNotReached': [for (final m in milestonesNotReached) m.id],
    'deadZones': [for (final d in deadZones) d.toJson()],
    'unusedResources': unusedResources,
    'finalStock': finalStock,
    'finalCredits': finalCredits,
    'bottleneckLog': bottleneckLog,
    'rejectedCommands': rejectedCommands,
  };

  /// Renders this report as Markdown with a milestone table.
  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Balance report: $botName bot')
      ..writeln()
      ..writeln(
        'Seed $seed, ${_hours(hours)} h, $checkIns check-ins. '
        'Final credits: $finalCredits. Rejected commands: $rejectedCommands.',
      )
      ..writeln()
      ..writeln('## Milestones')
      ..writeln()
      ..writeln('| Milestone | Id | Hours | Check-in |')
      ..writeln('|---|---|---:|---:|');
    for (final m in milestones) {
      b.writeln(
        '| ${m.name} | ${m.id} | ${_hours(m.gameHours)} | ${m.checkInIndex} |',
      );
    }
    for (final m in milestonesNotReached) {
      b.writeln('| ${m.name} | ${m.id} | not reached | |');
    }
    b
      ..writeln()
      ..writeln('## Dead zones')
      ..writeln();
    if (deadZones.isEmpty) b.writeln('None.');
    for (final d in deadZones) {
      b.writeln(
        '- Check-in ${d.checkInIndex} at ${_hours(d.gameHours)} h: '
        'nothing to do',
      );
    }
    b
      ..writeln()
      ..writeln('## Unused resources')
      ..writeln();
    b.writeln(unusedResources.isEmpty ? 'None.' : unusedResources.join(', '));
    b
      ..writeln()
      ..writeln('## Final stock')
      ..writeln()
      ..writeln('| Resource | Stock |')
      ..writeln('|---|---:|');
    for (final MapEntry(key: id, value: v) in finalStock.entries) {
      b.writeln('| $id | $v |');
    }
    b
      ..writeln()
      ..writeln('## Bottleneck log')
      ..writeln();
    if (bottleneckLog.isEmpty) b.writeln('None.');
    for (final line in bottleneckLog) {
      b.writeln('- $line');
    }
    return b.toString();
  }
}

String _hours(double h) => h.toStringAsFixed(1);

/// Plays a new game seeded with [seed] for [hours] with [bot] as the
/// player, checking in every [checkInEverySeconds] (4 times a day by
/// default, spec §6.7), and reports what it reached.
///
/// Each check-in, the bot decides every [decisionEverySeconds] of game time
/// for [activeSecondsPerCheckIn], each command going through
/// [GameEngine.apply]; then [GameEngine.catchUpOffline] covers the time to
/// the next check-in, up to the engine's offline cap. Hours in the report
/// are session time, which runs ahead of game time if the cap cuts a gap.
/// Deterministic for a deterministic bot.
BalanceReport runBotSession(
  GameEngine e,
  Bot bot, {
  required int seed,
  required double hours,
  double checkInEverySeconds = 21600,
  double activeSecondsPerCheckIn = 180,
}) {
  if (!hours.isFinite || hours <= 0) {
    throw ArgumentError.value(hours, 'hours', 'must be finite and > 0');
  }
  if (!checkInEverySeconds.isFinite ||
      checkInEverySeconds <= activeSecondsPerCheckIn ||
      activeSecondsPerCheckIn < 0) {
    throw ArgumentError(
      'need 0 <= activeSecondsPerCheckIn < checkInEverySeconds',
    );
  }
  final c = e.content;
  final s = e.newGame(seed);
  final faction = s.factions.firstWhere((f) => f.isPlayer);
  final end = hours * 3600;
  final tracker = _Tracker(c, s, faction.id);
  final hits = <MilestoneHit>[];
  final deadZones = <DeadZone>[];
  final bottleneckLog = <String>[];
  var rejected = 0;
  var clock = 0.0;
  var checkIn = 0;

  void noteMilestones(int index) {
    for (final m in c.milestones) {
      if (faction.reachedMilestones.contains(m.id) &&
          !hits.any((h) => h.id == m.id)) {
        hits.add(
          MilestoneHit(
            id: m.id,
            name: m.name,
            gameHours: clock / 3600,
            checkInIndex: index,
          ),
        );
      }
    }
  }

  while (clock < end) {
    final necks = buildFlowReport(s, c, faction.id).bottlenecks;
    if (necks.isNotEmpty) {
      bottleneckLog.add(
        '#$checkIn ${_hours(clock / 3600)}h: ${necks.first.message}',
      );
    }
    final checkInStart = clock;
    final activeEnd = math.min(clock + activeSecondsPerCheckIn, end);
    var applied = 0;
    while (clock < activeEnd) {
      for (final cmd in bot.decide(e, s, faction.id)) {
        final before = tracker.stock();
        if (e.apply(s, cmd) is CommandOk) {
          applied++;
          tracker.noteSpent(before);
        } else {
          rejected++;
        }
      }
      final step = math.min(activeEnd - clock, decisionEverySeconds);
      e.advance(s, step);
      clock += step;
      tracker.sample();
      noteMilestones(checkIn);
    }
    if (applied == 0) {
      deadZones.add(
        DeadZone(checkInIndex: checkIn, gameHours: checkInStart / 3600),
      );
    }
    final next = math.min((checkIn + 1) * checkInEverySeconds, end);
    if (next > clock) {
      e.catchUpOffline(s, next - clock);
      clock = next;
      tracker.sample();
    }
    checkIn++;
    noteMilestones(checkIn);
  }

  final stock = tracker.stock();
  return BalanceReport(
    botName: bot.name,
    seed: seed,
    hours: hours,
    checkIns: checkIn,
    milestones: hits,
    milestonesNotReached: [
      for (final m in c.milestones)
        if (!hits.any((h) => h.id == m.id)) m,
    ],
    deadZones: deadZones,
    unusedResources: tracker.unused(),
    finalStock: {
      for (final id in c.resources.keys)
        if (stock[id] case final v? when !v.isZero) id: formatNumber(v),
    },
    finalCredits: formatNumber(faction.credits),
    bottleneckLog: bottleneckLog,
    rejectedCommands: rejected,
  );
}

/// Watches which resources a faction produces and uses or sells.
final class _Tracker {
  _Tracker(this.c, this.s, this.factionId);

  final Content c;
  final GameState s;
  final String factionId;
  final Set<String> _produced = {};
  final Set<String> _used = {};

  /// Resource id to units held over the faction's bodies.
  Map<String, BigNum> stock() {
    final total = <String, BigNum>{};
    for (final b in s.bodies) {
      if (b.ownerId != factionId) continue;
      for (final MapEntry(key: id, value: v) in b.stock.entries) {
        total[id] = (total[id] ?? const BigNum.zero()) + v;
      }
    }
    return total;
  }

  /// Records what ran in the last step and what the market is absorbing.
  ///
  /// Sales show as a saturation below 1, which takes up to
  /// `marketRecoverySeconds` to wear off, so sampling every check-in sees
  /// any steady selling.
  void sample() {
    for (final body in s.bodies) {
      if (body.ownerId != factionId) continue;
      for (final b in body.buildings) {
        if (b.crew == 0 || b.lastRunFraction <= 0) continue;
        final def = c.buildings[b.defId]!;
        if (def.kind == BuildingKind.extractor) {
          if (b.depositResourceId case final id?) _produced.add(id);
        } else {
          _produced.addAll(def.outputs.keys);
        }
        _used.addAll(def.inputs.keys);
      }
    }
    for (final MapEntry(key: id, value: sat) in s.market.saturation.entries) {
      if (sat < 1) _used.add(id);
    }
  }

  /// Records resources whose stock a command just took, compared with
  /// [before].
  void noteSpent(Map<String, BigNum> before) {
    final after = stock();
    for (final MapEntry(key: id, value: v) in before.entries) {
      if ((after[id] ?? const BigNum.zero()) < v) _used.add(id);
    }
  }

  /// Resources never produced, or never used or sold, in content order.
  List<String> unused() => [
    for (final id in c.resources.keys)
      if (!_produced.contains(id) || !_used.contains(id)) id,
  ];
}
