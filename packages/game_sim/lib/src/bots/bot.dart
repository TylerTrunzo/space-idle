import 'dart:math' as math;

import 'package:game_core/game_core.dart';

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
/// claim each decision, after filling free crew slots and setting
/// auto-sell on surplus.
final class GreedyBot implements Bot {
  @override
  String get name => 'greedy';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    var bought = false;
    return planCommands(e, s, (w) {
      final v = _View(e.content, w, factionId);
      final housekeeping = v.assignFreeCrew() ?? v.autoSell();
      if (housekeeping != null || bought) return housekeeping;
      bought = true;
      return v.cheapestPurchase();
    });
  }
}

/// Plays toward the content's milestones like a steady player.
///
/// Each planning step takes the first of: staff idle buildings; fix one of
/// the worst bottlenecks (assign crew, then an efficiency or speed upgrade
/// on the starving supplier, then build another supplier, then open a
/// route); claim a body when affordable; auto-sell surplus; work toward
/// the next milestone or more housing when crew runs out, saving credits
/// for it; and with what is left, buy whatever adds the most credits per
/// second for its price.
final class BalancedBot implements Bot {
  /// Bottlenecks, worst first, the bot tries to fix per planning step.
  static const int bottlenecksConsidered = 3;

  @override
  String get name => 'balanced';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    // Each bottleneck gets one fix per decision: the 1 s sample cannot see
    // a fix work until stock has had a real step to refill.
    final tried = <String>{};
    return planCommands(e, s, (w) {
      final v = _View(e.content, w, factionId, withReport: true);
      final quick =
          v.assignFreeCrew() ??
          v.shedCrew() ??
          v.closeShipTransfers() ??
          v.fixBottleneck(tried) ??
          v.claim() ??
          v.autoSell();
      if (quick != null) return quick;
      return switch (v.pursueGoals()) {
        _Do(:final cmd) => cmd,
        _Save(:final credits) => v.grow(reserve: credits),
        _ => v.grow(reserve: const BigNum.zero()),
      };
    });
  }
}

/// Plays like [BalancedBot] on a budget: at most [commandsPerCheckIn]
/// commands per check-in, the way a player with a few minutes to spare
/// acts on the most pressing things and leaves the rest.
///
/// A decision more than a minute of game time after the last one starts a
/// new check-in. The commands kept are the first of the balanced plan, so
/// they are still valid in order.
final class CasualBot implements Bot {
  /// Creates a casual bot.
  CasualBot({this.commandsPerCheckIn = defaultCommandsPerCheckIn});

  /// Commands a casual check-in allows by default.
  static const int defaultCommandsPerCheckIn = 15;

  /// Most commands it issues per check-in.
  final int commandsPerCheckIn;

  final _inner = BalancedBot();
  double? _lastDecision;
  int _used = 0;

  @override
  String get name => 'casual';

  @override
  List<Command> decide(GameEngine e, GameState s, String factionId) {
    final last = _lastDecision;
    if (last == null || s.time - last > 60) _used = 0;
    _lastDecision = s.time;
    final left = commandsPerCheckIn - _used;
    if (left <= 0) return const [];
    final cmds = _inner.decide(e, s, factionId).take(left).toList();
    _used += cmds.length;
    return cmds;
  }
}

/// Most commands one decision may plan; a guard against a planning loop.
const int _maxCommandsPerDecision = 60;

/// Storage share a bot keeps of a resource it uses; the rest is sold.
const double _keepShareOfCap = 0.25;

/// Share of a goal's price in hand from which the balanced bot saves for
/// it instead of spending.
const double _saveFrom = 0.5;

/// Units per second of a route moving build parts or cargo ships: a slow
/// trickle, one every 100 s.
const double _trickleRate = 0.01;

/// Cargo ships the balanced bot sends to a body that has goods to ship.
const int _shipsSent = 2;

/// Seconds of its buildings' input demand a body keeps back from
/// auto-sell ([_View.keep]).
///
/// The engine's auto-sell already keeps one tick's demand; a minute of it,
/// the engine's longest tick, is a cushion for inputs that arrive in
/// shipments rather than steadily.
const double _demandBufferSeconds = 60;

/// Share of demand below which a route counts as too small.
const double _routeSlack = 0.9;

/// How deep [_View.ensureMade] follows a recipe chain.
const int _maxChainDepth = 8;

