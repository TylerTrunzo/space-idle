import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/messages.dart';
import 'package:space_idle/view/onboarding.dart';

// The goal strip: three slots, Now, Today and Long, each always holding a
// goal or an honest line that there is none. Informational only: no
// streaks, no rewards for coming back.

/// Which slot a goal is in.
enum GoalSlot {
  /// What to do next.
  now,

  /// A milestone within reach.
  today,

  /// A long aim: a megaproject's next stage, a body, a survey.
  long,
}

/// What a goal is, for its icon.
enum GoalKind {
  /// A first-hour guide step.
  guide,

  /// Something held back, with its fix.
  problem,

  /// The upgrade that pays back soonest.
  upgrade,

  /// A milestone.
  milestone,

  /// An open contract.
  contract,

  /// A megaproject's next stage.
  megaproject,

  /// A body to claim.
  claim,

  /// Hidden bodies to survey.
  survey,

  /// Nothing in this slot.
  none,
}

/// What tapping a goal does.
sealed class GoalAction {
  const GoalAction();
}

/// Opens body [bodyId]'s panel on the map.
final class SelectBodyAction extends GoalAction {
  /// Creates the action.
  const SelectBodyAction(this.bodyId);

  /// The body.
  final String bodyId;

  @override
  bool operator ==(Object other) =>
      other is SelectBodyAction && other.bodyId == bodyId;

  @override
  int get hashCode => bodyId.hashCode;
}

/// One slot's goal.
@immutable
final class GoalView {
  /// Creates a goal.
  const GoalView({
    required this.slot,
    required this.kind,
    required this.title,
    this.detail,
    this.progress,
    this.action,
  });

  /// Its slot.
  final GoalSlot slot;

  /// What it is.
  final GoalKind kind;

  /// What it asks, such as "Build a second Smelter".
  final String title;

  /// A line more, such as "1.2K of 5K"; null for none.
  final String? detail;

  /// How far along, 0 to 1; null when it has no measure.
  final double? progress;

  /// What tapping it does; null when it does nothing.
  final GoalAction? action;
}

/// The goal strip.
@immutable
final class GoalStripView {
  /// Creates the strip.
  const GoalStripView({
    required this.now,
    required this.today,
    required this.long,
  });

  /// What to do next.
  final GoalView now;

  /// A milestone within reach, or a contract.
  final GoalView today;

  /// A long aim.
  final GoalView long;
}

/// The goal strip from [c].
///
/// - *now*: the guide's step [guideStep] while the guide runs; else the
///   flow report's first bottleneck, with its fix; else [best], the
///   upgrade that pays back soonest (the controller's, worked out in fills,
///   never here); while none is ready yet, a line saying it is being
///   looked for.
/// - *today*: the unreached milestone nearest done by `milestoneProgress`;
///   else an open contract.
/// - *long*: the core's `nextGoal` (as the away summary has it: the soonest
///   of a milestone and a megaproject stage, skipping one the player chose
///   not to fund), unless it is today's milestone; then the megaproject
///   stage, of every megaproject taking deliveries, nearest done; else the
///   next body to claim; else the signals to survey.
///
/// No slot is ever empty: each ends in an honest line that there is
/// nothing there.
///
/// [nextGoal] is the core's next goal, handed in: it needs the flow
/// report's income run, which the controller works out off the tick
/// (`measuredNow`). Until it is, Long goes straight to its fallbacks, so
/// just after a launch, command or load Long can show a fallback for a
/// frame and then switch to the measured goal once the fill lands. That
/// one-frame change is accepted: holding Long blank until then would be
/// worse, and its fallbacks are true goals too.
GoalStripView goalStripView(
  GameController c, {
  int? guideStep,
  UpgradeAdvice? best,
  bool bestReady = true,
  NextGoal? nextGoal,
}) {
  final today = _today(c);
  return GoalStripView(
    now: _now(c, guideStep, best, bestReady),
    today: today.view,
    long: _long(c, today.milestoneId, nextGoal),
  );
}

