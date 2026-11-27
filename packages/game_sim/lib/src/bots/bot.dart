import 'dart:math' as math;

import 'package:game_core/game_core.dart';

part 'contracts.dart';
part 'megaprojects.dart';
part 'routes.dart';
part 'claims.dart';
part 'planning.dart';
part 'growth.dart';

/// Decides a faction's commands from the state it sees.
///
/// The same shape as the future `FactionController` (spec §5.1). Bots use
/// only public `game_core` APIs and must be deterministic: no wall clock,
/// and every list and map visited in a stable order.
abstract interface class Bot {
  /// Short id used on the command line and in reports.
  String get name;

  /// Commands for [factionId] to issue now against [s], in order.
  ///
  /// Must not change [s]; the caller applies the commands through
  /// [GameEngine.apply]. An empty list means nothing worth doing.
  List<Command> decide(GameEngine e, GameState s, String factionId);
}

/// Buys the cheapest affordable upgrade, building, extra build slot or
/// claim each decision, after filling free crew slots, working its
/// contracts, feeding megaprojects (on their own once open,
/// [_View.autoDeliver], by hand for the rest), surveying and setting
/// auto-sell on surplus.
final class GreedyBot implements Bot {
  @override
  String get name => 'greedy';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    var bought = false;
    return planCommands(e, s, (w) {
      final v = _View(e.content, w, factionId);
      final housekeeping =
          v.assignFreeCrew() ??
          v.workContracts() ??
          v.autoDeliver() ??
          v.deliverMegaproject() ??
          v.survey() ??
          v.autoSell();
      if (housekeeping != null || bought) return housekeeping;
      bought = true;
      return v.cheapestPurchase();
    });
  }
}

/// Plays toward the content's milestones like a steady player.
///
/// Each planning step takes the first of: staff idle buildings and shed
/// crew housing cannot support; start what takes time, so it runs while
/// the player is away: survey a hidden body with drones the station does
/// not need ([_View.survey]), claim a body when affordable, deliver to or
/// discard contracts ([_View.workContracts]), have every open megaproject
/// fed its goods on their own, and its credits once every good its stage
/// lacks is made or held ([_View.autoDeliver]), and deliver by hand what
/// that does not cover
/// ([_View.deliverMegaproject]); fix one of the worst
/// bottlenecks (an efficiency or speed upgrade on the starving supplier,
/// another supplier, or a route, grown when too small); auto-sell surplus;
/// work toward the next milestone, the next megaproject level (growing the
/// supply of a good a stage would take more than a day to get) or more
/// housing when crew runs out, saving credits for it; and with what is
/// left, buy whatever adds the most credits per second for its price.
/// New buildings take their crew as they are built (`autoCrew`).
final class BalancedBot implements Bot {
  /// Creates a balanced bot that fixes buildings short of an input while
  /// they run below [inputWorthFixingBelow] of full rate.
  BalancedBot({
    this.inputWorthFixingBelow = defaultInputWorthFixingBelow,
    this.creditWeights = defaultCreditWeights,
  });

  /// [creditWeights] by default: the Orbital Station takes two shares of
  /// the credits auto-pay hands out to the Mass Driver's one. An optimizer
  /// funds the better buy first: on the balanced bot's own day 7 to 21
  /// states a station level adds 8.5-18.6% to income and a Mass Driver
  /// level 4.9%, for a similar price (the stage 1.7 task 4 report has the
  /// table). The casual bot keeps the default, equal shares.
  static const Map<String, int> defaultCreditWeights = {'orbital_station': 2};

  /// Megaproject id to the weight its credits take of what auto-pay shares
  /// out ([SetMegaprojectAutoCommand.creditWeight]); 1 for any not named.
  final Map<String, int> creditWeights;

