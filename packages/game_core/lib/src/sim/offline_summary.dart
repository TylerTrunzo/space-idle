import '../content/content.dart';
import '../num/big_num.dart';
import '../num/format.dart';
import '../report/flow_report.dart';
import '../state/game_state.dart';
import '../state/save_codec.dart';
import 'crew.dart';
import 'megaprojects.dart';
import 'milestones.dart';

/// A project that completed while the player was away.
final class CompletedProject {
  /// Creates a record.
  const CompletedProject({
    required this.kind,
    required this.targetId,
    required this.name,
    this.level,
  });

  /// Restores a record written by [toJson].
  factory CompletedProject.fromJson(Map<String, Object?> j) => CompletedProject(
    kind: ProjectKind.values.byName(j['kind']! as String),
    targetId: j['targetId']! as String,
    name: j['name']! as String,
    level: j['level'] as int?,
  );

  /// What the project did.
  final ProjectKind kind;

  /// Body or megaproject it acted on.
  final String targetId;

  /// Display name of [targetId].
  final String name;

  /// For a megaproject stage, the level it brought the megaproject to;
  /// null for other kinds.
  final int? level;

  /// This record as JSON.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'targetId': targetId,
    'name': name,
    'level': ?level,
  };
}

/// One of an [OfflineSummary]'s top bottlenecks that was there before the
/// absence began, and how it changed while the player was away.
final class OngoingBottleneck {
  /// Creates a record.
  const OngoingBottleneck({
    required this.key,
    required this.since,
    required this.worseThanBefore,
    this.lostBefore,
  });

  /// Restores a record written by [toJson].
  factory OngoingBottleneck.fromJson(Map<String, Object?> j) =>
      OngoingBottleneck(
        key: j['key']! as String,
        since: (j['since']! as num).toDouble(),
        worseThanBefore: j['worseThanBefore']! as bool,
        lostBefore: switch (j['lostBefore']) {
          final String v => BigNum.fromJson(v),
          _ => null,
        },
      );

  /// How much its credits lost an hour must grow for it to be
  /// [worseThanBefore]: by more than a quarter.
  static const double worseGrowth = 1.25;

  /// The [Bottleneck.key] of the bottleneck.
  final String key;

  /// Game time in seconds since which the faction has had it without a
  /// break ([Bottleneck.firstSeenAt]), before the absence began.
  final double since;

  /// Its [Bottleneck.lostCreditsPerHour] as the absence began, from a
  /// report of the state then; null where that was not estimated or the
  /// report then did not show it.
  final BigNum? lostBefore;

  /// Whether the credits it loses an hour grew by more than
  /// [worseGrowth] while away; false when either figure is unknown.
  final bool worseThanBefore;

  /// This record as JSON.
  Map<String, Object?> toJson() => {
    'key': key,
    'since': since,
    'worseThanBefore': worseThanBefore,
    'lostBefore': ?lostBefore?.toJson(),
  };
}

/// The goal the player's current rates reach soonest ([nextGoal]):
/// a milestone or a megaproject's next stage.
sealed class NextGoal {
  const NextGoal({this.etaSeconds});

  /// Restores a goal written by [toJson].
  factory NextGoal.fromJson(Map<String, Object?> j) {
    final eta = (j['etaSeconds'] as num?)?.toDouble();
    return switch (j['kind']) {
      'milestone' => MilestoneGoal(
        milestoneId: j['milestoneId']! as String,
        current: BigNum.fromJson(j['current']! as String),
        target: BigNum.fromJson(j['target']! as String),
        etaSeconds: eta!,
      ),
      _ => MegaprojectGoal(
        megaprojectId: j['megaprojectId']! as String,
        level: j['level']! as int,
        remaining: {
          for (final MapEntry(key: id, value: v)
              in (j['remaining']! as Map<String, Object?>).entries)
            id: BigNum.fromJson(v! as String),
        },
        etaSeconds: eta,
      ),
    };
  }

  /// Game seconds until it is reached at the current rates; 0 when it can
  /// be had now, null when the rates never get there.
  final double? etaSeconds;

  /// This goal as JSON, with its `kind`.
  Map<String, Object?> toJson();
}