GoalView _now(
  GameController c,
  int? guideStep,
  UpgradeAdvice? best,
  bool bestReady,
) {
  final s = c.state;
  final content = c.content;
  final p = c.playerId;
  if (guideStep != null) {
    final step = onboardingSteps[guideStep];
    double? progress;
    if (step.id == 'claim') {
      final cost = claimCost(s, content, p)[creditsKey] ?? const BigNum.zero();
      progress = cost.isZero
          ? 1
          : (s.faction(p).credits.toDouble() / cost.toDouble()).clamp(0, 1);
    }
    return GoalView(
      slot: GoalSlot.now,
      kind: GoalKind.guide,
      title: step.title,
      detail: onboardingDetail(step, s, content, p),
      progress: progress,
      action: switch (_guideBody(c, step)) {
        final id? => SelectBodyAction(id),
        null => null,
      },
    );
  }
  final neck = c.flow.bottlenecks.firstOrNull;
  if (neck != null) {
    return GoalView(
      slot: GoalSlot.now,
      kind: GoalKind.problem,
      title: bottleneckText(s, content, p, neck),
      action: switch (neck.bodyId) {
        final id? => SelectBodyAction(id),
        null => null,
      },
    );
  }
  if (best case final b?) {
    final building = s
        .body(b.bodyId)
        .buildings
        .where((x) => x.id == b.buildingId)
        .firstOrNull;
    final name = building == null
        ? 'a building'
        : content.buildings[building.defId]!.name;
    final track = switch (b.track) {
      UpgradeTrack.speed => 'Speed',
      UpgradeTrack.efficiency => 'Efficiency',
      UpgradeTrack.capacity => 'Capacity',
    };
    return GoalView(
      slot: GoalSlot.now,
      kind: GoalKind.upgrade,
      title:
          '$track on ${s.body(b.bodyId).name} $name: pays back in '
          '${formatDuration(b.preview.paybackSeconds!)}',
      detail: 'Costs ${formatNumber(b.preview.cost)} credits',
      action: SelectBodyAction(b.bodyId),
    );
  }
  return GoalView(
    slot: GoalSlot.now,
    kind: GoalKind.none,
    title: bestReady
        ? 'Nothing held back, and no upgrade to afford yet'
        : 'Looking for the best upgrade…',
  );
}

/// The body a guide step is about: the claim step's first body to claim,
/// the build step's newest body, else the home body.
String? _guideBody(GameController c, OnboardingStep step) {
  final s = c.state;
  final owned = [
    for (final b in s.bodies)
      if (b.ownerId == c.playerId) b,
  ];
  switch (step.id) {
    case 'claim':
      return s.bodies
          .where(
            (b) =>
                b.ownerId == null &&
                isVisible(s, b, c.playerId) &&
                projectOn(s, ProjectKind.claim, b.id) == null,
          )
          .firstOrNull
          ?.id;
    case 'build-away':
      return owned.length > 1 ? owned.last.id : owned.firstOrNull?.id;
    case _:
      return owned.firstOrNull?.id;
  }
}

({GoalView view, String? milestoneId}) _today(GameController c) {
  final s = c.state;
  final content = c.content;
  final f = s.faction(c.playerId);
  MilestoneDef? nearest;
  MilestoneProgress? nearestP;
  var best = -1.0;
  for (final m in content.milestones) {
    if (f.reachedMilestones.contains(m.id)) continue;
    final p = milestoneProgress(s, content, c.playerId, m);
    if (p.met) continue;
    final share = _share(p.current, p.target);
    if (share > best) {
      best = share;
      nearest = m;
      nearestP = p;
    }
  }
  if (nearest != null && nearestP != null) {
    return (
      view: GoalView(
        slot: GoalSlot.today,
        kind: GoalKind.milestone,
        title: milestoneGoalText(content, nearest),
        detail:
            '${formatNumber(nearestP.current, rounding: NumberRounding.down)} '
            'of ${formatNumber(nearestP.target)}',
        progress: best,
      ),
      milestoneId: nearest.id,
    );
  }
  if (f.contracts.firstOrNull case final k?) {
    final name = content.resources[k.resourceId]?.name ?? k.resourceId;
    return (
      view: GoalView(
        slot: GoalSlot.today,
        kind: GoalKind.contract,
        title:
            'Deliver ${formatNumber(k.quantity)} $name for '
            '${formatNumber(k.rewardCredits)} credits',
        detail: '${formatNumber(k.delivered)} delivered',
        progress: _share(k.delivered, k.quantity),
      ),
      milestoneId: null,
    );
  }
  return (
    view: const GoalView(
      slot: GoalSlot.today,
      kind: GoalKind.none,
      title: 'Every milestone is reached, and no contract is open',
    ),
    milestoneId: null,
  );
}