  /// [inputWorthFixingBelow] by default: a bot heuristic, not a pacing
  /// rule. The report shows a building cargo feeds at the share a full
  /// step gives it, so many read 80-95% of their supply where a second's
  /// sample showed them full; chasing those spent a casual check-in's few
  /// commands for little ([CasualBot] plays this bot on a budget). Tuned on
  /// the suite's seed-1 sessions (the stage 1.7 task 1 report has seeds 1
  /// to 3). The balanced bot keeps it too: fixing every one of them leads
  /// its day-3 state to one where 60 s catch-up steps and 1 s steps share
  /// magnets arriving in lots differently (a known gap, logged for a later
  /// stage), which the regression suite's catch-up probe would trip on.
  /// Stage 1.7's buy-max bot takes over pacing.
  static const double defaultInputWorthFixingBelow = 0.7;

  /// Bottlenecks, worst first, the bot tries to fix per planning step.
  static const int bottlenecksConsidered = 3;

  /// Run fraction from which a building short of an input is left as it
  /// is; 1 fixes every one.
  final double inputWorthFixingBelow;

  @override
  String get name => 'balanced';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) =>
      plan(e, s, factionId);

  /// [decide]'s plan, ending before the command that would take the
  /// commands other than auto-sell rules past [budget], if given.
  List<Command> plan(
    GameEngine e,
    GameState s,
    String factionId, {
    int? budget,
  }) => _plan(e, s, factionId, budget: budget).cmds;

  /// [plan], with the planning copy as the plan leaves it and the credits
  /// it saves for its next goal ([_Goals.goalSaving]): read once per
  /// decision, at its first step, with [withSaving]; otherwise only if
  /// credit auto-pay's reserve needed it (zero if not).
  ({List<Command> cmds, GameState end, BigNum saving}) _plan(
    GameEngine e,
    GameState s,
    String factionId, {
    int? budget,
    bool withSaving = false,
  }) {
    // Each bottleneck gets one fix per decision: the 1 s sample cannot see
    // a fix work until stock has had a real step to refill.
    final tried = <String>{};
    // Megaprojects whose goods got a step toward more supply this decision.
    final grown = <String>{};
    // Income and the goal saved for are read once per decision: working
    // them out plays the economy forward, and a few commands hardly move
    // them.
    double? income;
    BigNum? saving;
    late GameState end;
    final cmds = planCommands(e, s, budget: budget, onDone: (w) => end = w, (
      w,
    ) {
      late final _View v;
      v = _View(
        e.content,
        w,
        factionId,
        withReport: true,
        grown: grown,
        creditWeights: creditWeights,
        income: () =>
            income ??= math.max(0.0, v.report!.creditsPerSec.toDouble()),
        saving: () => saving ??= v.goalSaving(),
      );
      // Buy-max leaves the goal's saving whether or not auto-pay reads it.
      if (withSaving) saving ??= v.goalSaving();
      final quick =
          v.assignFreeCrew() ??
          v.shedCrew() ??
          v.survey() ??
          v.claim() ??
          v.workContracts() ??
          v.autoDeliver() ??
          v.deliverMegaproject() ??
          v.fixBottleneck(tried, below: inputWorthFixingBelow) ??
          v.autoSell();
      if (quick != null) return quick;
      return switch (v.pursueGoals()) {
        _Do(:final cmd) => cmd,
        _Save(:final credits) => v.grow(reserve: credits),
        _ => v.grow(reserve: const BigNum.zero()),
      };
    });
    return (cmds: cmds, end: end, saving: saving ?? const BigNum.zero());
  }
}

/// Plays like [BalancedBot] on a budget: at most [commandsPerCheckIn]
/// commands per check-in, the way a player with a few minutes to spare
/// acts on the most pressing things and leaves the rest; and once per
/// check-in it taps "buy max" ([BuyUpgradesCommand]), as the app lets
/// every player do, which counts as one of those commands.
///
/// Buy-max spends the spare credits the balanced plan leaves: those held,
/// less what it saves for its next goal (a claim, say), and while
/// megaprojects take credits on their own, no more than the shared
/// auto-pay reserve (an hour of income plus that saving), the credits
/// above it being theirs. So the reserve is the spending allowance, as
/// round 4's buy-max casual found; before any megaproject takes credits,
/// buy-max spends all that is spare.
///
/// Auto-sell rules do not count: the balanced bot re-tunes how much each
/// one keeps as demand changes, which a player sets once (and the app can
/// do for them). A decision more than a minute of game time after the
/// last one starts a new check-in. The commands kept are the first of the
/// balanced plan, so they are still valid in order; buy-max comes after
/// them, in the check-in's first decision.
final class CasualBot implements Bot {
  /// Creates a casual bot.
  CasualBot({this.commandsPerCheckIn = defaultCommandsPerCheckIn});

