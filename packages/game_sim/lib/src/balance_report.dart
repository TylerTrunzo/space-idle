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

/// What the market paid during one day of a session.
final class DayIncome {
  /// Creates a day's income; [share] is copied unmodifiable.
  DayIncome({
    required this.day,
    required this.credits,
    required Map<String, double> share,
  }) : share = Map.unmodifiable(share);

  /// Day number from 1: day 1 is the first 24 h. The last day may be
  /// shorter when the session does not end on a day boundary.
  final int day;

  /// Credits earned from market sales that day.
  final BigNum credits;

  /// Resource id to its share of [credits], in `[0, 1]`, in content order;
  /// resources that earned nothing are left out.
  final Map<String, double> share;

  /// Serializes this day.
  Map<String, Object?> toJson() => {
    'day': day,
    'credits': formatNumber(credits),
    'share': share,
  };
}

/// What kind of new thing a [SessionEvent] is.
enum SessionEventKind {
  /// A milestone reached.
  milestone,

  /// A claim completed: a body is the faction's.
  body,

  /// A survey completed: a hidden body revealed.
  survey,

  /// An extra build slot arrived.
  extraSlot,

  /// A megaproject stage completed: its level rose.
  megaproject,

  /// A contract delivered in full.
  contract,
}

/// Something new the player saw: a milestone, a completed project or a
/// completed contract.
final class SessionEvent {
  /// Creates an event.
  const SessionEvent({
    required this.gameHours,
    required this.day,
    required this.kind,
    required this.text,
  });

  /// Session hours when the player first saw it: when it happened during
  /// a check-in, else on returning to the next one.
  final double gameHours;

  /// What kind of thing it is.
  final SessionEventKind kind;

  /// What happened, such as "Orbital Station level 2" or "Brine claimed".
  final String text;

  /// Day number from 1 in which it was seen: day 1 is the first 24 h.
  /// What is seen as the session ends counts in its last day.
  final int day;

  /// Serializes this event.
  Map<String, Object?> toJson() => {
    'gameHours': gameHours,
    'day': day,
    'kind': kind.name,
    'text': text,
  };
}

/// Where a session stood at the end of one day.
final class DayEnd {
  /// Creates a day's end; [megaprojectLevels] is copied unmodifiable.
  DayEnd({
    required this.day,
    required this.bodiesOwned,
    required this.contractsCompleted,
    required Map<String, int> megaprojectLevels,
  }) : megaprojectLevels = Map.unmodifiable(megaprojectLevels);

  /// Day number from 1.
  final int day;

  /// Bodies the faction owned.
  final int bodiesOwned;

  /// Contracts completed since the session began.
  final int contractsCompleted;

  /// Megaproject id to the faction's level of it, in content order.
  final Map<String, int> megaprojectLevels;

