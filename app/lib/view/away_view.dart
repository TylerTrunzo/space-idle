import 'package:game_core/game_core.dart' hide formatDuration;
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/messages.dart';

/// Where a "Go" on the away summary takes the player.
@immutable
sealed class AwayGo {
  const AwayGo();
}

/// The body's panel on the map.
final class AwayGoBody extends AwayGo {
  /// Creates the target.
  const AwayGoBody(this.bodyId);

  /// The body.
  final String bodyId;

  @override
  bool operator ==(Object other) =>
      other is AwayGoBody && other.bodyId == bodyId;

  @override
  int get hashCode => Object.hash(AwayGoBody, bodyId);
}

/// The megaproject's card on the Projects tab, where its auto-delivery is
/// set.
final class AwayGoMegaproject extends AwayGo {
  /// Creates the target.
  const AwayGoMegaproject(this.megaprojectId);

  /// The megaproject.
  final String megaprojectId;

  @override
  bool operator ==(Object other) =>
      other is AwayGoMegaproject && other.megaprojectId == megaprojectId;

  @override
  int get hashCode => Object.hash(AwayGoMegaproject, megaprojectId);
}

/// The contract's card on the Projects tab.
final class AwayGoContract extends AwayGo {
  /// Creates the target.
  const AwayGoContract(this.contractId);

  /// The contract.
  final String contractId;

  @override
  bool operator ==(Object other) =>
      other is AwayGoContract && other.contractId == contractId;

  @override
  int get hashCode => Object.hash(AwayGoContract, contractId);
}

/// One problem on return: what it is, and where Go takes the player.
@immutable
final class AwayProblem {
  /// Creates a line.
  const AwayProblem({required this.text, this.go});

  /// "17 Station Docks on Cinder are running as low as 40%: not enough
  /// Hull Plate (about 1.2M credits an hour)".
  final String text;

  /// Where Go takes the player; null when there is nowhere to go.
  final AwayGo? go;
}

/// One stock change: a resource and how much it rose or fell.
@immutable
final class AwayStockLine {
  /// Creates a line.
  const AwayStockLine({
    required this.name,
    required this.amount,
    required this.gain,
  });

  /// The resource's name.
  final String name;

  /// The change with its sign: "+500", "-200".
  final String amount;

  /// Whether it rose.
  final bool gain;
}

/// Everything the "while you were away" dialog shows, from every pending
/// summary together, built from their typed fields.
@immutable
final class AwayView {
  /// Creates a view.
  const AwayView({
    required this.headline,
    required this.timeLine,
    required this.capped,
    required this.net,
    required this.gains,
    required this.finished,
    required this.contracts,
    required this.milestones,
    required this.stock,
    required this.waste,
    required this.problems,
    required this.attention,
    required this.afford,
    required this.nextGoal,
  });

  /// One line of what matters most: "Away 4h; +1.2M credits; Orbital
  /// Station reached level 3".
  final String headline;

  /// "Away 4d, 12h counted" when the offline cap cut it, else "Away 2h".
  final String timeLine;

  /// Whether the cap cut any of it.
  final bool capped;

  /// The change in credits, in whole credits with its sign: "+1.2M
  /// credits", "+0 credits" under one.
  final String net;

  /// Where the credits came from and went: "Earned 1.5M credits from
  /// sales and contracts", "300K credits went into the Orbital Station".
  final List<String> gains;

  /// Projects that finished: "Claimed Brine", "Surveyed Tessaly", "Extra
  /// build slot on Kora", "Orbital Station reached level 3".
  final List<String> finished;

  /// New contracts still on the board: "Veyra Exchange wants 1K Copper
  /// Ore for 7.5K credits".
  final List<String> contracts;

  /// Milestones reached, by name.
  final List<String> milestones;

  /// The five largest stock changes by their worth.
  final List<AwayStockLine> stock;