  /// Commands a casual check-in allows by default.
  static const int defaultCommandsPerCheckIn = 15;

  /// Most commands it issues per check-in, buy-max included.
  final int commandsPerCheckIn;

  final _inner = BalancedBot(creditWeights: const {});
  double? _lastDecision;
  int _used = 0;
  bool _boughtMax = false;

  @override
  String get name => 'casual';

  /// What buy-max may spend of [factionId]'s credits in [s]: what is held,
  /// at most the shared auto-pay reserve while a megaproject set to take
  /// credits on its own can take them now (it owes credits and takes
  /// deliveries: the credits above the reserve are its at the next game
  /// minute), less [saving], what the plan saves for its next goal; never
  /// below zero.
  static BigNum _spare(
    GameState s,
    Content c,
    String factionId,
    BigNum saving,
  ) {
    final f = s.faction(factionId);
    final funding = c.megaprojects.values.any(
      (m) =>
          (f.megaprojectAuto[m.id]?.credits ?? false) &&
          megaprojectTakesDeliveries(s, c, factionId, m) &&
          megaprojectRemaining(s, c, factionId, m).containsKey('credits'),
    );
    final held = funding ? f.credits.min(f.autoPayReserve) : f.credits;
    return (held - saving).max(const BigNum.zero());
  }

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final last = _lastDecision;
    if (last == null || s.time - last > 60) {
      _used = 0;
      _boughtMax = false;
    }
    _lastDecision = s.time;
    final buy = !_boughtMax && _used < commandsPerCheckIn;
    final p = _inner._plan(
      e,
      s,
      factionId,
      budget: commandsPerCheckIn - _used - (buy ? 1 : 0),
      withSaving: buy,
    );
    final cmds = [
      ...p.cmds,
      if (buy)
        BuyUpgradesCommand(
          factionId,
          _spare(p.end, e.content, factionId, p.saving),
        ),
    ];
    _boughtMax = _boughtMax || buy;
    _used += cmds.where((c) => c is! SetAutoSellCommand).length;
    return cmds;
  }
}

/// The command the balanced bot's planning would issue toward more of the
/// good the stage of [megaprojectId] being paid for still lacks that comes
/// slowest ([_Megaprojects._growFor]); null when every good comes within
/// [_stageGoodsWithinSeconds] at today's surplus, no step helps, or the
/// step is to save credits. One planning step's view, for tests.
Command? growthStepFor(
  GameEngine e,
  GameState s,
  String factionId,
  String megaprojectId,
) {
  final v = _View(e.content, s, factionId, withReport: true);
  final m = e.content.megaprojects[megaprojectId]!;
  final step = v._growFor(m, megaprojectRemaining(s, e.content, factionId, m));
  return step is _Do ? step.cmd : null;
}

/// Most commands one decision may plan; a guard against a planning loop.
const int _maxCommandsPerDecision = 60;

/// Storage share a bot keeps of a resource it uses; the rest is sold.
const double _keepShareOfCap = 0.25;

/// Share of a body's storage cap from which its store of a good counts as
/// nearly full, so a contract takes what it holds ([_View.workContracts]).
const double _fullShare = 0.9;

/// Share of a goal's price in hand from which the balanced bot may save
/// for it instead of spending.
const double _saveFrom = 0.5;

/// Share of its credits the balanced bot still spends per purchase while
/// saving for a goal, so a check-in spent saving is not idle.
const double _pettyShare = 0.01;