  /// Serializes this day's end.
  Map<String, Object?> toJson() => {
    'day': day,
    'bodiesOwned': bodiesOwned,
    'contractsCompleted': contractsCompleted,
    'megaprojectLevels': megaprojectLevels,
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
    List<DayIncome> days = const [],
    List<SessionEvent> events = const [],
    List<DayEnd> dayEnds = const [],
    Map<String, int> resourceTiers = const {},
  }) : days = List.unmodifiable(days),
       events = List.unmodifiable(events),
       dayEnds = List.unmodifiable(dayEnds),
       resourceTiers = Map.unmodifiable(resourceTiers),
       milestones = List.unmodifiable(milestones),
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

  /// Market income of each day of the session, in order.
  final List<DayIncome> days;

  /// Every new thing the player saw, in the order seen: milestones,
  /// completed claims, surveys, extra slots and megaproject stages, and
  /// completed contracts.
  final List<SessionEvent> events;

  /// Where the faction stood at the end of each day, in order.
  final List<DayEnd> dayEnds;

  /// Resource id to its tier, for income shares by tier.
  final Map<String, int> resourceTiers;

  /// New things ([events]) seen on day [day].
  int newThingsOn(int day) => events.where((e) => e.day == day).length;

  /// Days among the first [days] on which something new was seen.
  int daysWithNewThings(int days) => [
    for (var d = 1; d <= days; d++)
      if (newThingsOn(d) > 0) d,
  ].length;

  /// The fewest days with something new in any 7 days in a row within the
  /// first [days]; 7 if every day had something.
  int worstWeekWithNewThings(int days) {
    var worst = 7;
    for (var start = 1; start + 6 <= days; start++) {
      var n = 0;
      for (var d = start; d < start + 7; d++) {
        if (newThingsOn(d) > 0) n++;
      }
      worst = math.min(worst, n);
    }
    return worst;
  }

  /// Share in `[0, 1]` of [income]'s credits earned from resources of
  /// [tier].
  double tierShare(DayIncome income, int tier) => income.share.entries
      .where((e) => resourceTiers[e.key] == tier)
      .fold(0.0, (t, e) => t + e.value);

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
    'days': [for (final d in days) d.toJson()],
    'events': [for (final e in events) e.toJson()],
    'dayEnds': [for (final d in dayEnds) d.toJson()],
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
      ..writeln('## Income by day')
      ..writeln()
      ..writeln('| Day | Credits earned | Top resources |')
      ..writeln('|---:|---:|---|');
    for (final d in days) {
      final top = d.share.entries.toList()
        ..sort((x, y) => y.value.compareTo(x.value));
      final shown = [
        for (final e in top.take(4))
          '${e.key} ${(e.value * 100).toStringAsFixed(0)}%',
      ];
      b.writeln(
        '| ${d.day} | ${formatNumber(d.credits)} | ${shown.join(', ')} |',
      );
    }
    _writeDays(b);
    b
      ..writeln()
      ..writeln('## Timeline')
      ..writeln()
      ..writeln(
        'Claims, surveys, extra slots, megaproject stages and '
        'contracts, as seen; milestones are listed above.',
      )
      ..writeln();
    final timeline = events.where((e) => e.kind != SessionEventKind.milestone);
    if (timeline.isEmpty) b.writeln('None.');
    for (final e in timeline) {
      b.writeln('- ${_hours(e.gameHours)} h (day ${e.day}): ${e.text}');
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

extension on BalanceReport {
  /// The table of what each day brought and where it ended.
  void _writeDays(StringBuffer b) {
    final first = math.min(21, days.length);
    final megaprojects = dayEnds.isEmpty
        ? const <String>[]
        : dayEnds.first.megaprojectLevels.keys.toList();
    final tiers = {...resourceTiers.values}.toList()..sort();
    final highTiers = [
      for (final t in tiers)
        if (t >= 2) t,
    ];
    b
      ..writeln()
      ..writeln('## Days')
      ..writeln()
      ..writeln(
        'Days with something new (a milestone, project completion, contract '
        'or body) in the first $first: ${daysWithNewThings(first)} of $first; '
        'the worst 7 days in a row had ${worstWeekWithNewThings(first)}.',
      )
      ..writeln()
      ..writeln(
        '| Day | New | Milestones | Projects | Contracts total | Bodies '
        '${[for (final m in megaprojects) '| $m '].join()}'
        '| Earned | Tier 0-1 '
        '${[for (final t in highTiers) '| Tier $t '].join()}|',
      )
      ..writeln(
        '|---:|---:|---:|---:|---:|---:'
        '${'|---:' * megaprojects.length}|---:|---:'
        '${'|---:' * highTiers.length}|',
      );
    for (final income in days) {
      final d = income.day;
      final seen = events.where((e) => e.day == d);
      final end = dayEnds.where((x) => x.day == d).firstOrNull;
      String pct(double v) => '${(v * 100).toStringAsFixed(0)}%';
      final low = tiers
          .where((t) => t <= 1)
          .fold(0.0, (sum, t) => sum + tierShare(income, t));
      b.writeln(
        '| $d | ${seen.length} '
        '| ${seen.where((e) => e.kind == SessionEventKind.milestone).length} '
        '| ${seen.where((e) => e.kind != SessionEventKind.milestone && e.kind != SessionEventKind.contract).length} '
        '| ${end?.contractsCompleted ?? ''} '
        '| ${end?.bodiesOwned ?? ''} '
        '${[for (final m in megaprojects) '| ${end?.megaprojectLevels[m] ?? ''} '].join()}'
        '| ${formatNumber(income.credits)} | ${pct(low)} '
        '${[for (final t in highTiers) '| ${pct(tierShare(income, t))} '].join()}|',
      );
    }
  }
}

String _hours(double h) => h.toStringAsFixed(1);

/// Seconds in a day of session time.
const double _daySeconds = 86400;

/// Plays a new game seeded with [seed] for [hours] with [bot] as the
/// player, checking in every [checkInEverySeconds] (4 times a day by
/// default, spec §6.7), and reports what it reached.
///
/// Each check-in, the bot decides every [decisionEverySeconds] of game time
/// for [activeSecondsPerCheckIn], each command going through
/// [GameEngine.apply]; then [GameEngine.catchUpOffline] covers the time to
/// the next check-in, up to the engine's offline cap. Hours in the report
/// are session time, which runs ahead of game time if the cap cuts a gap.
/// Deterministic for a deterministic bot. [onFinished], if given, gets
/// the final state, for tools that study it further.
BalanceReport runBotSession(
  GameEngine e,
  Bot bot, {
  required int seed,
  required double hours,
  double checkInEverySeconds = 21600,
  double activeSecondsPerCheckIn = 180,
  void Function(GameState s)? onFinished,
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
  final lastDay = (end / _daySeconds).ceil();
  int dayAt(double t) => math.min(t ~/ _daySeconds + 1, lastDay);
  final watch = _Watch(c, s, faction.id, dayAt);
  final events = <SessionEvent>[];
  final dayEnds = <DayEnd>[];
  final deadZones = <DeadZone>[];
  final bottleneckLog = <String>[];
  var rejected = 0;
  var clock = 0.0;
  var checkIn = 0;
  // Sales revenue at the start of each day, then at the end.
  final revenueAt = [Map.of(faction.salesRevenue)];
  // Notes the start of every day that begins by session time [t], one at a
  // time, so a gap of more than a day still records each boundary.
  void noteDaysUpTo(double t) {
    while (revenueAt.length * _daySeconds <= t &&
        revenueAt.length * _daySeconds < end) {
      revenueAt.add(Map.of(faction.salesRevenue));
      dayEnds.add(watch.dayEnd(revenueAt.length - 1));
    }
  }

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
        events.add(
          SessionEvent(
            gameHours: clock / 3600,
            day: dayAt(clock),
            kind: SessionEventKind.milestone,
            text: m.name,
          ),
        );
      }
    }
    events.addAll(watch.changes(clock));
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
      noteDaysUpTo(clock);
    }
    if (applied == 0) {
      deadZones.add(
        DeadZone(checkInIndex: checkIn, gameHours: checkInStart / 3600),
      );
    }
    final next = math.min((checkIn + 1) * checkInEverySeconds, end);
    if (next > clock) {
      // The offline catch-up, capped as the player's megaproject levels
      // allow when it leaves, runs right after the player leaves; it is
      // split at day boundaries so each day's income is its own.
      final simulated = math.min(next - clock, offlineCapFor(s, c, faction.id));
      var t = clock;
      while (t < clock + simulated) {
        final boundary = revenueAt.length * _daySeconds;
        final pieceEnd = boundary > t
            ? math.min(boundary, clock + simulated)
            : clock + simulated;
        e.catchUpOffline(s, pieceEnd - t, capSeconds: pieceEnd - t);
        t = pieceEnd;
        noteDaysUpTo(t);
      }
      clock = next;
      tracker.sample();
    }
    noteDaysUpTo(clock);
    checkIn++;
    noteMilestones(checkIn);
  }

  revenueAt.add(Map.of(faction.salesRevenue));
  dayEnds.add(watch.dayEnd(revenueAt.length - 1));
  onFinished?.call(s);
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
    days: [
      for (var i = 1; i < revenueAt.length; i++)
        _dayIncome(c, i, revenueAt[i - 1], revenueAt[i]),
    ],
    events: events,
    dayEnds: dayEnds,
    resourceTiers: {for (final r in c.resources.values) r.id: r.tier},
  );
}