  /// "Wasted 1.2K units, worth about 3K credits"; null when nothing was.
  final String? waste;

  /// Up to three problems, those under [minProblemShare] of income left
  /// out.
  final List<AwayProblem> problems;

  /// Contracts holding goods a megaproject fed on its own needs: always
  /// shown, apart from [problems], since they have no credits figure.
  final List<AwayProblem> attention;

  /// "You can now afford to claim Cinder", when something became
  /// affordable while away; else null.
  final String? afford;

  /// What the rates on return reach soonest, as "Next: Millionaire in
  /// 3h"; null when none.
  final String? nextGoal;
}

/// Problems costing less than this share of the hour's income are left
/// out of the summary: a waste row worth a millionth of income is noise.
const double minProblemShare = 0.001;

/// The view of [all], the pending summaries, oldest first: the totals of
/// every one, and the problems of the last (the state on return).
AwayView awayView(GameController c, List<OfflineSummary> all) {
  final s = c.state;
  final content = c.content;
  final p = c.playerId;
  final last = all.isEmpty ? null : all.last;
  final away = all.fold(0.0, (t, x) => t + x.secondsAway);
  final counted = all.fold(0.0, (t, x) => t + x.secondsSimulated);
  final capped = all.any((x) => x.capped);
  BigNum sum(BigNum Function(OfflineSummary) f) =>
      all.fold(const BigNum.zero(), (t, x) => t + f(x));
  final gained = sum((x) => x.creditsGained);
  final earned = sum((x) => x.creditsEarned);
  // Credits paid into each megaproject.
  final paid = <String, BigNum>{};
  for (final x in all) {
    for (final MapEntry(key: m, value: got) in x.autoDelivered.entries) {
      if (got[creditsKey] case final v? when !v.isZero) {
        paid[m] = (paid[m] ?? const BigNum.zero()) + v;
      }
    }
  }
  String mega(String id) => content.megaprojects[id]?.name ?? id;
  final net = '${_signed(gained)} credits';
  final timeLine = capped
      ? 'Away ${formatDuration(away)}, ${formatDuration(counted)} counted'
      : 'Away ${formatDuration(away)}';
  // The levels reached, the last per megaproject.
  final levels = <String, (String, int)>{};
  final finished = <String>[];
  for (final x in all) {
    for (final done in x.projectsCompleted) {
      finished.add(switch (done.kind) {
        ProjectKind.claim => 'Claimed ${done.name}',
        ProjectKind.survey => 'Surveyed ${done.name}',
        ProjectKind.expandSlots => 'Extra build slot on ${done.name}',
        ProjectKind.megaprojectStage =>
          '${done.name} reached level ${done.level ?? '?'}',
      });
      if (done.level case final level?) {
        levels[done.targetId] = (done.name, level);
      }
    }
  }
  final crewShort = last != null && last.housingAfter.overAssigned > 0
      ? 'Crew short: ${last.housingAfter.supported} housed for '
            '${last.housingAfter.assigned} assigned'
      : null;
  final headline = [
    'Away ${formatDuration(away)}',
    if (capped) '${formatDuration(counted)} counted (cap)',
    if (paid.isEmpty)
      net
    else
      'earned ${formatNumber(earned)} credits, '
          '${[for (final MapEntry(key: m, value: v) in paid.entries) '${formatNumber(v)} to ${mega(m)}'].join(' and ')}, '
          'net ${_signed(gained)}',
    ?crewShort,
    for (final (name, level) in levels.values) '$name reached level $level',
  ].join('; ');
  return AwayView(
    headline: headline,
    timeLine: timeLine,
    capped: capped,
    net: net,
    gains: [
      if (!earned.isZero)
        'Earned ${formatNumber(earned)} credits from sales and contracts',
      for (final MapEntry(key: m, value: v) in paid.entries)
        '${formatNumber(v)} credits went into the ${mega(m)}',
    ],
    finished: finished,
    contracts: _contracts(c, all),
    milestones: [
      for (final x in all)
        for (final id in x.milestonesReached)
          content.milestones.where((m) => m.id == id).firstOrNull?.name ?? id,
    ],
    stock: _stock(c, all),
    waste: _waste(all),
    problems: last == null ? const [] : _problems(c, last),
    attention: _attention(c, all),
    afford: _afford(c, s.faction(p).credits - gained),
    nextGoal: last?.nextGoal == null ? null : _goal(c, last!.nextGoal!),
  );
}

