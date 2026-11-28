import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../report/flow_report.dart';
import '../state/game_state.dart';
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

  /// The [Bottleneck.groupKey] of the bottleneck.
  final String key;

  /// Game time in seconds since which the faction has had it without a
  /// break ([Bottleneck.firstSeenAt]), before the absence began.
  final double since;

  /// Its [Bottleneck.lostCreditsPerHour] as the absence began, from a
  /// report of the state then: like every report figure, one sample step
  /// of that moment, not an average over time before it. Null where that
  /// was not estimated or the report then did not show it.
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

  /// Restores a goal written by [toJson]; throws [FormatException] for a
  /// `kind` it does not know.
  factory NextGoal.fromJson(Map<String, Object?> j) {
    final eta = (j['etaSeconds'] as num?)?.toDouble();
    return switch (j['kind']) {
      'milestone' => MilestoneGoal(
        milestoneId: j['milestoneId']! as String,
        current: BigNum.fromJson(j['current']! as String),
        target: BigNum.fromJson(j['target']! as String),
        etaSeconds: eta!,
      ),
      'megaproject' => MegaprojectGoal(
        megaprojectId: j['megaprojectId']! as String,
        level: j['level']! as int,
        remaining: {
          for (final MapEntry(key: id, value: v)
              in (j['remaining']! as Map<String, Object?>).entries)
            id: BigNum.fromJson(v! as String),
        },
        etaSeconds: eta,
      ),
      final kind => throw FormatException('Unknown next goal kind', kind),
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
/// pay toward it ([megaprojectTakesDeliveries]: open, the host body type
/// owned, below its highest level, not already paid for); its ETA is the
/// longest any entry still owed takes (null when one of them is not being
/// made), with what the faction holds and makes shared out among the
/// megaprojects as auto-delivery shares it ([megaprojectEtas]). A stage
/// still owed credits is left out when the faction set the megaproject's
/// auto-delivery with credit auto-pay off and has paid it none since it
/// opened: the player chose not to fund it, so the soonest milestone or
/// another megaproject comes first. A megaproject whose auto-delivery was
/// never set counts as funded.
/// Ties go to the milestone, then content order.
NextGoal? nextGoal(
  GameState s,
  Content c,
  String factionId,
  FlowReport report,
) {
  final f = s.faction(factionId);
  final income = report.creditsPerSec;
  final wasting = report.bodies.any((b) => b.wastedPerSec.isNotEmpty);
  // Gross output, as `lifetimeProduced` counts it: a milestone on an
  // intermediate is reached by what is made, even when all of it is used.
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

  MilestoneGoal? milestone;
  for (final m in c.milestones) {
    if (f.reachedMilestones.contains(m.id)) continue;
    final rate = rateOf(m.condition);
    if (rate == null) continue;
    final p = milestoneProgress(s, c, factionId, m);
    if (p.met) continue;
    final t = _eta(p.target - p.current, rate);
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
  for (final MapEntry(key: id, value: eta) in megaprojectEtas(
    s,
    c,
    factionId,
    report,
  ).entries) {
    final m = c.megaprojects[id]!;
    if (megaprojectUnfunded(s, c, factionId, m)) continue;
    final goal = MegaprojectGoal(
      megaprojectId: id,
      level: megaprojectDeliveryLevel(s, factionId, m) + 1,
      remaining: megaprojectRemaining(s, c, factionId, m),
      etaSeconds: eta,
    );
    if (stage == null || _sooner(goal.etaSeconds, stage.etaSeconds)) {
      stage = goal;
    }
  }
  if (milestone == null) return stage;
  if (stage == null) return milestone;
  return _sooner(stage.etaSeconds, milestone.etaSeconds) ? stage : milestone;
}

/// Whether [m]'s stage [factionId] pays for still owes credits that it
/// chose not to pay: it set [m]'s auto-delivery
/// ([FactionState.megaprojectAutoSet]) with credit auto-pay off, and has
/// paid it no credits since the stage opened. [nextGoal] leaves such a
/// megaproject out, and so should anything that offers a goal beside it.
/// One whose auto-pay was never set is no choice: a new player still sees
/// its first stage.
bool megaprojectUnfunded(
  GameState s,
  Content c,
  String factionId,
  MegaprojectDef m,
) {
  final f = s.faction(factionId);
  if (!f.megaprojectAutoSet.contains(m.id)) return false;
  if (f.megaprojectAuto[m.id]?.credits ?? false) return false;
  if (!megaprojectRemaining(s, c, factionId, m).containsKey(creditsKey)) {
    return false;
  }
  final paid = f.megaprojectProgress[m.id]?[creditsKey];
  return paid == null || paid <= const BigNum.zero();
}

/// Megaproject id to the game seconds until [factionId] has paid, or can
/// pay, all that the stage it is paying for still needs, at the rates of
/// [report] (its flow report of [s]); null for never. Only megaprojects
/// that take deliveries now and are owed something, in content order.
///
/// What the faction holds and makes of each cost key is shared out as
/// auto-delivery shares it, so stock and income are never counted for two
/// megaprojects fed on their own, and a stage paid by hand waits for what
/// auto-delivery gives the others. Those paid by hand are each timed on
/// what is left once the fed ones have their share: the player chooses
/// which of them comes first.
///
/// - Credits: what is held above the faction's auto-pay reserve, then
///   [FlowReport.creditsPerSec], split by [MegaprojectAuto.creditWeight]
///   among the megaprojects fed credits on their own, a share one cannot
///   use going to the others (as `stepMegaprojectCredits` pays them): the
///   one owing least for its weight is done first, the others go on
///   sharing; those at weight 0 wait for the others. The reserve stays
///   held.
/// - Goods: the faction's stock of the good ([factionStock]), at the
///   larger of the empire's net rate ([FlowReport.empireNet]) and what
///   auto-delivery hands all megaprojects of it a second
///   ([FlowReport.autoDeliveredPerSec]): the first leaves out goods
///   auto-delivery takes before they are counted held, the second the
///   goods auto-sell would sell. The megaprojects fed goods take it in
///   content order, each what is left of the stock, then the rate, until
///   it has all it is owed. One fed goods near ready
///   ([GoodsFeedMode.nearReady]) whose stage is not fed yet starts taking
///   them when [_goodsStarts] has the start rule fire: with credit
///   auto-pay, once what it still owes is no more than
///   [RulesDef.nearReadyHorizonSeconds] of its weight share of income as
///   the others are paid for ([_nearReadyStart]); without it, once its
///   credits are held. From then it is timed on what is made of the good
///   ([FlowReport.netProducedPerSec]) less what the others take, since
///   until then its goods are sold.
///
/// It looks one stage ahead for each: once a megaproject's stage is paid
/// for, its next stage usually starts and takes a share again, which this
/// leaves out. So the soonest ETA, all [nextGoal] uses, is right, and the
/// later ones are lower bounds (18-41% short for the second of two
/// credit-fed megaprojects on bot states); that is why the package does
/// not export it.
Map<String, double?> megaprojectEtas(
  GameState s,
  Content c,
  String factionId,
  FlowReport report,
) {
  final f = s.faction(factionId);
  final owed = <String, Map<String, BigNum>>{
    for (final m in c.megaprojects.values)
      if (megaprojectTakesDeliveries(s, c, factionId, m))
        if (megaprojectRemaining(s, c, factionId, m) case final left
            when left.isNotEmpty)
          m.id: left,
  };
  if (owed.isEmpty) return const {};
  final held = factionStock(s, factionId);
  BigNum rateOf(String key) {
    if (key == creditsKey) return report.creditsPerSec;
    var fed = const BigNum.zero();
    for (final got in report.autoDeliveredPerSec.values) {
      fed = fed + (got[key] ?? const BigNum.zero());
    }
    return (report.empireNet[key] ?? const BigNum.zero()).max(fed);
  }

  final eta = <String, double?>{for (final m in owed.keys) m: 0};
  void note(String m, double? done) {
    final was = eta[m];
    eta[m] = was == null || done == null ? null : math.max(was, done);
  }

  // Credits first: a stage fed goods near ready starts taking them only
  // once its credits are near.
  final creditsDone = <String, double?>{};
  if (owed.values.any((left) => left.containsKey(creditsKey))) {
    _creditEtas(f, owed, rateOf(creditsKey), (m, done) {
      creditsDone[m] = done;
      note(m, done);
    });
  }
  // The megaprojects fed goods now, which take them first in content
  // order; and, for one fed near ready but not yet, when its feeding
  // starts ([_goodsStarts]).
  final fedNow = {
    for (final m in owed.keys)
      if (megaprojectGoodsFed(s, f, c.megaprojects[m]!)) m,
  };
  final goodsFrom = _goodsStarts(
    s,
    c,
    f,
    owed,
    fedNow,
    rateOf(creditsKey),
    creditsDone,
  );

  final keys = <String>{for (final left in owed.values) ...left.keys};
  for (final key in keys) {
    if (key == creditsKey) continue;
    final rate = rateOf(key);
    // Once a near-ready stage's feeding starts, what is made of the good
    // and not used goes in rather than selling.
    final madeRate = rate.max(report.netProducedPerSec(key));
    var pool = held[key] ?? const BigNum.zero();
    // When the megaprojects before have their share: null for never.
    double? from = 0;
    for (final first in [true, false]) {
      for (final MapEntry(key: m, value: left) in owed.entries) {
        final need = left[key];
        if (need == null || fedNow.contains(m) != first) continue;
        // One fed near ready but not yet waits for its feeding to start,
        // and then takes what is made: until then its goods sell.
        final waits = goodsFrom.containsKey(m);
        final start = waits ? goodsFrom[m] : from;
        double? done;
        var after = pool;
        if (from == null || start == null) {
          done = null;
        } else if (pool >= need) {
          done = math.max(from, start);
          after = pool - need;
        } else {
          final wait = _eta(need - pool, waits ? madeRate : rate);
          done = wait == null ? null : math.max(from, start) + wait;
          after = const BigNum.zero();
        }
        // Auto-delivery takes its share in turn; what is paid by hand is
        // the player's to share out, so each such stage is timed on what
        // auto-delivery leaves, as if it came first.
        if (first) (from, pool) = (done, after);
        note(m, done);
      }
    }
  }
  return eta;
}

/// Megaproject id to the game seconds until goods start going in on their
/// own for each megaproject of [owed] fed goods near ready but not yet
/// (not in [fedNow]); null for never. A stage owing no credits starts now;
/// with credit auto-pay, when the start rule would fire as the credits
/// are shared out at [income] ([_nearReadyStart]); without it, once the
/// credits it owes are held ([creditsDone]).
Map<String, double?> _goodsStarts(
  GameState s,
  Content c,
  FactionState f,
  Map<String, Map<String, BigNum>> owed,
  Set<String> fedNow,
  BigNum income,
  Map<String, double?> creditsDone,
) => {
  for (final m in owed.keys)
    if (f.megaprojectAuto[m] case final a?
        when !fedNow.contains(m) && a.goods == GoodsFeedMode.nearReady)
      m: !owed[m]!.containsKey(creditsKey)
          ? 0
          : a.credits
          ? _nearReadyStart(
              f,
              owed,
              m,
              income.toDouble(),
              c.rules.nearReadyHorizonSeconds,
            )
          : creditsDone[m],
};

/// Megaproject id to the game seconds until [factionId]'s megaprojects fed
/// goods near ready, but not fed yet, start taking them, at the rates of
/// [report]: what [megaprojectEtas] times their goods from. Null for
/// never. For tests: the package does not export it.
Map<String, double?> nearReadyStarts(
  GameState s,
  Content c,
  String factionId,
  FlowReport report,
) {
  final f = s.faction(factionId);
  final owed = <String, Map<String, BigNum>>{
    for (final m in c.megaprojects.values)
      if (megaprojectTakesDeliveries(s, c, factionId, m))
        if (megaprojectRemaining(s, c, factionId, m) case final left
            when left.isNotEmpty)
          m.id: left,
  };
  final creditsDone = <String, double?>{};
  if (owed.values.any((left) => left.containsKey(creditsKey))) {
    _creditEtas(f, owed, report.creditsPerSec, (m, done) {
      creditsDone[m] = done;
    });
  }
  return _goodsStarts(
    s,
    c,
    f,
    owed,
    {
      for (final m in owed.keys)
        if (megaprojectGoodsFed(s, f, c.megaprojects[m]!)) m,
    },
    report.creditsPerSec,
    creditsDone,
  );
}

/// Seconds until the near-ready start rule (`startNearReady`) fires for
/// [m], fed credits on its own: the first moment the credits it still owes
/// are no more than [horizon] seconds of its share of [income], the
/// credits above [f]'s reserve and then [income] being shared out among
/// the credit-fed megaprojects of [owed] by weight, as [_creditEtas] has
/// them paid. Its share grows as the others are paid for. 0 when the rule
/// holds now; null when it never does (no income).
double? _nearReadyStart(
  FactionState f,
  Map<String, Map<String, BigNum>> owed,
  String m,
  double income,
  double horizon,
) {
  final fed = [
    for (final MapEntry(key: id, value: left) in owed.entries)
      if (left[creditsKey] case final need?)
        if (f.megaprojectAuto[id] case final a? when a.credits)
          (id: id, need: need.toDouble(), weight: a.creditWeight),
  ];
  final me = fed.where((x) => x.id == m).firstOrNull;
  if (me == null) return 0;
  final weighted = [
    for (final x in fed)
      if (x.weight > 0) x,
  ];
  final zeros = [
    for (final x in fed)
      if (x.weight == 0) x,
  ];
  final first = weighted.fold(0.0, (t, x) => t + x.need);
  final total = fed.fold(0.0, (t, x) => t + x.need);
  // What [x] has received once [paid] has gone in: a fill by weight of
  // those above 0, then an even fill of those at 0.
  double received(({String id, double need, int weight}) x, double paid) {
    final (group, poured, even) = x.weight > 0
        ? (weighted, paid, false)
        : (zeros, math.max(0.0, paid - first), true);
    double w(({String id, double need, int weight}) y) =>
        even ? 1.0 : y.weight.toDouble();
    if (poured >= group.fold(0.0, (t, y) => t + y.need)) return x.need;
    var lo = 0.0;
    var hi = group.fold(0.0, (t, y) => math.max(t, y.need / w(y)));
    for (var i = 0; i < 100; i++) {
      final mid = (lo + hi) / 2;
      final sum = group.fold(0.0, (t, y) => t + math.min(y.need, w(y) * mid));
      if (sum < poured) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return math.min(x.need, w(x) * hi);
  }

  bool near(double paid) {
    final owing = [
      for (final x in fed)
        if (received(x, paid) < x.need * (1 - 1e-12)) x,
    ];
    final anyWeighted = owing.any((x) => x.weight > 0);
    final weights = owing.fold(
      0.0,
      (t, x) => t + (anyWeighted ? x.weight : (x.weight == 0 ? 1 : 0)),
    );
    final mine = anyWeighted ? me.weight : (me.weight == 0 ? 1 : 0);
    final share = weights <= 0 ? 0.0 : mine / weights;
    return me.need - received(me, paid) <= horizon * income * share + 1e-9;
  }

  final now = math.max(0.0, f.credits.toDouble() - f.autoPayReserve.toDouble());
  if (near(now)) return 0;
  if (income <= 0) return null;
  // The rule holds once [me] is paid in full, and the more is paid, the
  // nearer it holds: the first amount paid that meets it.
  var lo = now;
  var hi = math.max(now, total);
  for (var i = 0; i < 100; i++) {
    final mid = (lo + hi) / 2;
    if (near(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  final t = (hi - now) / income;
  return t.isFinite ? t : null;
}

/// [megaprojectEtas] for credits: [note]s, for each megaproject of [owed]
/// that owes credits, when its credits are in at [income], those fed
/// credits on their own sharing what is above [f]'s auto-pay reserve by
/// their weights (as `stepMegaprojectCredits` pays them), the rest each
/// timed on what that leaves.
void _creditEtas(
  FactionState f,
  Map<String, Map<String, BigNum>> owed,
  BigNum income,
  void Function(String m, double? done) note,
) {
  final rate = income.toDouble();
  final held = f.credits.toDouble();
  final spare = held - f.autoPayReserve.toDouble();
  // Seconds until [x] credits have been paid in above the reserve.
  double? until(double x) {
    if (x <= spare) return 0;
    if (rate <= 0) return null;
    final t = (x - spare) / rate;
    return t.isFinite ? t : null;
  }

  final fed = [
    for (final MapEntry(key: m, value: left) in owed.entries)
      if (left[creditsKey] case final need?)
        if (f.megaprojectAuto[m] case final a? when a.credits)
          (m, need.toDouble(), a.creditWeight),
  ];
  // A split by weight, a share one cannot use going to the others, fills
  // each need at a rate in proportion to its weight: the one owing [d] at
  // weight [w] is done once `Σ min(need, weight × d / w)` has gone in.
  // Those at weight 0 wait for every one above 0 to be done, then share
  // what comes evenly; with none above 0, they share from the start.
  final weighted = [
    for (final x in fed)
      if (x.$3 > 0) x,
  ];
  final first = weighted.fold(0.0, (t, x) => t + x.$2);
  double? end = 0;
  var paid = 0.0;
  for (final (m, d, w) in fed) {
    var given = 0.0;
    if (w > 0) {
      for (final (_, other, v) in weighted) {
        given += math.min(other, v * d / w);
      }
    } else {
      given = first;
      for (final (_, other, v) in fed) {
        if (v == 0) given += math.min(other, d);
      }
    }
    final done = until(given);
    note(m, done);
    end = end == null || done == null ? null : math.max(end, done);
    paid += d;
  }
  for (final MapEntry(key: m, value: left) in owed.entries) {
    final need = left[creditsKey];
    if (need == null || (f.megaprojectAuto[m]?.credits ?? false)) continue;
    if (end == null) {
      note(m, null);
      continue;
    }
    // What is held once the fed ones have their share.
    final pool = held + rate * end - paid;
    final short = need.toDouble() - pool;
    if (short <= 0) {
      note(m, end);
    } else if (rate <= 0) {
      note(m, null);
    } else {
      note(m, end + short / rate);
    }
  }
}

/// Seconds [left] takes at [rate]; 0 when nothing is left, null when
/// never.
double? _eta(BigNum left, BigNum? rate) {
  if (left <= const BigNum.zero()) return 0;
  if (rate == null || rate <= const BigNum.zero()) return null;
  final t = (left / rate).toDouble();
  return t.isFinite ? t : null;
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
    Map<String, Map<String, BigNum>> autoDelivered = const {},
    BigNum? creditsEarned,
  }) : contractsPosted = List.unmodifiable(contractsPosted),
       creditsEarned = creditsEarned ?? creditsGained + _paidIn(autoDelivered),
       autoDelivered = Map.unmodifiable({
         for (final MapEntry(key: m, value: got) in autoDelivered.entries)
           m: Map<String, BigNum>.unmodifiable(got),
       }),
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
      // Absent in summaries from before it was kept: what was gained plus
      // what was paid in.
      creditsEarned: switch (j['creditsEarned']) {
        final String v => BigNum.fromJson(v),
        _ => null,
      },
      // Absent in summaries from before auto-delivery.
      autoDelivered: {
        for (final MapEntry(key: m, value: got)
            in ((j['autoDelivered'] as Map<String, Object?>?) ?? const {})
                .entries)
          m: {
            for (final MapEntry(key: id, value: v)
                in (got! as Map<String, Object?>).entries)
              id: BigNum.fromJson(v! as String),
          },
      },
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

  /// Resource id to the change in the player's stock summed over the bodies
  /// it owns, in content order; negative for resources used up. Resources
  /// whose total did not change, or changed only by float residue (within
  /// a relative 1e-12), are left out.
  final Map<String, BigNum> stockGained;

  /// Change in the player's credits; negative if it fell: what it
  /// [creditsEarned] less what auto-delivery paid its megaprojects
  /// ([creditsPaidIn]).
  final BigNum creditsGained;

  /// Credits the player earned while away, from sales and contract
  /// rewards (its lifetime credits gained), before any went to
  /// megaprojects.
  final BigNum creditsEarned;

  /// Credits auto-delivery paid the player's megaprojects while away, all
  /// of them together; [autoDelivered] has them by megaproject.
  BigNum get creditsPaidIn => _paidIn(autoDelivered);

  static BigNum _paidIn(Map<String, Map<String, BigNum>> delivered) {
    var total = const BigNum.zero();
    for (final got in delivered.values) {
      total = total + (got[creditsKey] ?? const BigNum.zero());
    }
    return total;
  }

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

  /// The player's worst bottlenecks after catching up, at most three, by
  /// cause ([FlowReport.groupedBottlenecks], so one entry stands for every
  /// building held back the same way on a body), with what the storage cap
  /// cut while away counted as storage-full entries (its value an hour
  /// over the time simulated): a crew shortage first whenever it costs
  /// credits, then those with an estimate of the credits they lose an
  /// hour, most first ([Bottleneck.lostCreditsPerHour]), then the rest in
  /// report order.
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

  /// Megaproject id to what auto-delivery handed it while away
  /// (`stepMegaprojectAuto`), by cost key (`credits` or a resource id),
  /// megaprojects in content order; those given nothing are left out.
  final Map<String, Map<String, BigNum>> autoDelivered;

  /// The [ongoing] record of [b], one of [topBottlenecks]; null when [b]
  /// began while away.
  OngoingBottleneck? ongoingFor(Bottleneck b) {
    for (final o in ongoing) {
      if (o.key == b.groupKey) return o;
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
    'creditsEarned': creditsEarned.toJson(),
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
    'autoDelivered': {
      for (final MapEntry(key: m, value: got) in autoDelivered.entries)
        m: {
          for (final MapEntry(key: id, value: v) in got.entries) id: v.toJson(),
        },
    },
  };
}
