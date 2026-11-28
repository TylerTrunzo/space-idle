import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/building_row_view.dart';
import 'package:space_idle/view/messages.dart';
import 'package:space_idle/view/view_models.dart' show autoSellStepSeconds;

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
  for (final p in runningProjects(c.state, c.playerId)) projectView(c, p),
];

/// The view of project [p], one of the player's or any faction's.
ProjectView projectView(GameController c, ProjectState p) {
  final s = c.state;
  final span = p.finishAt - p.startedAt;
  final done = span <= 0 ? 1.0 : (s.time - p.startedAt) / span;
  String body(String id) =>
      s.bodies.where((b) => b.id == id).firstOrNull?.name ?? id;
  // The project's own faction's level: another faction's stage is its own.
  final owner = s.factions.where((f) => f.id == p.factionId).firstOrNull;
  final level = (owner?.megaprojectLevels[p.targetId] ?? 0) + 1;
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
    required this.owed,
    this.holders = const [],
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

  /// What the stage still owes of it, whole units; zero once paid.
  final BigNum owed;

  /// For a good still owed, the owned bodies holding a whole unit or more
  /// of it, the fullest first, each with what it would hand over (its
  /// stock, up to [owed]); empty for credits.
  final List<ContractSource> holders;
}

/// An open contract holding goods a megaproject fed on its own still
/// owes (the report's `contractBlocksDelivery`).
@immutable
final class MegaprojectBlock {
  /// Creates a block.
  const MegaprojectBlock({required this.contractId, required this.text});

  /// The contract, for a Go to its card.
  final String contractId;

  /// "Veyra Exchange's contract holds 120 Hull Plate this needs".
  final String text;
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
    required this.runningBonus,
    required this.lines,
    required this.running,
    required this.queued,
    required this.takesDeliveries,
    required this.locked,
    required this.bestSources,
    required this.auto,
    required this.unfunded,
    required this.feed,
    required this.blocks,
    required this.deliverAll,
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

  /// What its bonuses add up to once the stage [lines] are for completes
  /// (level [deliveryLevel] + 1), such as "storage +20%".
  final String nextBonus;

  /// What they add up to once the stage under way completes (level
  /// [level] + 1); null when none is under way.
  final String? runningBonus;

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

  /// Whether the player chose not to fund it: auto-delivery set with
  /// credit auto-pay off and no credits paid this stage
  /// (`megaprojectUnfunded`).
  final bool unfunded;

  /// Whether goods go in on their own now, and why: "Goods go in from
  /// every body each game minute, above what each keeps".
  final String feed;

  /// Contracts holding goods it is fed on its own.
  final List<MegaprojectBlock> blocks;

  /// What "Deliver all goods" would hand over from every owned body, such
  /// as "300 Hull Plate and 3 Survey Drone"; null when no body holds a
  /// whole unit of a good still owed.
  final String? deliverAll;
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
  final takes = megaprojectTakesDeliveries(s, content, c.playerId, m);
  final fed = megaprojectGoodsFed(s, f, m);
  final lines = [
    for (final MapEntry(key: id, value: need) in megaprojectCost(
      content,
      m,
      at,
    ).entries)
      _line(
        c,
        id,
        got[id] ?? const BigNum.zero(),
        need,
        remaining[id] ?? const BigNum.zero(),
      ),
  ];
  final all = <String, BigNum>{
    for (final l in lines)
      if (l.holders.isNotEmpty)
        l.id: _sum([for (final h in l.holders) h.units]).min(l.owed),
  };
  return MegaprojectView(
    id: m.id,
    name: m.name,
    level: level,
    deliveryLevel: at,
    nextBonus: megaprojectBonusText(m, at + 1),
    runningBonus: stage == null ? null : megaprojectBonusText(m, level + 1),
    lines: lines,
    running: stage == null ? null : projectView(c, stage),
    queued: megaprojectStageQueued(s, content, c.playerId, m),
    takesDeliveries: takes,
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
      goodsFedNow: fed,
    ),
    unfunded: megaprojectUnfunded(s, content, c.playerId, m),
    feed: _feedText(c, auto, takes: takes, fed: fed),
    blocks: [
      for (final b in c.flow.contractBlocks)
        if (b.kind == BottleneckKind.contractBlocksDelivery &&
            b.megaprojectId == m.id &&
            b.contractId != null)
          MegaprojectBlock(
            contractId: b.contractId!,
            text:
                "${_contractTitle(c, b.contractId!)}'s contract holds "
                '${formatNumber(b.heldForContract ?? const BigNum.zero())} '
                '${c.content.resources[b.resourceId]?.name ?? b.resourceId} '
                'this needs',
          ),
    ],
    deliverAll: all.isEmpty ? null : costText(c.content, all),
  );
}