/// Game seconds of income within which the rest of a goal must be in
/// reach before the balanced bot stops investing and saves for it: one
/// 6 h check-in gap. Further off, investing first gets there sooner.
const double _saveWithinSeconds = 21600;

/// Units per second of a route moving build parts: a slow trickle, one
/// every 100 s.
const double _trickleRate = 0.01;

/// Cargo ships the balanced bot sends to a body that has goods to ship.
const int _shipsSent = 2;

/// Times the demand a route feeding a body's buildings carries, so it
/// keeps up as they grow; its stop level keeps the extra from piling up.
const double _feedHeadroom = 2;

/// Seconds of its buildings' input demand a body keeps back from
/// auto-sell ([_View.keep]).
///
/// The engine's auto-sell already keeps one tick's demand; a minute of it,
/// the engine's longest tick, is a cushion for inputs that arrive in
/// shipments rather than steadily.
const double _demandBufferSeconds = 60;

/// Game seconds within which the goods a megaproject stage still lacks
/// should come at today's rates; slower, the balanced and casual bots grow
/// the supply of the slowest ([_Megaprojects._growFor]).
const double _stageGoodsWithinSeconds = 86400;

/// Share of demand below which a route counts as too small.
const double _routeSlack = 0.9;

/// Share of a market's most steady income above which the balanced bot
/// builds no more makers of that good ([_View.marketFull]).
const double _marketFullShare = 0.9;

/// Free crew below which the balanced bot works toward more housing before
/// saving for a goal, so crew is left to staff the life-support chain.
const int _housingAheadCrew = 3;

/// Run share at or above which a maker counts as fed ([_View._feed]).
const double _fedShare = 0.5;

/// How deep [_View.ensureMade] follows a recipe chain.
const int _maxChainDepth = 8;

/// Plans commands on a deep copy of [s]: asks [next] for a command, applies
/// it to the copy, and repeats until [next] returns null.
///
/// A command the copy rejects ends the plan but is still returned last:
/// the copy matches [s], so the caller's [GameEngine.apply] rejects it too
/// and the bot bug shows up in its count of rejected commands (see
/// `BalanceReport.rejectedCommands`) instead of passing silently.
///
/// With a [budget], the plan ends before the command that would make more
/// than [budget] commands other than auto-sell rules.
///
/// [onDone], if given, gets the copy as the plan leaves it.
List<Command> planCommands(
  GameEngine e,
  GameState s,
  Command? Function(GameState w) next, {
  int? budget,
  void Function(GameState w)? onDone,
}) {
  final w = s.copy();
  final out = <Command>[];
  var counted = 0;
  for (var i = 0; i < _maxCommandsPerDecision; i++) {
    final cmd = next(w);
    if (cmd == null) break;
    if (budget != null && cmd is! SetAutoSellCommand) {
      if (counted >= budget) break;
      counted++;
    }
    out.add(cmd);
    if (e.apply(w, cmd) is! CommandOk) break;
  }
  onDone?.call(w);
  return out;
}

/// Progress toward a goal.
sealed class _Step {
  const _Step();
}

/// Issue [cmd] next.
final class _Do extends _Step {
  const _Do(this.cmd);
  final Command cmd;
}

/// Save up [credits] for the next step; [stage] when they are a
/// megaproject stage's, which credit auto-pay can take instead.
final class _Save extends _Step {
  const _Save(this.credits, {this.stage = false});
  final BigNum credits;
  final bool stage;
}

/// Already met, or waiting on production: nothing to do for it now.
final class _Waiting extends _Step {
  const _Waiting();
}

/// No way forward with what the faction has.
final class _Stuck extends _Step {
  const _Stuck();
}

/// Whether [step] asks for action or saving.
bool _acts(_Step step) => step is _Do || step is _Save;

/// Whether [b] ran its last step on every input it wanted: nothing held it
/// back, or only a crew below its base slots.
bool _runsFreely(BuildingState b) =>
    b.lastLimitReason == null || b.lastLimitReason == 'understaffed';

