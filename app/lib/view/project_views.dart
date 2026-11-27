import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/building_row_view.dart';
import 'package:space_idle/view/messages.dart';

/// A project under way: a claim, survey, slot expansion or megaproject
/// stage. Its countdown ticks from game time.
@immutable
final class ProjectView {
  /// Creates a view.
  const ProjectView({
    required this.id,
    required this.kind,
    required this.title,
    required this.bodyId,
    required this.progress,
    required this.remaining,
  });

  /// Project id.
  final String id;

  /// What it does.
  final ProjectKind kind;

  /// "Claiming Brine", "Surveying a signal", "Extra build slot on Kora",
  /// "Orbital Station level 2".
  final String title;

  /// The body it works on; null for a survey (its body is hidden until it
  /// completes) and a megaproject stage.
  final String? bodyId;

  /// How far along it is, 0 to 1.
  final double progress;

  /// Game time left, as `2h 14m`; never negative.
  final String remaining;
}

/// The player's projects under way, soonest to finish first.
List<ProjectView> projectViews(GameController c) => [
  for (final p in runningProjects(c.state, c.playerId)) _project(c, p),
];

ProjectView _project(GameController c, ProjectState p) {
  final s = c.state;
  final span = p.finishAt - p.startedAt;
  final done = span <= 0 ? 1.0 : (s.time - p.startedAt) / span;
  String body(String id) =>
      s.bodies.where((b) => b.id == id).firstOrNull?.name ?? id;
  final level = (s.faction(c.playerId).megaprojectLevels[p.targetId] ?? 0) + 1;
  return ProjectView(
    id: p.id,
    kind: p.kind,
    title: switch (p.kind) {
      ProjectKind.claim => 'Claiming ${body(p.targetId)}',
      ProjectKind.survey => 'Surveying a signal',
      ProjectKind.expandSlots => 'Extra build slot on ${body(p.targetId)}',
      ProjectKind.megaprojectStage =>
        '${c.content.megaprojects[p.targetId]?.name ?? p.targetId} '
            'level $level',
    },
    bodyId: switch (p.kind) {
      ProjectKind.claim || ProjectKind.expandSlots => p.targetId,
      ProjectKind.survey || ProjectKind.megaprojectStage => null,
    },
    progress: done.clamp(0.0, 1.0),
    remaining: formatDuration(p.finishAt - s.time),
  );
}

/// One entry of a megaproject stage's cost: credits or a resource.
@immutable
final class MegaprojectLine {
  /// Creates a line.
  const MegaprojectLine({
    required this.id,
    required this.name,
    required this.delivered,
    required this.needed,
    required this.fill,
  });

  /// `credits` or a resource id.
  final String id;

  /// "Credits" or the resource's name.
  final String name;

  /// Delivered toward it, rounded down.
  final String delivered;

  /// The stage's whole cost of it.
  final String needed;

  /// Delivered over needed, 0 to 1.
  final double fill;
}

/// How a megaproject is fed on its own.
@immutable
final class MegaprojectAutoView {
  /// Creates a view.
  const MegaprojectAutoView({
    required this.goods,
    required this.credits,
    required this.creditWeight,
    required this.goodsFedNow,
  });

  /// When goods go in from every body.
  final GoodsFeedMode goods;

  /// Whether it takes a share of the credits above the auto-pay reserve.
  final bool credits;

  /// Its share of those credits against the others, 0 to 10.
  final int creditWeight;

  /// Whether goods are going in now (`megaprojectGoodsFed`): always for
  /// [GoodsFeedMode.always], for [GoodsFeedMode.nearReady] only once a
  /// stage is near ready.
  final bool goodsFedNow;
}

/// A megaproject's card: the Orbital Station, the Mass Driver.
@immutable
final class MegaprojectView {
  /// Creates a view.
  const MegaprojectView({
    required this.id,
    required this.name,
    required this.level,
    required this.deliveryLevel,
    required this.nextBonus,
    required this.lines,
    required this.running,
    required this.queued,
    required this.takesDeliveries,
    required this.locked,
    required this.bestSources,
    required this.auto,
  });

  /// Megaproject id.
  final String id;

  /// Display name.
  final String name;

  /// Levels completed.
  final int level;

  /// The level whose stage deliveries pay for now: [level], or one more
  /// while a stage is under way.
  final int deliveryLevel;

  /// What its bonuses add up to one level on, such as "storage +20%".
  final String nextBonus;

  /// The cost lines of the stage deliveries pay for.
  final List<MegaprojectLine> lines;

  /// Its stage under way, if any.
  final ProjectView? running;

  /// Whether the next stage is paid for and starts when [running] is done.
  final bool queued;

  /// Whether it takes deliveries now.
  final bool takesDeliveries;

  /// Why it is closed, such as "Opens at Orbital Station level 1 (now
  /// 0)"; null once it is open.
  final String? locked;

  /// Per resource still owed: the owned body holding the most of it, and
  /// how much.
  final Map<String, NamedValue> bestSources;

  /// Its auto-feed settings.
  final MegaprojectAutoView auto;
}

/// Every megaproject, in content order.
List<MegaprojectView> megaprojectViews(GameController c) => [
  for (final m in c.content.megaprojects.values) _megaproject(c, m),
];