/// [v] with its sign, in whole credits: "+1.2M", "-1.5K", "+0" under one
/// either way (float residue of what went in and out).
String _signed(BigNum v) {
  final d = v.toDouble();
  final whole = d.abs() < 1
      ? const BigNum.zero()
      : d.abs() < 1e15
      ? BigNum.from(d.roundToDouble())
      : v;
  return '${whole.isNegative ? '' : '+'}${formatNumber(whole)}';
}

List<String> _contracts(GameController c, List<OfflineSummary> all) {
  final board = {
    for (final k in c.state.faction(c.playerId).contracts) k.id: k,
  };
  return [
    for (final x in all)
      for (final id in x.contractsPosted)
        if (board[id] case final k?)
          '${c.content.contractTemplates[k.templateId]?.issuer ?? k.templateId} '
              'wants ${formatNumber(k.quantity)} '
              '${c.content.resources[k.resourceId]?.name ?? k.resourceId} for '
              '${formatNumber(k.rewardCredits)} credits',
  ];
}

List<AwayStockLine> _stock(GameController c, List<OfflineSummary> all) {
  final change = <String, BigNum>{};
  for (final x in all) {
    for (final MapEntry(key: id, value: v) in x.stockGained.entries) {
      change[id] = (change[id] ?? const BigNum.zero()) + v;
    }
  }
  double worth(MapEntry<String, BigNum> e) =>
      (e.value.toDouble() *
              (c.content.resources[e.key]?.basePrice.toDouble() ?? 1))
          .abs();
  final ranked = [
    for (final e in change.entries)
      if (!e.value.isZero) e,
  ]..sort((a, b) => worth(b).compareTo(worth(a)));
  return [
    for (final e in ranked.take(5))
      AwayStockLine(
        name: c.content.resources[e.key]?.name ?? e.key,
        amount: '${e.value.isNegative ? '' : '+'}${formatNumber(e.value)}',
        gain: !e.value.isNegative,
      ),
  ];
}

String? _waste(List<OfflineSummary> all) {
  final units = all.fold(
    const BigNum.zero(),
    (BigNum t, x) => t + x.totalWasted,
  );
  if (units < BigNum.from(1)) return null;
  final value = all.fold(
    const BigNum.zero(),
    (BigNum t, x) => t + x.wastedValue,
  );
  return 'Wasted ${formatNumber(units)} units, worth about '
      '${formatNumber(value)} credits';
}

/// Up to three of [last]'s problems worth showing: those under
/// [minProblemShare] of an hour's income on return left out, and contract
/// holds left to [AwayView.attention].
List<AwayProblem> _problems(GameController c, OfflineSummary last) {
  final perHour = last.creditsPerSecAfter.toDouble() * 3600;
  final floor = perHour * minProblemShare;
  return [
    for (final b in last.topBottlenecks)
      if (b.kind != BottleneckKind.contractBlocksDelivery &&
          (b.lostCreditsPerHour == null ||
              b.lostCreditsPerHour!.toDouble() >= floor))
        AwayProblem(text: _problemText(c, b), go: _goFor(b)),
  ].take(3).toList();
}

String _problemText(GameController c, Bottleneck b) {
  final text = bottleneckText(c.state, c.content, c.playerId, b);
  final lost = b.lostCreditsPerHour;
  // The diversion's own text says what it costs.
  if (lost == null || b.kind == BottleneckKind.megaprojectDiversion) {
    return text;
  }
  return '$text (about ${formatNumber(lost)} credits an hour)';
}