/// One planning step's view of a faction: the state, its buildings and the
/// decisions built from them.
final class _View {
  _View(
    this.c,
    this.s,
    this.factionId, {
    bool withReport = false,
    double Function()? income,
    BigNum Function()? saving,
    Set<String>? grown,
    this.creditWeights = const {},
  }) : _planIncome = income,
       _planSaving = saving,
       _grown = grown ?? {},
       owned = [
         for (final b in s.bodies)
           if (b.ownerId == factionId) b,
       ],
       report = withReport ? buildFlowReport(s, c, factionId) : null {
    final crew = crewTotals(s, c, factionId);
    freeCrew = crew.free - crew.overAssigned;
    crewEff = crewEfficiency(s, c, factionId);
  }

  final Content c;
  final GameState s;
  final String factionId;

  /// Bodies the faction owns, in body order.
  final List<BodyState> owned;

  /// Flows and bottlenecks; only the balanced bot needs them.
  final FlowReport? report;

  final double Function()? _planIncome;

  /// Credits the plan saves for its next goal, read once per decision.
  final BigNum Function()? _planSaving;

  /// Megaproject id to the credit weight [autoDeliver] gives it; 1 for any
  /// not named.
  final Map<String, int> creditWeights;

  /// Ids of the megaprojects whose goods got a step toward more supply in
  /// this decision ([_Megaprojects._growFor]); one each per decision.
  final Set<String> _grown;

  /// Credits a second the faction earns, never below zero: what the plan
  /// passed in, else the report's [FlowReport.creditsPerSec].
  double get income =>
      _planIncome?.call() ?? math.max(0.0, report!.creditsPerSec.toDouble());

  /// Crew free to assign, or minus the crew assigned beyond what housing
  /// supports.
  late final int freeCrew;
  late final double crewEff;

  /// The faction's megaproject bonuses, which speed some buildings up.
  late final EmpireBonuses bonuses = bonusesFor(s, c, factionId);

  RulesDef get r => c.rules;

  FactionState get faction => s.faction(factionId);

  Iterable<(BodyState, BuildingState)> get buildings sync* {
    for (final body in owned) {
      for (final b in body.buildings) {
        yield (body, b);
      }
    }
  }

  BuildingDef def(BuildingState b) => c.buildings[b.defId]!;

  BigNum stock(BodyState b, String id) => b.stock[id] ?? const BigNum.zero();

  bool canPay(BodyState body, Map<String, BigNum> cost) {
    for (final MapEntry(key: id, value: need) in cost.entries) {
      final have = id == 'credits' ? faction.credits : stock(body, id);
      if (have < need) return false;
    }
    return true;
  }

  bool hasFreeSlot(BodyState body) =>
      body.buildings.length < buildSlots(c, body);

  /// Whether an extra build slot for [body] is under way.
  bool expanding(BodyState body) =>
      projectOn(s, ProjectKind.expandSlots, body.id) != null;

  /// Whether [b]'s type has track [t] and its next level would help
  /// ([upgradeMaxedReason]).
  bool canUpgrade(BuildingState b, UpgradeTrack t) =>
      def(b).upgrades.containsKey(t) && upgradeMaxedReason(c, b, t) == null;

  /// Whether [b] makes [resourceId] when it runs.
  bool makes(BuildingState b, String resourceId) =>
      def(b).kind == BuildingKind.extractor
      ? b.depositResourceId == resourceId
      : def(b).outputs.containsKey(resourceId);

  /// Whether a staffed building on [body] makes [resourceId].
  bool madeAt(BodyState body, String resourceId) =>
      body.buildings.any((b) => b.crew > 0 && makes(b, resourceId));

  /// Whether a staffed building anywhere makes [resourceId].
  bool made(String resourceId) => owned.any((b) => madeAt(b, resourceId));

  bool routeInto(BodyState body, String resourceId) => s.routes.any(
    (rt) => rt.toBodyId == body.id && rt.resourceId == resourceId,
  );