MegaprojectView _megaproject(GameController c, MegaprojectDef m) {
  final s = c.state;
  final content = c.content;
  final f = s.faction(c.playerId);
  final level = f.megaprojectLevels[m.id] ?? 0;
  final at = megaprojectDeliveryLevel(s, c.playerId, m);
  final got = f.megaprojectProgress[m.id] ?? const <String, BigNum>{};
  final remaining = megaprojectRemaining(s, content, c.playerId, m);
  final stage = megaprojectStageOf(s, c.playerId, m.id);
  final lock = megaprojectLockedBy(s, content, c.playerId, m);
  final auto = f.megaprojectAuto[m.id] ?? const MegaprojectAuto();
  return MegaprojectView(
    id: m.id,
    name: m.name,
    level: level,
    deliveryLevel: at,
    nextBonus: megaprojectBonusText(m, level + 1),
    lines: [
      for (final MapEntry(key: id, value: need) in megaprojectCost(
        content,
        m,
        at,
      ).entries)
        _line(c, id, got[id] ?? const BigNum.zero(), need),
    ],
    running: stage == null ? null : _project(c, stage),
    queued: megaprojectStageQueued(s, content, c.playerId, m),
    takesDeliveries: megaprojectTakesDeliveries(s, content, c.playerId, m),
    locked: lock == null
        ? null
        : 'Opens at ${content.megaprojects[lock.megaprojectId]?.name} '
              'level ${lock.level} '
              '(now ${f.megaprojectLevels[lock.megaprojectId] ?? 0})',
    bestSources: {
      for (final id in remaining.keys)
        if (id != creditsKey) id: ?_fullest(c, id),
    },
    auto: MegaprojectAutoView(
      goods: auto.goods,
      credits: auto.credits,
      creditWeight: auto.creditWeight,
      goodsFedNow: megaprojectGoodsFed(s, f, m),
    ),
  );
}

MegaprojectLine _line(GameController c, String id, BigNum got, BigNum need) {
  final done = got > need ? need : got;
  final needD = need.toDouble();
  return MegaprojectLine(
    id: id,
    name: id == creditsKey ? 'Credits' : c.content.resources[id]!.name,
    delivered: formatNumber(done.floor(), rounding: NumberRounding.down),
    needed: formatNumber(need),
    fill: needD <= 0 ? 1 : (done.toDouble() / needD).clamp(0.0, 1.0),
  );
}

/// The owned body holding the most of [resourceId] (ties by body order),
/// with the amount; null when none holds any.
NamedValue? _fullest(GameController c, String resourceId) {
  BodyState? best;
  var most = const BigNum.zero();
  for (final b in c.state.bodies) {
    if (b.ownerId != c.playerId) continue;
    final held = b.stock[resourceId] ?? const BigNum.zero();
    if (held > most) {
      best = b;
      most = held;
    }
  }
  return best == null ? null : NamedValue(best.name, formatNumber(most));
}

/// A body that can supply a contract, and how much it holds.
@immutable
final class ContractSource {
  /// Creates a source.
  const ContractSource({
    required this.bodyId,
    required this.bodyName,
    required this.amount,
  });

  /// Body id.
  final String bodyId;

  /// Its name.
  final String bodyName;

  /// What it holds of the contract's resource.
  final String amount;
}

/// A contract on the player's board.
@immutable
final class ContractView {
  /// Creates a view.
  const ContractView({
    required this.id,
    required this.title,
    required this.resourceName,
    required this.delivered,
    required this.quantity,
    required this.fill,
    required this.reward,
    required this.sources,
  });

  /// Contract id.
  final String id;

  /// Who posted it, such as "Veyra Exchange".
  final String title;

  /// The resource it asks for.
  final String resourceName;

  /// Units delivered, rounded down.
  final String delivered;

  /// Units asked for.
  final String quantity;

  /// Delivered over quantity, 0 to 1.
  final double fill;

  /// Credits it pays on completion.
  final String reward;

  /// Owned bodies holding a whole unit or more of the resource, the
  /// fullest first.
  final List<ContractSource> sources;
}

/// The player's contracts, in board order.
List<ContractView> contractViews(GameController c) => [
  for (final k in c.state.faction(c.playerId).contracts) _contract(c, k),
];

ContractView _contract(GameController c, ContractState k) {
  final holders = [
    for (final b in c.state.bodies)
      if (b.ownerId == c.playerId &&
          (b.stock[k.resourceId] ?? const BigNum.zero()) >= BigNum.from(1))
        b,
  ];
  BigNum held(BodyState b) => b.stock[k.resourceId] ?? const BigNum.zero();
  holders.sort((a, b) => held(b).compareTo(held(a)));
  final q = k.quantity.toDouble();
  return ContractView(
    id: k.id,
    title: c.content.contractTemplates[k.templateId]?.issuer ?? k.templateId,
    resourceName: c.content.resources[k.resourceId]!.name,
    delivered: formatNumber(k.delivered.floor(), rounding: NumberRounding.down),
    quantity: formatNumber(k.quantity),
    fill: q <= 0 ? 1 : (k.delivered.toDouble() / q).clamp(0.0, 1.0),
    reward: formatNumber(k.rewardCredits),
    sources: [
      for (final b in holders)
        ContractSource(
          bodyId: b.id,
          bodyName: b.name,
          amount: formatNumber(held(b).floor(), rounding: NumberRounding.down),
        ),
    ],
  );
}

/// When the board's next contract arrives, from its soonest refill: "1h",
/// "due now" once that time has come, or null when none is due.
String? nextContractIn(GameController c) {
  final at = c.state.faction(c.playerId).contractRefillAt;
  if (at.isEmpty) return null;
  final soonest = at.reduce((a, b) => a < b ? a : b);
  final left = soonest - c.state.time;
  return left <= 0 ? 'due now' : formatDuration(left);
}