/// Day [day]'s income: sales revenue [after] the day less [before] it.
DayIncome _dayIncome(
  Content c,
  int day,
  Map<String, BigNum> before,
  Map<String, BigNum> after,
) {
  final earned = {
    for (final id in c.resources.keys)
      if ((after[id] ?? const BigNum.zero()) -
              (before[id] ?? const BigNum.zero())
          case final v when v > const BigNum.zero())
        id: v,
  };
  final total = earned.values.fold(const BigNum.zero(), (t, v) => t + v);
  return DayIncome(
    day: day,
    credits: total,
    share: {
      for (final MapEntry(key: id, value: v) in earned.entries)
        id: (v / total).toDouble(),
    },
  );
}

/// Notes what is new for a faction since it last looked: bodies owned,
/// bodies surveyed, extra slots, megaproject levels and contracts done.
final class _Watch {
  _Watch(this.c, this.s, this.factionId, this.dayAt) {
    _take();
  }

  final Content c;
  final GameState s;
  final String factionId;

  /// The report day of session second `t`.
  final int Function(double t) dayAt;
  Set<String> _owned = {};
  Set<String> _surveyed = {};
  Map<String, int> _slots = {};
  Map<String, int> _levels = {};
  int _contracts = 0;

  FactionState get _faction => s.faction(factionId);