  /// The stop level for a route bringing [resourceId] to [to]: what the
  /// bot keeps there for use ([keepForUse]), so the route fills that and
  /// pauses rather than filling storage; null if it keeps none.
  BigNum? stopFor(BodyState to, String resourceId) {
    final keep = keepForUse(to, resourceId);
    return keep > const BigNum.zero() ? keep : null;
  }

  bool hasShip(BodyState body) =>
      stock(body, r.cargoShipResource) >= BigNum.from(1);

  /// Credits per second of [flow]'s outputs less inputs: the outputs at
  /// what selling that much more would add ([extraRevenue]), the inputs at
  /// their [marginalPrice].
  double value(BuildingFlow flow) {
    var made = 0.0;
    for (final MapEntry(key: id, value: n) in flow.outputs.entries) {
      made += extraRevenue(id, n.toDouble());
    }
    return made - _worth(flow.inputs);
  }

  /// Credits per second that selling [extra] more units a second of [id]
  /// would add once the market settles, on top of what the faction makes
  /// for sale now; while a megaproject stage still wants [id]
  /// ([stageNeed]), its full base price, as the stage takes every unit.
  ///
  /// Steady sales of `q` a second hold the saturation at
  /// `1 / (1 + q × marketRecoverySeconds / depth)` (or the floor), so the
  /// extra units earn the difference in income between `q` and
  /// `q + extra`. `q` is the faction's surplus of [id] a second over its
  /// owned bodies ([surplus]), or, without a flow report, the rate
  /// today's saturation implies. Stock piling up unsold counts, so a good
  /// held back for later is not valued as if every extra unit sold at
  /// full price.
  double extraRevenue(String id, double extra) {
    if (_stageWants(id)) return extra * c.resources[id]!.basePrice.toDouble();
    final now = _soldPerSec(id);
    return _income(id, now + extra) - _income(id, now);
  }

  /// Units of [id] a second the faction makes for sale now: its surplus
  /// over its owned bodies ([surplus]), or, without a flow report, the
  /// rate today's saturation implies.
  double _soldPerSec(String id) {
    if (report != null) {
      return owned.fold(0.0, (t, b) => t + math.max(0.0, surplus(b, id)));
    }
    final sat = s.market.saturation[id] ?? 1;
    final floor = marketFloorOf(c, id);
    return sat >= 1 ? 0.0 : (1 / math.max(sat, floor) - 1) / _marketK(id);
  }

  /// `marketRecoverySeconds / depth` for the faction's sales of [id]: steady
  /// sales of `q` a second hold the saturation at `1 / (1 + k q)`.
  double _marketK(String id) =>
      r.marketRecoverySeconds / marketDepthFor(s, c, factionId, id);

  /// Credits a second that steady sales of [q] units a second of [id] earn.
  double _income(String id, double q) =>
      q *
      c.resources[id]!.basePrice.toDouble() *
      math.max(marketFloorOf(c, id), 1 / (1 + _marketK(id) * q));

  /// Whether what the faction already makes of [id] earns at least
  /// [_marketFullShare] of the most its market pays for steady sales,
  /// `basePrice × depth / marketRecoverySeconds`.
  bool marketFull(String id) {
    final cap = c.resources[id]!.basePrice.toDouble() / _marketK(id);
    return cap > 0 && _income(id, _soldPerSec(id)) >= _marketFullShare * cap;
  }

  /// Whether every good a new [d] on [deposit] would make already fills
  /// its market ([marketFull]), so another one would earn next to nothing.
  bool _onlyFullMarkets(BuildingDef d, String? deposit) {
    final made = d.kind == BuildingKind.extractor
        ? [?deposit]
        : d.outputs.keys.toList();
    return made.isNotEmpty && made.every(marketFull);
  }

  double _worth(Map<String, BigNum> amounts) {
    var v = 0.0;
    for (final MapEntry(key: id, value: n) in amounts.entries) {
      v += n.toDouble() * marginalPrice(id);
    }
    return v;
  }