/// Plans commands on a deep copy of [s]: asks [next] for a command, applies
/// it to the copy, and repeats until [next] returns null.
///
/// A command the copy rejects ends the plan but is still returned last:
/// the copy matches [s], so the caller's [GameEngine.apply] rejects it too
/// and the bot bug shows up in its count of rejected commands (see
/// `BalanceReport.rejectedCommands`) instead of passing silently.
List<Command> planCommands(
  GameEngine e,
  GameState s,
  Command? Function(GameState w) next,
) {
  final w = s.copy();
  final out = <Command>[];
  for (var i = 0; i < _maxCommandsPerDecision; i++) {
    final cmd = next(w);
    if (cmd == null) break;
    out.add(cmd);
    if (e.apply(w, cmd) is! CommandOk) break;
  }
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

/// Save up [credits] for the next step.
final class _Save extends _Step {
  const _Save(this.credits);
  final BigNum credits;
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

/// One planning step's view of a faction: the state, its buildings and the
/// decisions built from them.
final class _View {
  _View(this.c, this.s, this.factionId, {bool withReport = false})
    : owned = [
        for (final b in s.bodies)
          if (b.ownerId == factionId) b,
      ],
      report = withReport ? buildFlowReport(s, c, factionId) : null {
    freeCrew = availableCrew(s, c, factionId);
    crewEff = crewEfficiency(s, c, factionId);
  }

  final Content c;
  final GameState s;
  final String factionId;

  /// Bodies the faction owns, in body order.
  final List<BodyState> owned;

  /// Flows and bottlenecks; only the balanced bot needs them.
  final FlowReport? report;

  late final int freeCrew;
  late final double crewEff;

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

  bool hasShip(BodyState body) =>
      stock(body, r.cargoShipResource) >= BigNum.from(1);

  /// Credits per second at current prices of [flow]'s outputs less inputs.
  double value(BuildingFlow flow) => _worth(flow.outputs) - _worth(flow.inputs);

  double _worth(Map<String, BigNum> amounts) {
    var v = 0.0;
    for (final MapEntry(key: id, value: n) in amounts.entries) {
      v += n.toDouble() * price(s, c, id).toDouble();
    }
    return v;
  }

  /// Per-second flow of [b] at full input supply.
  BuildingFlow flowOf(BodyState body, BuildingState b) =>
      fullRateFlow(c, body, b, 1, crewEff);

  /// Per-second flow of a new one-crew [d] on [body].
  BuildingFlow probe(BuildingDef d, BodyState body, String? deposit) =>
      fullRateFlow(
        c,
        body,
        BuildingState(id: '', defId: d.id, depositResourceId: deposit, crew: 1),
        1,
        crewEff,
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

  // -------------------------------------------------------------------------
  // Housekeeping shared by both bots.

  /// Assigns free crew to an unstaffed habitat, else another unstaffed
  /// building, else a building with open slots; body and list order.
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

  /// Units of [resourceId] kept on [body] when a building there uses it, a
  /// route ships it, or it pays for builds, routes or claims; otherwise
  /// none.
  ///
  /// The larger of a share of storage and [_demandBufferSeconds] of what
  /// the body's buildings use, at most the storage cap.
  BigNum keep(BodyState body, String resourceId) {
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
          offer(UpgradeCommand(factionId, b.id, t), body, upgradeCost(c, b, t));
        }
      }
      if (!hasFreeSlot(body)) {
        offer(ExpandSlotsCommand(factionId, body.id), body, slotCost(c, body));
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

  // -------------------------------------------------------------------------
  // Balanced bot: bottlenecks.

  /// Units per second of [resourceId] made on [body] beyond what its
  /// buildings use; zero or less when there is none.
  double surplus(BodyState body, String resourceId) {
    final flow = report!.bodies.where((f) => f.bodyId == body.id).firstOrNull;
    if (flow == null) return 0;
    final madeHere = flow.producedPerSec[resourceId] ?? const BigNum.zero();
    final used = flow.consumedPerSec[resourceId] ?? const BigNum.zero();
    return (madeHere - used).toDouble();
  }

  /// The first fix for one of the worst bottlenecks not yet in [tried],
  /// adding it to [tried] when fixed.
  Command? fixBottleneck(Set<String> tried) {
    for (final neck in report!.bottlenecks.take(
      BalancedBot.bottlenecksConsidered,
    )) {
      if (neck.kind == BottleneckKind.storageFull) {
        final key = '${neck.bodyId}:store';
        if (tried.contains(key)) continue;
        final fix = _addStorage(s.body(neck.bodyId!));
        if (fix != null) {
          tried.add(key);
          return fix;
        }
        continue;
      }
      if (neck.kind != BottleneckKind.input) {
        // Free crew is assigned first and a crew shortage is shed
        // ([shedCrew]); an idle building waits for crew to free up.
        continue;
      }
      final key = '${neck.bodyId}:${neck.resourceId}';
      if (tried.contains(key)) continue;
      final fix = _fixInput(s.body(neck.bodyId!), neck.resourceId!);
      if (fix != null) {
        tried.add(key);
        return fix;
      }
    }
    return null;
  }

  /// More storage on [body], whose store of something is full and wasting
  /// output: a warehouse if there is a free slot and it can be paid, else
  /// a capacity level on the warehouse there with the cheapest one.
  Command? _addStorage(BodyState body) {
    final depot = c.buildings.values
        .where((d) => d.kind == BuildingKind.warehouse)
        .firstOrNull;
    if (depot == null) return null;
    if (hasFreeSlot(body) && canPay(body, depot.buildCost)) {
      return BuildCommand(factionId, body.id, depot.id);
    }
    (Command, BigNum)? best;
    for (final b in body.buildings) {
      if (def(b).kind != BuildingKind.warehouse ||
          !def(b).upgrades.containsKey(UpgradeTrack.capacity)) {
        continue;
      }
      final cost = upgradeCost(c, b, UpgradeTrack.capacity);
      if (!canPay(body, cost)) continue;
      if (best == null || cost['credits']! < best.$2) {
        best = (
          UpgradeCommand(factionId, b.id, UpgradeTrack.capacity),
          cost['credits']!,
        );
      }
    }
    return best?.$1;
  }

  Command? _fixInput(BodyState body, String resourceId) {
    final local = _boostSupply(body, resourceId);
    if (local != null) return local;

    // Everything on [body] that uses it, so one route serves them all.
    var demand = const BigNum.zero();
    for (final b in body.buildings) {
      if (b.crew == 0) continue;
      final need = flowOf(body, b).inputs[resourceId];
      if (need != null) demand = demand + need;
    }
    final existing = s.routes
        .where((rt) => rt.toBodyId == body.id && rt.resourceId == resourceId)
        .firstOrNull;
    if (existing == null) return _route(resourceId, body, demand);
    final carries = existing.ratePerSecond.min(routeCapacity(c, existing));
    final from = s.body(existing.fromBodyId);
    if (carries >= demand.mulDouble(_routeSlack)) {
      // The route is big enough; its source is what runs short.
      return _boostSupply(from, resourceId);
    }
    // Too small for today's demand: close it so a later decision opens a
    // bigger one, its ships back at the source.
    final canGrow =
        existing.ratePerSecond < demand.mulDouble(_routeSlack) || hasShip(from);
    return canGrow ? RemoveRouteCommand(factionId, existing.id) : null;
  }

  /// More [resourceId] made on [body]: the cheapest affordable upgrade of a
  /// staffed building there that makes it (speed if it runs freely,
  /// efficiency if it is itself short of inputs), else a new supplier.
  Command? _boostSupply(BodyState body, String resourceId) {
    (Command, BigNum)? upgrade;
    for (final b in body.buildings) {
      if (b.crew == 0 || !makes(b, resourceId)) continue;
      final t = b.lastLimitReason == null
          ? UpgradeTrack.speed
          : UpgradeTrack.efficiency;
      if (!def(b).upgrades.containsKey(t)) continue;
      final cost = upgradeCost(c, b, t);
      if (!canPay(body, cost)) continue;
      if (upgrade == null || cost['credits']! < upgrade.$2) {
        upgrade = (UpgradeCommand(factionId, b.id, t), cost['credits']!);
      }
    }
    return upgrade?.$1 ?? _buildSupplier(body, resourceId);
  }

  /// The cheapest affordable building on [body] that makes [resourceId]:
  /// an extractor on its deposit, or a factory whose inputs [body] has a
  /// surplus of. Null without a free slot or free crew to staff it.
  Command? _buildSupplier(BodyState body, String resourceId) {
    if (!hasFreeSlot(body) || freeCrew < 1) return null;
    (Command, BigNum)? best;
    for (final d in c.buildings.values) {
      final String? deposit;
      if (d.kind == BuildingKind.extractor) {
        if (!d.extracts.contains(resourceId) ||
            !body.deposits.any((x) => x.resourceId == resourceId)) {
          continue;
        }
        deposit = resourceId;
      } else if (d.kind == BuildingKind.factory &&
          d.outputs.containsKey(resourceId) &&
          d.inputs.keys.every((i) => surplus(body, i) > 0)) {
        deposit = null;
      } else {
        continue;
      }
      if (!canPay(body, d.buildCost)) continue;
      final credits = d.buildCost['credits'] ?? const BigNum.zero();
      if (best == null || credits < best.$2) {
        best = (
          BuildCommand(factionId, body.id, d.id, depositResourceId: deposit),
          credits,
        );
      }
    }
    return best?.$1;
  }

  /// A route bringing up to [rate] per second of [resourceId] to [to] from
  /// [routeSource], with enough cargo ships for the rate if it has them.
  Command? _route(String resourceId, BodyState to, BigNum rate) {
    final from = routeSource(resourceId, to);
    if (from == null) return null;
    final ships = stock(from, r.cargoShipResource).toDouble().floor();
    final want = (rate.toDouble() / r.shipCapacityPerSecond).ceil();
    return CreateRouteCommand(
      factionId,
      from.id,
      to.id,
      resourceId,
      rate,
      math.max(1, math.min(ships, want)),
    );
  }

  /// The first other owned body in [to]'s system with a surplus or stock of
  /// [resourceId] and a cargo ship, or null if there is none or a route
  /// already brings it.
  BodyState? routeSource(String resourceId, BodyState to) {
    if (routeInto(to, resourceId)) return null;
    for (final from in owned) {
      if (from.id == to.id || from.systemId != to.systemId) continue;
      if (!hasShip(from)) continue;
      if (surplus(from, resourceId) > 0 ||
          stock(from, resourceId) > const BigNum.zero()) {
        return from;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Balanced bot: claims.

  /// Claims the best unowned body when the faction can pay, kits taken from
  /// the first owned body that holds enough.
  Command? claim() {
    final cost = claimCost(s, c, factionId);
    final source = owned.where((b) => canPay(b, cost)).firstOrNull;
    final target = _claimTarget();
    if (source == null || target == null) return null;
    return ClaimBodyCommand(factionId, target.id, source.id);
  }

  /// The unowned body adding the most deposit types the faction lacks, then
  /// the most richness in them; body order breaks a tie.
  BodyState? _claimTarget() {
    final have = {
      for (final b in owned)
        for (final d in b.deposits) d.resourceId,
    };
    BodyState? best;
    var bestCount = -1;
    var bestRichness = 0.0;
    for (final b in s.bodies) {
      if (b.ownerId != null) continue;
      final fresh = b.deposits.where((d) => !have.contains(d.resourceId));
      final richness = fresh.fold(0.0, (sum, d) => sum + d.richness);
      if (fresh.length > bestCount ||
          (fresh.length == bestCount && richness > bestRichness)) {
        best = b;
        bestCount = fresh.length;
        bestRichness = richness;
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // Balanced bot: goals.

  /// The next step toward the first unreached milestone that has one, else
  /// toward more housing when crew has run out.
  ///
  /// Saving is only worth it once at least [_saveFrom] of the sum is in
  /// hand; a goal further off than that lets the next one act, so the bot
  /// keeps growing in the meantime.
  _Step pursueGoals() {
    _Step? worth(_Step step) => switch (step) {
      _Do() => step,
      _Save(:final credits)
          when faction.credits >= credits.mulDouble(_saveFrom) =>
        step,
      _ => null,
    };
    for (final m in c.milestones) {
      if (faction.reachedMilestones.contains(m.id) || _met(m.condition)) {
        continue;
      }
      final step = switch (m.condition) {
        StockCondition(:final resourceId) => ensureMade(resourceId),
        BodiesOwnedCondition() => _ensureClaimable(),
        BuildingCountCondition(:final defId) => _ensureBuilt(defId),
        CreditsCondition(:final amount) => _Save(amount),
      };
      if (worth(step) case final step?) return step;
    }
    if (freeCrew < 1) {
      if (worth(_ensureHousing()) case final step?) return step;
    }
    return const _Waiting();
  }

  /// Whether [cond] holds in this (possibly planned-ahead) state, which the
  /// engine has not yet checked for milestones.
  bool _met(MilestoneCondition cond) => switch (cond) {
    StockCondition(:final resourceId, :final amount) =>
      owned.fold(const BigNum.zero(), (t, b) => t + stock(b, resourceId)) >=
          amount,
    CreditsCondition(:final amount) => faction.credits >= amount,
    BodiesOwnedCondition(:final count) => owned.length >= count,
    BuildingCountCondition(:final defId, :final count) =>
      buildings.where((x) => x.$2.defId == defId).length >= count,
  };

  /// Gets the next claim within reach: makes its outpost kits, then saves
  /// its credits.
  _Step _ensureClaimable() {
    if (_claimTarget() == null) return const _Waiting();
    final cost = claimCost(s, c, factionId);
    for (final MapEntry(key: id, value: need) in cost.entries) {
      if (id == 'credits') continue;
      if (owned.any((b) => stock(b, id) >= need)) continue;
      final step = ensureMade(id);
      // Kits are on their way: save for the credits meanwhile.
      if (step is _Waiting && made(id)) return _Save(cost['credits']!);
      return step;
    }
    return _Save(cost['credits']!);
  }

  /// Builds one more [defId] on the first owned body with a free slot,
  /// unless one is already waiting for crew.
  _Step _ensureBuilt(String defId) {
    final d = c.buildings[defId]!;
    if (buildings.any((x) => x.$2.defId == defId && x.$2.crew == 0)) {
      return const _Waiting();
    }
    for (final body in owned) {
      if (!hasFreeSlot(body)) continue;
      if (buildDeposits(d, body) case [final dep, ...]) {
        return _buildAt(d, body, dep);
      }
    }
    return const _Stuck();
  }

  /// The next step toward a staffed building that makes [resourceId]:
  /// staffing an idle one, building an extractor on a deposit, or building
  /// a factory once something makes each of its inputs (those first).
  _Step ensureMade(String resourceId, [Set<String> visiting = const {}]) {
    if (visiting.length > _maxChainDepth || visiting.contains(resourceId)) {
      return const _Stuck();
    }
    if (made(resourceId)) return const _Waiting();
    for (final (_, b) in buildings) {
      if (b.crew == 0 && makes(b, resourceId)) return _staff(b);
    }
    for (final d in c.buildings.values) {
      if (d.kind != BuildingKind.extractor ||
          !d.extracts.contains(resourceId)) {
        continue;
      }
      for (final body in owned) {
        if (hasFreeSlot(body) &&
            body.deposits.any((x) => x.resourceId == resourceId)) {
          return _buildAt(d, body, resourceId);
        }
      }
    }
    final deeper = {...visiting, resourceId};
    for (final d in c.buildings.values) {
      if (d.kind != BuildingKind.factory ||
          !d.outputs.containsKey(resourceId)) {
        continue;
      }
      final step = _ensureInputs(d.inputs.keys, deeper);
      if (_acts(step)) return step;
      if (step is _Stuck) continue;
      final body = _site(d.inputs.keys);
      if (body != null) return _buildAt(d, body, null);
      // Every input is made, but no body can get them all: ships are short.
      final ships = _shipsFor(d.inputs.keys, deeper);
      if (_acts(ships)) return ships;
    }
    return const _Stuck();
  }

  /// [_Waiting] once something makes every one of [inputs], else the first
  /// step toward that, or [_Stuck].
  _Step _ensureInputs(Iterable<String> inputs, Set<String> visiting) {
    for (final i in inputs) {
      if (made(i)) continue;
      final step = ensureMade(i, visiting);
      return _acts(step) ? step : const _Stuck();
    }
    return const _Waiting();
  }

  /// The owned body with a free slot that can get every one of [inputs],
  /// made there or shipped in, with the most made there; body order breaks
  /// a tie. Goods ship only from bodies holding a cargo ship.
  BodyState? _site(Iterable<String> inputs) {
    BodyState? best;
    var bestLocal = -1;
    for (final body in owned) {
      if (!hasFreeSlot(body)) continue;
      var local = 0;
      var reachable = true;
      for (final i in inputs) {
        if (madeAt(body, i)) {
          local++;
        } else if (!routeInto(body, i) &&
            !owned.any((o) => o != body && hasShip(o) && madeAt(o, i))) {
          reachable = false;
        }
      }
      if (reachable && local > bestLocal) {
        best = body;
        bestLocal = local;
      }
    }
    return best;
  }

  /// The next step toward cargo ships on a body that makes one of
  /// [inputs] and has none: making ships, then sending [_shipsSent] there
  /// from a body holding more.
  _Step _shipsFor(Iterable<String> inputs, Set<String> visiting) {
    final ship = r.cargoShipResource;
    final making = ensureMade(ship, visiting);
    if (_acts(making) || making is _Stuck) return making;
    for (final to in owned) {
      if (hasShip(to) || routeInto(to, ship)) continue;
      if (!inputs.any((i) => madeAt(to, i))) continue;
      final from = owned
          .where(
            (o) =>
                o != to &&
                o.systemId == to.systemId &&
                stock(o, ship) >= BigNum.from(_shipsSent + 1),
          )
          .firstOrNull;
      if (from == null) return const _Waiting();
      return _Do(
        CreateRouteCommand(
          factionId,
          from.id,
          to.id,
          ship,
          BigNum.from(_trickleRate),
          1,
        ),
      );
    }
    return const _Waiting();
  }

  /// Closes a route moving cargo ships once its destination holds
  /// [_shipsSent] of them.
  Command? closeShipTransfers() {
    for (final rt in s.routes) {
      if (rt.ownerId != factionId || rt.resourceId != r.cargoShipResource) {
        continue;
      }
      if (stock(s.body(rt.toBodyId), r.cargoShipResource) >=
          BigNum.from(_shipsSent)) {
        return RemoveRouteCommand(factionId, rt.id);
      }
    }
    return null;
  }

  /// Builds [d] on [body], or saves for it; staffing follows on a later
  /// step so that crew moved to it is not handed straight back.
  _Step _buildAt(BuildingDef d, BodyState body, String? deposit) {
    if (freeCrew < 1 && _crewDonor(null) == null) return const _Stuck();
    if (!canPay(body, d.buildCost)) {
      final credits = d.buildCost['credits'] ?? const BigNum.zero();
      final short = d.buildCost.entries.any(
        (x) => x.key != 'credits' && stock(body, x.key) < x.value,
      );
      return short ? const _Stuck() : _Save(credits);
    }
    return _Do(
      BuildCommand(factionId, body.id, d.id, depositResourceId: deposit),
    );
  }

  /// Staffs idle building [b]: free crew is assigned by [assignFreeCrew],
  /// so this takes one crew from the most-crewed other building with more
  /// than one, the lowest-value first on a tie.
  _Step _staff(BuildingState b) {
    if (freeCrew >= 1) return const _Waiting();
    final donor = _crewDonor(b);
    if (donor == null) return const _Stuck();
    return _Do(AssignCrewCommand(factionId, donor.id, donor.crew - 1));
  }

  /// The building other than [except] that can best spare one crew: the
  /// most crewed with at least [minCrew], the lowest value per crew on a
  /// tie; never one that [keepsCrewAlive].
  BuildingState? _crewDonor(BuildingState? except, {int minCrew = 2}) {
    (BuildingState, double)? best;
    for (final (body, x) in buildings) {
      if (x == except || x.crew < minCrew || keepsCrewAlive(x)) continue;
      final v = value(flowOf(body, x)) / x.crew;
      if (best == null ||
          x.crew > best.$1.crew ||
          (x.crew == best.$1.crew && v < best.$2)) {
        best = (x, v);
      }
    }
    return best?.$1;
  }

  /// The next step toward a running habitat that has its life support:
  /// staffing an idle one that needs crew, making its build resources and inputs, shipping
  /// its build resources to the chosen body, then building it.
  _Step _ensureHousing() {
    final hab = c.buildings.values
        .where((d) => d.kind == BuildingKind.habitat)
        .firstOrNull;
    if (hab == null) return const _Stuck();
    for (final (_, b) in buildings) {
      if (b.crew == 0 &&
          def(b).kind == BuildingKind.habitat &&
          !runsWithoutCrew(def(b))) {
        return _staff(b);
      }
    }
    // Feed the habitats there are before adding more.
    if (crewEff < 1 ||
        buildings.any(
          (x) =>
              def(x.$2).kind == BuildingKind.habitat &&
              x.$2.lastRunFraction < 1,
        )) {
      return const _Waiting();
    }
    // A capacity level on a fed habitat adds housing more cheaply than a
    // new habitat, until its price passes a new one's credits.
    final more = _habitatCapacity();
    final newCredits = hab.buildCost['credits'] ?? const BigNum.zero();
    if (more != null && more.$2 <= newCredits) {
      return canPay(more.$3, {'credits': more.$2})
          ? _Do(more.$1)
          : _Save(more.$2);
    }
    final parts = {
      for (final MapEntry(key: id, value: n) in hab.buildCost.entries)
        if (id != 'credits') id: n,
    };
    for (final id in parts.keys) {
      final step = ensureMade(id);
      if (_acts(step)) return step;
      if (step is _Stuck) return step;
    }
    final inputs = _ensureInputs(hab.inputs.keys, const {});
    if (inputs is! _Waiting) return inputs;
    // Only where life support is made on the spot: a habitat fed by routes
    // starves whenever its source's own buildings use the supply first,
    // and every crewed building slows with it.
    final body = owned
        .where(
          (b) => hasFreeSlot(b) && hab.inputs.keys.every((i) => madeAt(b, i)),
        )
        .firstOrNull;
    if (body == null) {
      // No room for a new one: grow the ones there are.
      if (more == null) return const _Stuck();
      return canPay(more.$3, {'credits': more.$2})
          ? _Do(more.$1)
          : _Save(more.$2);
    }
    for (final MapEntry(key: id, value: n) in parts.entries) {
      if (stock(body, id) >= n) continue;
      if (routeInto(body, id)) return const _Waiting();
      final from = owned
          .where((o) => o != body && hasShip(o) && stock(o, id) >= n)
          .firstOrNull;
      if (from == null) return const _Waiting();
      return _Do(
        CreateRouteCommand(
          factionId,
          from.id,
          body.id,
          id,
          BigNum.from(_trickleRate),
          1,
        ),
      );
    }
    return _buildAt(hab, body, null);
  }

  /// The cheapest capacity level on a habitat that runs at full rate, its
  /// credit cost and its body; null if there is none.
  (Command, BigNum, BodyState)? _habitatCapacity() {
    (Command, BigNum, BodyState)? best;
    for (final (body, b) in buildings) {
      final d = def(b);
      if (d.kind != BuildingKind.habitat ||
          b.lastRunFraction < 1 ||
          !d.upgrades.containsKey(UpgradeTrack.capacity)) {
        continue;
      }
      final credits = upgradeCost(c, b, UpgradeTrack.capacity)['credits']!;
      if (best == null || credits < best.$2) {
        best = (
          UpgradeCommand(factionId, b.id, UpgradeTrack.capacity),
          credits,
          body,
        );
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // Balanced bot: growth.

  /// Share in `[0, 1]` of extra per-second input demand [inputs] on [body]
  /// that spare supply meets: local surplus, plus another body's when a
  /// route could bring it.
  double supplied(BodyState body, Map<String, BigNum> inputs) {
    var share = 1.0;
    for (final MapEntry(key: id, value: need) in inputs.entries) {
      final n = need.toDouble();
      if (n <= 0) continue;
      var spare = math.max(0.0, surplus(body, id));
      if (routeInto(body, id)) {
        spare = math.max(spare, n);
      } else if (routeSource(id, body) case final from?) {
        spare += math.max(0.0, surplus(from, id));
      }
      share = math.min(share, spare / n);
    }
    return share;
  }

  /// Credits per second that [extra] flow on [body] adds: its outputs at
  /// market price less the inputs used, both scaled by the share of the
  /// extra input demand that spare supply meets.
  ///
  /// Every output is worth its price because [autoSell] sells all surplus
  /// and the engine auto-sells before it clamps stock to the storage cap,
  /// so nothing a body makes is lost to the cap.
  double gain(BodyState body, BuildingFlow extra) {
    final share = supplied(body, extra.inputs);
    return value(extra) * share;
  }

  /// The purchase adding the most credits per second per credit that the
  /// faction can pay while keeping [reserve] credits: speed, efficiency and
  /// capacity upgrades (for their extra crew slot), new extractors and
  /// factories, and an extra build slot on a full body (valued as the best
  /// building it would take, priced with it). See [gain]. Storage is
  /// bought only when a store fills up ([fixBottleneck]).
  Command? grow({required BigNum reserve}) {
    final budget = faction.credits - reserve;
    if (budget <= const BigNum.zero()) return null;
    Command? best;
    var bestRoi = 0.0;
    void consider(
      Command cmd,
      BodyState payer,
      Map<String, BigNum> cost,
      double gain,
    ) {
      final credits = cost['credits'] ?? const BigNum.zero();
      if (gain <= 0 || credits > budget || !canPay(payer, cost)) return;
      final roi = gain / math.max(1.0, credits.toDouble());
      if (roi > bestRoi) {
        best = cmd;
        bestRoi = roi;
      }
    }

    for (final body in owned) {
      for (final b in body.buildings) {
        final d = def(b);
        final ups = d.upgrades;
        if (ups.containsKey(UpgradeTrack.capacity) &&
            d.kind != BuildingKind.habitat &&
            freeCrew >= 1 &&
            b.crew > 0 &&
            b.lastLimitReason == null &&
            b.crew >= maxCrew(r, d, b)) {
          // One more crew slot, worth it when crew is free and this
          // building runs freely with every slot filled.
          final g = gain(body, _scaledFlow(flowOf(body, b), 1 / b.crew));
          consider(
            UpgradeCommand(factionId, b.id, UpgradeTrack.capacity),
            body,
            upgradeCost(c, b, UpgradeTrack.capacity),
            g,
          );
        }
        if (b.crew == 0 || b.lastLimitReason != null) continue;
        if (d.kind == BuildingKind.habitat) continue;
        final flow = flowOf(body, b);
        if (ups.containsKey(UpgradeTrack.speed)) {
          final level = b.levels[UpgradeTrack.speed]!;
          final more =
              speedMultiplier(r, level + 1) / speedMultiplier(r, level) - 1;
          consider(
            UpgradeCommand(factionId, b.id, UpgradeTrack.speed),
            body,
            upgradeCost(c, b, UpgradeTrack.speed),
            gain(body, _scaledFlow(flow, more)),
          );
        }
        if (ups.containsKey(UpgradeTrack.efficiency) &&
            flow.inputs.isNotEmpty) {
          final level = b.levels[UpgradeTrack.efficiency]!;
          final saved =
              1 -
              efficiencyMultiplier(r, level + 1) /
                  efficiencyMultiplier(r, level);
          consider(
            UpgradeCommand(factionId, b.id, UpgradeTrack.efficiency),
            body,
            upgradeCost(c, b, UpgradeTrack.efficiency),
            _worth(flow.inputs) * saved,
          );
        }
      }

      if (!hasFreeSlot(body)) {
        // An extra slot is worth what the best new building there would
        // add, for the slot and the building together.
        if (freeCrew < 1) continue;
        final slot = slotCost(c, body)['credits']!;
        for (final d in c.buildings.values) {
          if (d.kind != BuildingKind.extractor &&
              d.kind != BuildingKind.factory) {
            continue;
          }
          for (final dep in buildDeposits(d, body)) {
            consider(ExpandSlotsCommand(factionId, body.id), body, {
              ...d.buildCost,
              'credits': slot + (d.buildCost['credits'] ?? const BigNum.zero()),
            }, gain(body, probe(d, body, dep)));
          }
        }
        continue;
      }
      for (final d in c.buildings.values) {
        switch (d.kind) {
          case BuildingKind.warehouse:
            // Auto-sell keeps stock under the cap; storage earns nothing.
            continue;
          case BuildingKind.extractor || BuildingKind.factory:
            if (freeCrew < 1) continue;
            for (final dep in buildDeposits(d, body)) {
              consider(
                BuildCommand(factionId, body.id, d.id, depositResourceId: dep),
                body,
                d.buildCost,
                gain(body, probe(d, body, dep)),
              );
            }
          case BuildingKind.habitat:
            // Housing is a goal; see [pursueGoals].
            continue;
        }
      }
    }
    return best;
  }
}

BuildingFlow _scaledFlow(BuildingFlow f, double by) =>
    (inputs: _scaled(f.inputs, by), outputs: _scaled(f.outputs, by));

Map<String, BigNum> _scaled(Map<String, BigNum> m, double f) => {
  for (final MapEntry(key: id, value: v) in m.entries) id: v.mulDouble(f),
};