/// Whether goods go in on their own now, and why, for [auto] on a
/// megaproject that [takes] deliveries and is [fed] goods now.
String _feedText(
  GameController c,
  MegaprojectAuto auto, {
  required bool takes,
  required bool fed,
}) {
  final horizon = formatDuration(c.content.rules.nearReadyHorizonSeconds);
  final why = auto.credits
      ? 'its credits were due within $horizon of what auto-pay gives it'
      : 'the credits held, the reserve included, paid for the stage';
  return switch (auto.goods) {
    GoodsFeedMode.off => 'Goods go in only when you deliver them',
    _ when !takes => 'Goods go in on their own once it takes deliveries',
    GoodsFeedMode.always =>
      'Goods go in from every body each game minute, above what each keeps',
    GoodsFeedMode.nearReady when fed =>
      'Goods are going in: feeding started because $why, and it keeps '
          'going until the stage is paid for',
    GoodsFeedMode.nearReady =>
      'Goods wait until the stage is near ready: ${auto.credits ? 'its credits due within $horizon of what auto-pay gives it' : 'until the credits held, the reserve included, pay for the stage'}',
  };
}

MegaprojectLine _line(
  GameController c,
  String id,
  BigNum got,
  BigNum need,
  BigNum owed,
) {
  final done = got > need ? need : got;
  final needD = need.toDouble();
  final holders = <ContractSource>[];
  if (id != creditsKey && owed >= BigNum.from(1)) {
    final bodies = [
      for (final b in c.state.bodies)
        if (b.ownerId == c.playerId &&
            (b.stock[id] ?? const BigNum.zero()) >= BigNum.from(1))
          b,
    ];
    BigNum held(BodyState b) => (b.stock[id] ?? const BigNum.zero()).floor();
    bodies.sort((a, b) => held(b).compareTo(held(a)));
    for (final b in bodies) {
      final gives = held(b).min(owed);
      holders.add(
        ContractSource(
          bodyId: b.id,
          bodyName: b.name,
          amount: formatNumber(gives, rounding: NumberRounding.down),
          units: gives,
        ),
      );
    }
  }
  return MegaprojectLine(
    id: id,
    name: id == creditsKey ? 'Credits' : c.content.resources[id]!.name,
    delivered: formatNumber(done.floor(), rounding: NumberRounding.down),
    needed: formatNumber(need),
    fill: needD <= 0 ? 1 : (done.toDouble() / needD).clamp(0.0, 1.0),
    owed: owed.ceil(),
    holders: holders,
  );
}

BigNum _sum(Iterable<BigNum> xs) =>
    xs.fold(const BigNum.zero(), (t, x) => t + x);

/// "20K credits and 3 Survey Drone": a cost or a delivery, credits first
/// as the core lists them.
String costText(Content c, Map<String, BigNum> m) => [
  for (final MapEntry(key: k, value: v) in m.entries)
    k == creditsKey
        ? '${formatNumber(v)} credits'
        : '${formatNumber(v)} ${c.resources[k]?.name ?? k}',
].join(' and ');

String _contractTitle(GameController c, String contractId) {
  final k = c.state
      .faction(c.playerId)
      .contracts
      .where((k) => k.id == contractId)
      .firstOrNull;
  return k == null
      ? 'A'
      : c.content.contractTemplates[k.templateId]?.issuer ?? k.templateId;
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
    required this.units,
  });

  /// Body id.
  final String bodyId;

  /// Its name.
  final String bodyName;

  /// What it would hand over: its whole units, up to what is owed.
  final String amount;

  /// The same, as a number, for the command.
  final BigNum units;
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
    required this.remaining,
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

  /// Units still wanted, for a delivery's amount.
  final BigNum remaining;
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
  final owed = k.remaining.ceil();
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
          amount: formatNumber(
            held(b).floor().min(owed),
            rounding: NumberRounding.down,
          ),
          units: held(b).floor().min(owed),
        ),
    ],
    remaining: owed,
  );
}

/// What "Deliver all" on contract [contractId] would do, worked out on a
/// copy of the state: the units each body gives (the outcome's
/// `fromBodies`), or why it would fail.
sealed class ContractPreview {
  const ContractPreview();
}

/// The delivery would go through.
final class ContractPreviewReady extends ContractPreview {
  /// Creates a preview.
  const ContractPreviewReady({
    required this.gives,
    required this.total,
    required this.warnings,
  });

  /// Each body's name and what it gives, in the order taken.
  final List<NamedValue> gives;

  /// What it delivers in all, such as "150 Iron Ore".
  final String total;

  /// For each body whose own buildings use the good: "Kora's buildings
  /// use Iron Ore: they will run short".
  final List<String> warnings;
}

/// The delivery would fail, as the command says.
final class ContractPreviewFailed extends ContractPreview {
  /// Creates a preview.
  const ContractPreviewFailed(this.message);