  /// Credits one more unit of [id] a second would earn once the market
  /// settles: steady sales hold the saturation at `s = 1 / (1 + a × rate)`,
  /// so income `rate × base × s` grows by `base × s²` per extra unit, and
  /// by `base × floor` once the price is at the floor.
  double marginalPrice(String id) {
    final sat = s.market.saturation[id] ?? 1;
    final base = c.resources[id]!.basePrice.toDouble();
    return base * math.max(marketFloorOf(c, id), sat * sat);
  }

  /// Per-second flow of [b] at full input supply.
  BuildingFlow flowOf(BodyState body, BuildingState b) =>
      fullRateFlow(c, body, b, 1, crewEff, bonuses: bonuses);

  /// Per-second flow of a new one-crew [d] on [body].
  BuildingFlow probe(BuildingDef d, BodyState body, String? deposit) =>
      fullRateFlow(
        c,
        body,
        BuildingState(id: '', defId: d.id, depositResourceId: deposit, crew: 1),
        1,
        crewEff,
        bonuses: bonuses,
      );

  /// Deposits [d] can be built on at [body]: each minable deposit for an
  /// extractor, a single null for any other kind.
  List<String?> buildDeposits(BuildingDef d, BodyState body) =>
      d.kind == BuildingKind.extractor
      ? [
          for (final dep in body.deposits)
            if (d.extracts.contains(dep.resourceId)) dep.resourceId,
        ]
      : [null];

  /// Assigns free crew to an unstaffed habitat, else another unstaffed
  /// building, else a building with open slots; body and list order.
  ///
  /// New buildings take their crew as they are built (`autoCrew`); this
  /// staffs what is left: crew freed by new housing, or a building that
  /// was built while crew ran short.
  Command? assignFreeCrew() {
    if (freeCrew < 1) return null;
    final open = [
      for (final (_, b) in buildings)
        if (b.crew < maxCrew(r, def(b), b)) b,
    ];
    final b =
        open
            .where((b) => b.crew == 0 && def(b).kind == BuildingKind.habitat)
            .firstOrNull ??
        open.where((b) => b.crew == 0).firstOrNull ??
        open.firstOrNull;
    if (b == null) return null;
    final target = math.min(maxCrew(r, def(b), b), b.crew + freeCrew);
    return AssignCrewCommand(factionId, b.id, target);
  }

  /// Takes one crew off the best donor while more crew is assigned than
  /// housing supports, which slows every crewed building alike.
  ///
  /// Never from life support: starving habitats house fewer crew, which
  /// slows life support further.
  Command? shedCrew() {
    if (freeCrew >= 0) return null;
    final donor = _crewDonor(null, minCrew: 1);
    if (donor == null) return null;
    return AssignCrewCommand(factionId, donor.id, donor.crew - 1);
  }

  /// Resources habitats need, directly or further up their recipe chains.
  late final Set<String> lifeSupport = () {
    final need = {
      for (final d in c.buildings.values)
        if (d.kind == BuildingKind.habitat) ...d.inputs.keys,
    };
    var grew = true;
    while (grew) {
      grew = false;
      for (final d in c.buildings.values) {
        if (d.kind != BuildingKind.factory) continue;
        if (!d.outputs.keys.any(need.contains)) continue;
        for (final i in d.inputs.keys) {
          if (need.add(i)) grew = true;
        }
      }
    }
    return need;
  }();

  /// Whether [b] is a habitat or makes something habitats depend on.
  bool keepsCrewAlive(BuildingState b) =>
      def(b).kind == BuildingKind.habitat ||
      lifeSupport.any((id) => makes(b, id));