/// An unreached milestone, as [milestoneProgress] measures it.
final class MilestoneGoal extends NextGoal {
  /// Creates a goal.
  const MilestoneGoal({
    required this.milestoneId,
    required this.current,
    required this.target,
    required double etaSeconds,
  }) : super(etaSeconds: etaSeconds);

  /// Id of the milestone.
  final String milestoneId;

  /// How far the faction is, in the milestone's own unit.
  final BigNum current;

  /// What reaches it, in the same unit.
  final BigNum target;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'milestone',
    'milestoneId': milestoneId,
    'current': current.toJson(),
    'target': target.toJson(),
    'etaSeconds': etaSeconds,
  };
}

/// The next stage of a megaproject the faction can pay toward.
final class MegaprojectGoal extends NextGoal {
  /// Creates a goal; [remaining] is copied unmodifiable.
  MegaprojectGoal({
    required this.megaprojectId,
    required this.level,
    required Map<String, BigNum> remaining,
    super.etaSeconds,
  }) : remaining = Map.unmodifiable(remaining);

  /// Id of the megaproject.
  final String megaprojectId;

  /// The level the stage brings it to.
  final int level;

  /// What the stage still needs ([megaprojectRemaining]): `credits` or a
  /// resource id to units, in cost order.
  final Map<String, BigNum> remaining;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'megaproject',
    'megaprojectId': megaprojectId,
    'level': level,
    'remaining': {
      for (final MapEntry(key: id, value: v) in remaining.entries)
        id: v.toJson(),
    },
    'etaSeconds': etaSeconds,
  };
}

/// What [factionId]'s current rates, from [report] (its flow report of
/// [s]), reach soonest: the unreached milestone with the smallest ETA, or
/// a megaproject's next stage when that comes sooner; null when there is
/// neither.
///
/// Only milestones whose progress grows at a rate the report shows count:
/// credits held and earned (at [FlowReport.creditsPerSec]), units made
/// (the gross rate), stock held (the empire's net rate) and time without
/// waste (while nothing is wasted). A stage counts while the faction can
/// pay toward it (the host body type owned, below its highest level, not
/// already paid for); its ETA is the longest any entry still owed takes,
/// after what the faction holds now, at those rates (null when one of
/// them is not being made). Ties go to the milestone, then content order.
NextGoal? nextGoal(
  GameState s,
  Content c,
  String factionId,
  FlowReport report,
) {
  final f = s.faction(factionId);
  final income = report.creditsPerSec;
  final wasting = report.bodies.any((b) => b.wastedPerSec.isNotEmpty);
  BigNum made(String id) {
    var total = const BigNum.zero();
    for (final b in report.bodies) {
      total = total + (b.producedPerSec[id] ?? const BigNum.zero());
    }
    return total;
  }

  BigNum? rateOf(MilestoneCondition m) => switch (m) {
    CreditsCondition() || CreditsEarnedCondition() => income,
    ProducedCondition(:final resourceId) => made(resourceId),
    StockCondition(:final resourceId) => report.empireNet[resourceId],
    ZeroWasteForCondition() => wasting ? null : BigNum.from(1),
    BodiesOwnedCondition() ||
    BuildingCountCondition() ||
    ContractsCompletedCondition() ||
    ProductionRateCondition() ||
    BuildingTypesBuiltCondition() ||
    CrewTotalCondition() ||
    MegaprojectLevelCondition() ||
    BodiesSurveyedCondition() => null,
  };
  // Seconds [left] takes at [rate]; null when never.
  double? eta(BigNum left, BigNum? rate) {
    if (left <= const BigNum.zero()) return 0;
    if (rate == null || rate <= const BigNum.zero()) return null;
    final t = (left / rate).toDouble();
    return t.isFinite ? t : null;
  }

  MilestoneGoal? milestone;
  for (final m in c.milestones) {
    if (f.reachedMilestones.contains(m.id)) continue;
    final rate = rateOf(m.condition);
    if (rate == null) continue;
    final p = milestoneProgress(s, c, factionId, m);
    if (p.met) continue;
    final t = eta(p.target - p.current, rate);
    if (t == null) continue;
    if (milestone == null || t < milestone.etaSeconds!) {
      milestone = MilestoneGoal(
        milestoneId: m.id,
        current: p.current,
        target: p.target,
        etaSeconds: t,
      );
    }
  }

  MegaprojectGoal? stage;
  Map<String, BigNum>? held;
  for (final m in c.megaprojects.values) {
    final host = m.hostBodyType;
    if (host != null &&
        !s.bodies.any((b) => b.ownerId == factionId && b.typeId == host)) {
      continue;
    }
    final level = megaprojectDeliveryLevel(s, factionId, m);
    if (level >= SaveCodec.maxMegaprojectLevel) continue;
    final owed = megaprojectRemaining(s, c, factionId, m);
    if (owed.isEmpty) continue;
    held ??= factionStock(s, factionId);
    double? longest = 0;
    for (final MapEntry(key: id, value: need) in owed.entries) {
      final have = id == 'credits'
          ? f.credits
          : held[id] ?? const BigNum.zero();
      final t = eta(
        need - have,
        id == 'credits' ? income : report.empireNet[id],
      );
      if (t == null) {
        longest = null;
        break;
      }
      if (t > longest!) longest = t;
    }
    final goal = MegaprojectGoal(
      megaprojectId: m.id,
      level: level + 1,
      remaining: owed,
      etaSeconds: longest,
    );
    if (stage == null || _sooner(goal.etaSeconds, stage.etaSeconds)) {
      stage = goal;
    }
  }
  if (milestone == null) return stage;
  if (stage == null) return milestone;
  return _sooner(stage.etaSeconds, milestone.etaSeconds) ? stage : milestone;
}