  /// The command's message.
  final String message;
}

/// [ContractPreview] of delivering contract [contractId] in full from
/// every body: an event's work (a tap), not a frame's, since it copies the
/// state.
ContractPreview contractDeliverAllPreview(GameController c, String contractId) {
  final s = c.state;
  final k = s
      .faction(c.playerId)
      .contracts
      .where((k) => k.id == contractId)
      .firstOrNull;
  if (k == null) return const ContractPreviewFailed('That contract is gone');
  final copy = s.copy();
  final r = c.engine.apply(
    copy,
    DeliverContractCommand(c.playerId, k.id, null, k.remaining.ceil()),
  );
  switch (r) {
    case CommandFailed(:final message):
      return ContractPreviewFailed(message);
    case CommandOk(outcome: final ContractProgress o):
      String name(String id) =>
          s.bodies.where((b) => b.id == id).firstOrNull?.name ?? id;
      final res = c.content.resources[k.resourceId]?.name ?? k.resourceId;
      return ContractPreviewReady(
        gives: [
          for (final MapEntry(key: b, value: v) in o.fromBodies.entries)
            NamedValue(name(b), formatNumber(v)),
        ],
        total: '${formatNumber(o.delivered)} $res',
        warnings: [
          for (final b in o.fromBodies.keys)
            if (_usesLocally(c, b, k.resourceId))
              "${name(b)}'s own buildings use $res: taking it can leave "
                  'them short',
        ],
      );
    case CommandOk():
      return const ContractPreviewFailed('Nothing would be delivered');
  }
}

/// Whether body [bodyId]'s own buildings use [resourceId], as an auto-sell
/// rule's keep counts it (`autoSellKeep`'s `localUse`).
bool _usesLocally(GameController c, String bodyId, String resourceId) =>
    autoSellKeep(
      c.state,
      c.content,
      AutoSellRule(
        bodyId: bodyId,
        resourceId: resourceId,
        keepAtLeast: const BigNum.zero(),
      ),
      autoSellStepSeconds,
    ).localUse >
    const BigNum.zero();

/// One system's survey: the next unsurveyed signal there, the owned body
/// that would pay for it, the cost and the time.
@immutable
final class SurveyView {
  /// Creates a view.
  const SurveyView({
    required this.systemId,
    required this.systemName,
    required this.signals,
    required this.sourceBodyId,
    required this.sourceName,
    required this.cost,
    required this.price,
    required this.time,
    required this.blockedReason,
  });

  /// The system.
  final String systemId;

  /// Its name.
  final String systemName;

  /// Unsurveyed signals there (`unsurveyedSignals`).
  final int signals;

  /// The owned body in the system whose drones would go: the one holding
  /// the most, with enough; null when none has enough.
  final String? sourceBodyId;

  /// Its name, or null.
  final String? sourceName;

  /// "20K credits and 3 Survey Drone".
  final String cost;

  /// Credits it spends, for the confirm.
  final BigNum price;

  /// How long a survey takes, as "3h".
  final String time;

  /// Why it can't start now, such as "needs 3 Survey Drone on one of your
  /// bodies in Veyra"; null when it can.
  final String? blockedReason;
}

/// A survey row for each system with unsurveyed signals, in galaxy
/// order; empty when no signal is left.
List<SurveyView> surveyViews(GameController c) {
  final s = c.state;
  final content = c.content;
  final cost = surveyCost(content);
  final drone = content.rules.surveyDroneResource;
  final drones = cost[drone] ?? const BigNum.zero();
  final credits = cost[creditsKey] ?? const BigNum.zero();
  final have = s.faction(c.playerId).credits;
  return [
    for (final system in content.galaxy.systems)
      if (unsurveyedSignals(s, content, c.playerId, system.id) case final n
          when n > 0)
        () {
          BodyState? source;
          var most = const BigNum.zero();
          for (final b in s.bodies) {
            if (b.systemId != system.id || b.ownerId != c.playerId) continue;
            final held = b.stock[drone] ?? const BigNum.zero();
            if (held >= drones && (source == null || held > most)) {
              source = b;
              most = held;
            }
          }
          final droneName = content.resources[drone]?.name ?? drone;
          return SurveyView(
            systemId: system.id,
            systemName: system.name,
            signals: n,
            sourceBodyId: source?.id,
            sourceName: source?.name,
            cost: costText(content, cost),
            price: credits,
            time: formatDuration(surveySeconds(content)),
            blockedReason: have < credits
                ? 'needs ${formatNumber(credits)} credits (you have '
                      '${formatNumber(have, rounding: NumberRounding.down)})'
                : source == null
                ? 'needs ${formatNumber(drones)} $droneName on one of your '
                      'bodies in ${system.name}'
                : null,
          );
        }(),
  ];
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