  /// Units of [resourceId] kept back from auto-sell on [body]: what it
  /// keeps for its own use ([keepForUse]) plus what the next stages of the
  /// megaprojects it delivers to by hand ([handStageNeed]) still want of
  /// it, so the goods pile up to be delivered; at most the storage cap.
  ///
  /// The engine's auto-sell already holds back what open contracts and
  /// megaprojects fed on their own still need, so those are not kept twice.
  BigNum keep(BodyState body, String resourceId) {
    final want = handStageNeed(resourceId);
    final own = keepForUse(body, resourceId);
    if (want.isZero) return own;
    return (own + want).min(storageCap(s, c, body));
  }

  /// Units of [resourceId] kept on [body] for the faction's own use: when
  /// a building there uses it, a route ships it, or it pays for builds,
  /// routes or claims; otherwise none. Megaproject stages and contracts get
  /// what is held beyond it.
  ///
  /// The larger of a share of storage and [_demandBufferSeconds] of what
  /// the body's buildings use, at most the storage cap.
  BigNum keepForUse(BodyState body, String resourceId) {
    final used =
        resourceId == r.cargoShipResource ||
        resourceId == r.outpostKitResource ||
        body.buildings.any((b) => def(b).inputs.containsKey(resourceId)) ||
        s.routes.any(
          (rt) => rt.fromBodyId == body.id && rt.resourceId == resourceId,
        ) ||
        c.buildings.values.any((d) => d.buildCost.containsKey(resourceId));
    if (!used) return const BigNum.zero();
    final cap = storageCap(s, c, body);
    var demand = const BigNum.zero();
    for (final b in body.buildings) {
      final need = flowOf(body, b).inputs[resourceId];
      if (need != null) demand = demand + need;
    }
    return cap
        .mulDouble(_keepShareOfCap)
        .max(demand.mulDouble(_demandBufferSeconds))
        .min(cap);
  }

  /// Whether a megaproject's next stage still wants [id]; cached per view.
  bool _stageWants(String id) =>
      _wanted.putIfAbsent(id, () => !stageNeed(id).isZero);
  final Map<String, bool> _wanted = {};

  /// Adds or updates one auto-sell rule so every sellable resource in stock
  /// on an owned body sells above what [keep] holds back.
  Command? autoSell() {
    final rules = faction.autoSell;
    for (final body in owned) {
      for (final res in c.resources.values) {
        if (res.basePrice.isZero) continue;
        final rule = rules
            .where((x) => x.bodyId == body.id && x.resourceId == res.id)
            .firstOrNull;
        if (rule == null && stock(body, res.id).isZero) continue;
        final k = keep(body, res.id);
        if (rule != null && rule.keepAtLeast == k) continue;
        return SetAutoSellCommand(factionId, body.id, res.id, k);
      }
    }
    return null;
  }

  /// The affordable upgrade, build, extra slot or claim with the lowest
  /// credit cost; the first in body, building and content order wins a
  /// tie, and a claim comes last.
  Command? cheapestPurchase() {
    (Command, BigNum)? best;
    void offer(Command cmd, BodyState payer, Map<String, BigNum> cost) {
      if (!canPay(payer, cost)) return;
      final credits = cost['credits'] ?? const BigNum.zero();
      if (best == null || credits < best!.$2) best = (cmd, credits);
    }

    for (final body in owned) {
      for (final b in body.buildings) {
        for (final t in def(b).upgrades.keys) {
          if (!canUpgrade(b, t)) continue;
          offer(UpgradeCommand(factionId, b.id, t), body, upgradeCost(c, b, t));
        }
      }
      if (!hasFreeSlot(body)) {
        if (!expanding(body)) {
          offer(
            ExpandSlotsCommand(factionId, body.id),
            body,
            slotCost(c, body),
          );
        }
        continue;
      }
      for (final d in c.buildings.values) {
        for (final dep in buildDeposits(d, body)) {
          offer(
            BuildCommand(factionId, body.id, d.id, depositResourceId: dep),
            body,
            d.buildCost,
          );
        }
      }
    }
    if (claim() case final ClaimBodyCommand cmd?) {
      offer(cmd, s.body(cmd.sourceBodyId), claimCost(s, c, factionId));
    }
    return best?.$1;
  }
}