  void _take() {
    _owned = {
      for (final b in s.bodies)
        if (b.ownerId == factionId) b.id,
    };
    _surveyed = {
      for (final b in s.bodies)
        if (b.surveyed) b.id,
    };
    _slots = {for (final b in s.bodies) b.id: b.extraSlots};
    _levels = Map.of(_faction.megaprojectLevels);
    _contracts = _faction.contractsCompleted;
  }

  /// What changed since the last call, each stamped session second
  /// [clock], in body and content order.
  List<SessionEvent> changes(double clock) {
    final out = <SessionEvent>[];
    void add(SessionEventKind kind, String text) => out.add(
      SessionEvent(
        gameHours: clock / 3600,
        day: dayAt(clock),
        kind: kind,
        text: text,
      ),
    );
    for (final b in s.bodies) {
      if (b.surveyed && !_surveyed.contains(b.id)) {
        add(SessionEventKind.survey, '${b.name} surveyed');
      }
      if (b.ownerId == factionId && !_owned.contains(b.id)) {
        add(SessionEventKind.body, '${b.name} claimed');
      }
      if (b.extraSlots > (_slots[b.id] ?? 0)) {
        add(SessionEventKind.extraSlot, 'Extra build slot on ${b.name}');
      }
    }
    for (final m in c.megaprojects.values) {
      final level = _faction.megaprojectLevels[m.id] ?? 0;
      for (var l = (_levels[m.id] ?? 0) + 1; l <= level; l++) {
        add(SessionEventKind.megaproject, '${m.name} level $l');
      }
    }
    for (var n = _contracts + 1; n <= _faction.contractsCompleted; n++) {
      add(SessionEventKind.contract, 'Contract $n completed');
    }
    _take();
    return out;
  }

  /// Where the faction stands now, as the end of day [day].
  DayEnd dayEnd(int day) => DayEnd(
    day: day,
    bodiesOwned: s.bodies.where((b) => b.ownerId == factionId).length,
    contractsCompleted: _faction.contractsCompleted,
    megaprojectLevels: {
      for (final m in c.megaprojects.values)
        m.id: _faction.megaprojectLevels[m.id] ?? 0,
    },
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