GoalView _long(GameController c, String? todayMilestone, NextGoal? goal) {
  final s = c.state;
  final content = c.content;
  final p = c.playerId;
  switch (goal) {
    case MegaprojectGoal():
      return _stage(
        c,
        content.megaprojects[goal.megaprojectId]!,
        goal.etaSeconds,
      );
    case MilestoneGoal(:final milestoneId)
        when milestoneId != todayMilestone &&
            !s.faction(p).reachedMilestones.contains(milestoneId):
      // The measured goal can be a game minute old: one reached or met
      // since then is passed over, and the bar is the live progress, as
      // Today's is. Only the ETA is the measurement's.
      final m = content.milestones.firstWhere((x) => x.id == milestoneId);
      final live = milestoneProgress(s, content, p, m);
      if (live.met) break;
      return GoalView(
        slot: GoalSlot.long,
        kind: GoalKind.milestone,
        title: milestoneGoalText(content, m),
        detail: _eta(goal.etaSeconds),
        progress: _share(live.current, live.target),
      );
    case _:
      break;
  }
  // Every megaproject taking deliveries that the player funds, as the
  // core's nextGoal counts them, the nearest done.
  GoalView? stage;
  var nearest = -1.0;
  for (final m in content.megaprojects.values) {
    if (!megaprojectTakesDeliveries(s, content, p, m)) continue;
    if (megaprojectUnfunded(s, content, p, m)) continue;
    final v = _stage(c, m, null);
    if ((v.progress ?? 0) > nearest) {
      nearest = v.progress ?? 0;
      stage = v;
    }
  }
  if (stage != null) return stage;
  final claimable = s.bodies
      .where(
        (b) =>
            b.ownerId == null &&
            isVisible(s, b, p) &&
            projectOn(s, ProjectKind.claim, b.id) == null,
      )
      .firstOrNull;
  if (claimable != null) {
    final cost = claimCost(s, content, p);
    final credits = cost[creditsKey] ?? const BigNum.zero();
    final kitId = content.rules.outpostKitResource;
    final kits = cost[kitId] ?? const BigNum.zero();
    // The kits come from one body, as the claim takes them.
    var most = const BigNum.zero();
    for (final b in s.bodies) {
      if (b.ownerId != p) continue;
      final held = b.stock[kitId] ?? const BigNum.zero();
      if (held > most) most = held;
    }
    final kitName = content.resources[kitId]?.name ?? kitId;
    final needsKits = kits > const BigNum.zero();
    final creditShare = _share(s.faction(p).credits, credits);
    return GoalView(
      slot: GoalSlot.long,
      kind: GoalKind.claim,
      title: needsKits
          ? 'Claim ${claimable.name} for ${formatNumber(credits)} credits '
                'and ${formatNumber(kits)} '
                '${kits == BigNum.from(1) ? kitName : plural(kitName)}'
          : 'Claim ${claimable.name} for ${formatNumber(credits)} credits',
      detail: needsKits
          ? '${plural(kitName)}: '
                '${formatNumber(most, rounding: NumberRounding.down)} of '
                '${formatNumber(kits)} on one body'
          : null,
      // The smaller share: either can hold the claim back.
      progress: needsKits
          ? (creditShare < _share(most, kits)
                ? creditShare
                : _share(most, kits))
          : creditShare,
      action: SelectBodyAction(claimable.id),
    );
  }
  var signals = 0;
  for (final system in content.galaxy.systems) {
    signals += unsurveyedSignals(s, content, p, system.id);
  }
  if (signals > 0) {
    return GoalView(
      slot: GoalSlot.long,
      kind: GoalKind.survey,
      title: 'Survey: ${signals == 1 ? '1 signal' : '$signals signals'}',
    );
  }
  return const GoalView(
    slot: GoalSlot.long,
    kind: GoalKind.none,
    title: 'Nothing left in this slot',
  );
}

/// Megaproject [m]'s next stage: its level and how much of it is in, the
/// mean over its cost entries of the share delivered.
GoalView _stage(GameController c, MegaprojectDef m, double? eta) {
  final s = c.state;
  final level = megaprojectDeliveryLevel(s, c.playerId, m);
  final cost = megaprojectCost(c.content, m, level);
  final left = megaprojectRemaining(s, c.content, c.playerId, m);
  var share = 0.0;
  for (final MapEntry(key: id, value: need) in cost.entries) {
    share += 1 - _share(left[id] ?? const BigNum.zero(), need);
  }
  share = cost.isEmpty ? 1 : share / cost.length;
  return GoalView(
    slot: GoalSlot.long,
    kind: GoalKind.megaproject,
    title: '${m.name} level ${level + 1}: ${formatPercent(share)} delivered',
    detail: _eta(eta),
    progress: share,
  );
}

String? _eta(double? seconds) => switch (seconds) {
  null => null,
  final t when t <= 0 => 'Within reach now',
  final t => 'About ${formatDuration(t)} at these rates',
};

/// [part] over [whole], 0 to 1; 1 for nothing to reach.
double _share(BigNum part, BigNum whole) {
  if (whole <= const BigNum.zero()) return 1;
  final v = part.toDouble() / whole.toDouble();
  return v.isFinite ? v.clamp(0.0, 1.0) : 0;
}