AwayGo? _goFor(Bottleneck b) => switch (b.kind) {
  BottleneckKind.megaprojectDiversion when b.megaprojectId != null =>
    AwayGoMegaproject(b.megaprojectId!),
  BottleneckKind.contractBlocksDelivery when b.contractId != null =>
    AwayGoContract(b.contractId!),
  _ when b.bodyId != null => AwayGoBody(b.bodyId!),
  _ => null,
};

/// Every contract holding goods a megaproject needs, from the report on
/// return and the summaries, each contract once.
List<AwayProblem> _attention(GameController c, List<OfflineSummary> all) {
  final seen = <String>{};
  return [
    for (final b in [
      ...c.flow.contractBlocks,
      for (final x in all)
        ...x.topBottlenecks.where(
          (b) => b.kind == BottleneckKind.contractBlocksDelivery,
        ),
    ])
      if (b.contractId case final id? when seen.add('$id/${b.resourceId}'))
        AwayProblem(
          text: bottleneckText(c.state, c.content, c.playerId, b),
          go: AwayGoContract(id),
        ),
  ];
}

/// The first of a claim, an extra slot or upgrade levels that the
/// credits on return pay for and the [before] credits did not.
String? _afford(GameController c, BigNum before) {
  final s = c.state;
  final content = c.content;
  final p = c.playerId;
  final now = s.faction(p).credits;
  bool newly(BigNum price) => price <= now && price > before;
  final claim = claimCost(s, content, p);
  final kits = claim[content.rules.outpostKitResource];
  final hasKits =
      kits == null ||
      s.bodies.any(
        (b) =>
            b.ownerId == p &&
            (b.stock[content.rules.outpostKitResource] ??
                    const BigNum.zero()) >=
                kits,
      );
  if (hasKits && newly(claim[creditsKey] ?? const BigNum.zero())) {
    final body = s.bodies
        .where(
          (b) =>
              b.ownerId == null &&
              isVisible(s, b, p) &&
              projectOn(s, ProjectKind.claim, b.id) == null,
        )
        .firstOrNull;
    if (body != null) return 'You can now afford to claim ${body.name}';
  }
  for (final b in s.bodies) {
    if (b.ownerId != p || b.extraSlots >= SaveCodec.maxExtraSlots) continue;
    if (projectOn(s, ProjectKind.expandSlots, b.id) != null) continue;
    if (newly(slotCost(content, b)[creditsKey] ?? const BigNum.zero())) {
      return 'You can now afford an extra build slot on ${b.name}';
    }
  }
  var levels = 0;
  for (final u in upgradeCandidates(s, content, p)) {
    final building = s
        .body(u.bodyId)
        .buildings
        .where((x) => x.id == u.buildingId)
        .firstOrNull;
    if (building == null) continue;
    final price =
        upgradeCost(content, building, u.track)[creditsKey] ??
        const BigNum.zero();
    if (newly(price)) levels++;
  }
  if (levels > 0) {
    return 'You can now afford ${levels == 1 ? 'an upgrade level' : '$levels '
              'upgrade levels'}: Buy max in the top bar buys the best';
  }
  return null;
}

String _goal(GameController c, NextGoal g) {
  final eta = g.etaSeconds;
  final when = eta == null ? '' : ' in ${formatDuration(eta)}';
  final what = switch (g) {
    MilestoneGoal(:final milestoneId) =>
      c.content.milestones
              .where((m) => m.id == milestoneId)
              .map((m) => milestoneGoalText(c.content, m))
              .firstOrNull ??
          milestoneId,
    MegaprojectGoal(:final megaprojectId, :final level) =>
      '${c.content.megaprojects[megaprojectId]?.name ?? megaprojectId} '
          'level $level',
  };
  return 'Next: $what$when';
}