/// Whether ETA [a] comes strictly before [b], null being never.
bool _sooner(double? a, double? b) => a != null && (b == null || a < b);

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
    required this.wastedValue,
    required List<String> milestonesReached,
    required List<Bottleneck> topBottlenecks,
    required List<CompletedProject> projectsCompleted,
    required this.housingBefore,
    required this.housingAfter,
    required this.creditsPerSecBefore,
    required this.creditsPerSecAfter,
    List<OngoingBottleneck> ongoing = const [],
    this.nextGoal,
    List<String> contractsPosted = const [],
  }) : contractsPosted = List.unmodifiable(contractsPosted),
       stockGained = Map.unmodifiable(stockGained),
       milestonesReached = List.unmodifiable(milestonesReached),
       topBottlenecks = List.unmodifiable(topBottlenecks),
       ongoing = List.unmodifiable(ongoing),
       projectsCompleted = List.unmodifiable(projectsCompleted);

  /// Restores a summary written by [toJson].
  factory OfflineSummary.fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> maps(String key) =>
        (j[key]! as List).cast<Map<String, Object?>>();
    BigNum big(String key) => BigNum.fromJson(j[key]! as String);
    return OfflineSummary(
      awayFrom: (j['awayFrom']! as num).toDouble(),
      secondsSimulated: (j['secondsSimulated']! as num).toDouble(),
      secondsAway: (j['secondsAway']! as num).toDouble(),
      capSeconds: (j['capSeconds']! as num).toDouble(),
      stockGained: {
        for (final MapEntry(key: id, value: v)
            in (j['stockGained']! as Map<String, Object?>).entries)
          id: BigNum.fromJson(v! as String),
      },
      creditsGained: big('creditsGained'),
      totalWasted: big('totalWasted'),
      wastedValue: big('wastedValue'),
      milestonesReached: (j['milestonesReached']! as List).cast<String>(),
      topBottlenecks: [
        for (final b in maps('topBottlenecks')) Bottleneck.fromJson(b),
      ],
      projectsCompleted: [
        for (final p in maps('projectsCompleted')) CompletedProject.fromJson(p),
      ],
      housingBefore: CrewTotals.fromJson(
        j['housingBefore']! as Map<String, Object?>,
      ),
      housingAfter: CrewTotals.fromJson(
        j['housingAfter']! as Map<String, Object?>,
      ),
      creditsPerSecBefore: big('creditsPerSecBefore'),
      creditsPerSecAfter: big('creditsPerSecAfter'),
      ongoing: [for (final o in maps('ongoing')) OngoingBottleneck.fromJson(o)],
      nextGoal: switch (j['nextGoal']) {
        final Map<String, Object?> g => NextGoal.fromJson(g),
        _ => null,
      },
      contractsPosted: (j['contractsPosted']! as List).cast<String>(),
    );
  }

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
  /// whole absence counted; then, when housing supports fewer crew than
  /// are assigned, "; Crew short: 41 housed for 67 assigned"; then the
  /// highest level each megaproject reached while away, such as
  /// "; Orbital Station reached level 3".
  String get headline {
    final counted = capped
        ? '; ${formatDuration(secondsSimulated)} counted (cap)'
        : '';
    final sign = creditsGained.isNegative ? '' : '+';
    final crew = housingAfter.overAssigned > 0
        ? '; Crew short: ${housingAfter.supported} housed for '
              '${housingAfter.assigned} assigned'
        : '';
    final levels = <String, (String, int)>{};
    for (final p in projectsCompleted) {
      if (p.level case final level?) levels[p.targetId] = (p.name, level);
    }
    return 'Away ${formatDuration(secondsAway)}$counted; '
        '$sign${formatNumber(creditsGained)} credits$crew'
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

  /// What the units in [totalWasted] are worth in credits, each resource
  /// at its market price when the player returns.
  final BigNum wastedValue;

  /// Ids of milestones the player reached while away, in content order.
  final List<String> milestonesReached;

  /// The player's worst bottlenecks after catching up, at most three: a
  /// crew shortage first whenever it costs credits, then those with an
  /// estimate of the credits they lose an hour, most first
  /// ([Bottleneck.lostCreditsPerHour]), then the rest in report order.
  final List<Bottleneck> topBottlenecks;

  /// The [topBottlenecks] that were there before the absence began, in
  /// their order: since when, and whether they got worse.
  final List<OngoingBottleneck> ongoing;

  /// The player's projects that completed while away, in the order they
  /// completed (`finishAt`, then the order they were started), stages that
  /// started while away included (`stepProjects`).
  final List<CompletedProject> projectsCompleted;

  /// Ids of the contracts posted to the player's board while away, in the
  /// order they were posted; they are on the board.
  final List<String> contractsPosted;

  /// The player's crew as the absence began.
  final CrewTotals housingBefore;

  /// The player's crew on return.
  final CrewTotals housingAfter;

  /// The player's steady credits a second as the absence began
  /// ([FlowReport.creditsPerSec]).
  final BigNum creditsPerSecBefore;

  /// The player's steady credits a second on return.
  final BigNum creditsPerSecAfter;

  /// What the player's rates on return reach soonest ([nextGoal]); null
  /// when there is nothing they reach.
  final NextGoal? nextGoal;

  /// The [ongoing] record of [b], one of [topBottlenecks]; null when [b]
  /// began while away.
  OngoingBottleneck? ongoingFor(Bottleneck b) {
    for (final o in ongoing) {
      if (o.key == b.key) return o;
    }
    return null;
  }

  /// This summary as JSON; [OfflineSummary.fromJson] restores it.
  Map<String, Object?> toJson() => {
    'awayFrom': awayFrom,
    'secondsSimulated': secondsSimulated,
    'secondsAway': secondsAway,
    'capSeconds': capSeconds,
    'stockGained': {
      for (final MapEntry(key: id, value: v) in stockGained.entries)
        id: v.toJson(),
    },
    'creditsGained': creditsGained.toJson(),
    'totalWasted': totalWasted.toJson(),
    'wastedValue': wastedValue.toJson(),
    'milestonesReached': milestonesReached,
    'topBottlenecks': [for (final b in topBottlenecks) b.toJson()],
    'ongoing': [for (final o in ongoing) o.toJson()],
    'projectsCompleted': [for (final p in projectsCompleted) p.toJson()],
    'contractsPosted': contractsPosted,
    'housingBefore': housingBefore.toJson(),
    'housingAfter': housingAfter.toJson(),
    'creditsPerSecBefore': creditsPerSecBefore.toJson(),
    'creditsPerSecAfter': creditsPerSecAfter.toJson(),
    'nextGoal': ?nextGoal?.toJson(),
  };
}
