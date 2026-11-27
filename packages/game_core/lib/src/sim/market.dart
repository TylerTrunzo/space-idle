import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'crew.dart';
import 'megaprojects.dart';
import 'production.dart';
import 'step_cache.dart';

/// What a sale moved and earned.
final class SaleResult {
  /// Creates a sale result.
  const SaleResult({required this.sold, required this.revenue});

  /// Units taken from stock.
  final BigNum sold;

  /// Credits paid to the seller.
  final BigNum revenue;
}

/// Lowest saturation [resourceId]'s market falls to: its own
/// [ResourceDef.marketFloor], else the rules' [RulesDef.marketFloor].
double marketFloorOf(Content c, String resourceId) =>
    c.resources[resourceId]!.marketFloor ?? c.rules.marketFloor;

/// Market depth of [resourceId] for sales by [factionId]: its
/// [ResourceDef.marketDepth] times the faction's
/// [EmpireBonuses.marketDepthMultiplierFor] the resource's tier.
double marketDepthFor(
  GameState s,
  Content c,
  String factionId,
  String resourceId,
) {
  final res = c.resources[resourceId]!;
  return res.marketDepth *
      bonusesFor(s, c, factionId).marketDepthMultiplierFor(res.tier);
}

/// Current price per unit of [resourceId]: base price × saturation. The
/// plain market price, the same for every faction; what a faction's sales
/// earn, and what its contracts value goods at, is [salePrice].
BigNum price(GameState s, Content c, String resourceId) => c
    .resources[resourceId]!
    .basePrice
    .mulDouble(s.market.saturation[resourceId] ?? 1);

/// Factor on the credits [factionId]'s market sales of [resourceId] earn:
/// its [EmpireBonuses.salePriceMultiplierFor] the resource's tier; 1 for
/// none.
double saleMultiplierFor(
  GameState s,
  Content c,
  String factionId,
  String resourceId,
) => bonusesFor(
  s,
  c,
  factionId,
).salePriceMultiplierFor(c.resources[resourceId]!.tier);

/// What a unit of [resourceId] earns [factionId] on the market now: the
/// [price] times its [saleMultiplierFor]. Every reading that values the
/// faction's sales (income, losses, waste, diversions) uses it, so they
/// agree with what [sell] and auto-sell pay.
BigNum salePrice(GameState s, Content c, String factionId, String resourceId) =>
    price(
      s,
      c,
      resourceId,
    ).mulDouble(saleMultiplierFor(s, c, factionId, resourceId));

/// Sells up to [amount] of [resourceId] from [bodyId]'s stock for
/// [factionId], all at once.
///
/// Each unit sold cuts the saturation by `1 / depth` of itself, down to
/// the floor ([marketFloorOf]), and earns the price at the saturation it
/// sold at; `depth` is the seller's [marketDepthFor].
/// So `n` units take the saturation from `s0` to `s0 × e^(−n / depth)` and
/// earn `basePrice × depth × (s0 − s1)`; every unit past the floor
/// earns `basePrice × marketFloor`. One large sale earns what the same
/// units sold in many small lots would. The credits are then multiplied by
/// the seller's [saleMultiplierFor] the resource.
///
/// Sells only what the body holds. Does no ownership checks; callers
/// validate first (see `SellCommand`). The ids must exist.
SaleResult sell(
  GameState s,
  Content c,
  String factionId,
  String bodyId,
  String resourceId,
  BigNum amount,
) {
  final body = s.body(bodyId);
  final held = body.stock[resourceId] ?? const BigNum.zero();
  final sold = amount.min(held).max(const BigNum.zero());
  if (sold.isZero) {
    return const SaleResult(sold: BigNum.zero(), revenue: BigNum.zero());
  }
  final res = c.resources[resourceId]!;
  final floor = marketFloorOf(c, resourceId);
  final s0 = s.market.saturation[resourceId] ?? 1;
  final depth = marketDepthFor(s, c, factionId, resourceId);
  // Units that take the saturation from s0 down to the floor.
  final toFloor = s0 <= floor ? 0.0 : depth * math.log(s0 / floor);
  final BigNum plain;
  final double s1;
  if (sold.toDouble() <= toFloor) {
    s1 = s0 * math.exp(-sold.toDouble() / depth);
    plain = res.basePrice.mulDouble(depth * (s0 - s1));
  } else {
    s1 = math.min(s0, floor);
    plain =
        res.basePrice.mulDouble(depth * (s0 - s1)) +
        (sold - BigNum.from(toFloor)) * res.basePrice.mulDouble(floor);
  }
  final revenue = plain.mulDouble(
    saleMultiplierFor(s, c, factionId, resourceId),
  );
  _earn(s.faction(factionId), resourceId, revenue);
  body.take(resourceId, sold);
  s.market.saturation[resourceId] = math.max(floor, s1);
  return SaleResult(sold: sold, revenue: revenue);
}

/// Runs [dt] game seconds of the market: saturation recovery and every
/// faction's auto-sell rules.
///
/// A rule sells what the body holds beyond `keepAtLeast`, plus what the
/// body's own buildings would use of the resource at full supply
/// ([fullRateFlow]) over the keep horizon, `max(dt,
/// shipmentMergeSeconds)` ([RulesDef.shipmentMergeSeconds]), plus what
/// its faction's open contracts still need of it when this body holds
/// them back, all kept no higher than the body's [storageCap] unless
/// `keepAtLeast` alone is ([autoSellKeep]); only while its faction owns
/// the body. A contract's need, less what the faction's bodies with no
/// rule on the resource hold, is held on the faction's bodies with a rule
/// on the resource, the one holding the most of it at the step's start
/// first (the first in rule order on a tie): first the stock each holds,
/// then what is still owed as the room each has below its cap, none more
/// than it can store. A rule sees the stock less what earlier rules on
/// the same body and resource queued, so duplicate rules (which saves
/// reject) never sell more than is held. Keeping that demand back means
/// auto-selling an input never starves the factories that use it, however
/// long the step; and since a route's sends land in lots up to
/// `shipmentMergeSeconds` apart, short steps keep enough of a lot to last
/// until the next one lands.
///
/// The engine runs this after `sendCargo`, so what a route sends this
/// step has already left the source's stock: a rule there with
/// `keepAtLeast` 0 sells only what the route leaves.
///
/// Saturation recovers toward 1: its gap to full price shrinks by a
/// factor e every `marketRecoverySeconds`. What is auto-sold of a resource
/// counts as sold at a steady rate over the step while it recovers, each
/// unit cutting the saturation by `1 / depth` of itself, `depth` being its
/// seller's [marketDepthFor], as in [sell]; the units earn the base price
/// times the saturation's average over the step ([_sellOverStep]). So a
/// long step earns what many short ones do, and steady selling settles at
/// `1 / (1 + rate × marketRecoverySeconds / depth)` (or the floor):
/// selling more always earns more, ever less per unit. Every seller of a
/// resource gets the same price per unit. Factions and their rules run in
/// list order; resources are settled in sorted-id order so the result does
/// not depend on map insertion order.
///
/// [limits], when given, caps what auto-sell may sell this step: body id
/// to resource id to units, a missing entry meaning nothing. The flow
/// report uses it to sell only what a step makes (see `buildFlowReport`).
/// [cache], when given, is the step's [StepCache]; one is made otherwise.
void stepMarket(
  GameState s,
  Content c,
  double dt, {
  Map<String, Map<String, BigNum>>? limits,
  StepCache? cache,
}) {
  final k = cache ?? StepCache(s, c);
  final horizon = math.max(dt, c.rules.shipmentMergeSeconds);
  final sales = <String, List<(FactionState, BodyState, BigNum)>>{};
  // Body id to resource id to what earlier rules already queued for sale,
  // so a second rule on the same stock never sells it twice.
  final queued = <String, Map<String, BigNum>>{};
  for (final f in s.factions) {
    if (f.autoSell.isEmpty) continue;
    final holds = _contractHolds(s, k, f);
    final fed = _megaprojectHolds(s, c, f);
    for (final rule in f.autoSell) {
      final body = s.body(rule.bodyId);
      if (body.ownerId != f.id) continue;
      final taken = queued[body.id] ??= {};
      final held =
          (body.stock[rule.resourceId] ?? _zero) -
          (taken[rule.resourceId] ?? _zero);
      // Nothing to sell whatever the keep: skip working it out.
      if (held <= rule.keepAtLeast) continue;
      final keep = _keep(
        k.cap(body),
        rule.keepAtLeast,
        k.use(body, horizon),
        rule.resourceId,
        holds[body.id]?[rule.resourceId] ?? _zero,
        fed[rule.resourceId] ?? _zero,
      ).keeps;
      var excess = held - keep;
      if (limits != null) {
        excess = excess.min(
          (limits[body.id]?[rule.resourceId] ?? _zero) -
              (taken[rule.resourceId] ?? _zero),
        );
      }
      if (excess > _zero) {
        (sales[rule.resourceId] ??= []).add((f, body, excess));
        taken[rule.resourceId] = (taken[rule.resourceId] ?? _zero) + excess;
      }
    }
  }
  final sat = s.market.saturation;
  for (final id in {...sat.keys, ...sales.keys}.toList()..sort()) {
    final lots = sales[id];
    if (lots == null) {
      sat[id] =
          1 - (1 - sat[id]!) * math.exp(-dt / c.rules.marketRecoverySeconds);
      continue;
    }
    // Share of the saturation the step's sales cut a second: each seller's
    // units a second over its market depth, summed.
    final cut = lots.fold(
      0.0,
      (t, lot) =>
          t + lot.$3.toDouble() / dt / marketDepthFor(s, c, lot.$1.id, id),
    );
    final (:priceShare, :end) = _sellOverStep(
      c,
      c.resources[id]!,
      sat[id] ?? 1,
      cut,
      dt,
    );
    final unitPrice = c.resources[id]!.basePrice.mulDouble(priceShare);
    for (final (f, body, amount) in lots) {
      _earn(
        f,
        id,
        (amount * unitPrice).mulDouble(saleMultiplierFor(s, c, f.id, id)),
      );
      body.take(id, amount);
    }
    sat[id] = end;
  }
}

/// What an auto-sell rule holds back from sale on its body, and why.
typedef AutoSellKeep = ({
  BigNum keepAtLeast,
  BigNum localUse,
  BigNum contractHold,
  BigNum megaprojectHold,
  BigNum keeps,
  bool cappedAtStorage,
});

/// What [rule] keeps on its body in a market step of [dt] seconds (the
/// engine's ticks are 60 s by default), as [stepMarket] works it out:
/// `keepAtLeast`, plus the body's own buildings' use of the resource at
/// full supply over `max(dt, shipmentMergeSeconds)` ([localUse]), plus
/// what the owner's open contracts still need of it when this body holds
/// it back for them ([contractHold]: the need less what bodies with no
/// rule on it hold, on the bodies with a rule on it, the fullest first:
/// their stock, then their room, each at most its storage cap), plus what
/// the megaprojects its owner feeds goods to on their own still need of it
/// ([megaprojectHold]; see `stepMegaprojectAuto`, which takes it once a
/// game minute), the sum
/// ([keeps]) no higher than the body's storage cap unless `keepAtLeast`
/// alone is ([cappedAtStorage] when the cap cut it).
///
/// The rule sells only what the body holds above [keeps]. The buildings
/// run at the crew efficiency of the body's owner (full for an unowned
/// body, whose rules sell nothing).
AutoSellKeep autoSellKeep(
  GameState s,
  Content c,
  AutoSellRule rule,
  double dt,
) {
  final body = s.body(rule.bodyId);
  final owner = body.ownerId;
  final used = _stepDemand(
    c,
    body,
    math.max(dt, c.rules.shipmentMergeSeconds),
    owner == null ? 1 : crewEfficiency(s, c, owner),
    bonusesFor(s, c, owner),
  );
  final f = owner == null ? null : s.faction(owner);
  final hold = f == null
      ? _zero
      : _contractHolds(s, StepCache(s, c), f)[body.id]?[rule.resourceId] ??
            _zero;
  final fed = f == null
      ? _zero
      : _megaprojectHolds(s, c, f)[rule.resourceId] ?? _zero;
  return _keep(
    storageCap(s, c, body),
    rule.keepAtLeast,
    used,
    rule.resourceId,
    hold,
    fed,
  );
}

/// [autoSellKeep] for a rule keeping [keepAtLeast] of [resourceId] on a
/// body whose storage cap is [cap], given [used], what the body's
/// buildings use over the keep horizon, [hold],
/// what it holds back for contracts, and [fed], what it holds back for
/// megaprojects fed on their own.
AutoSellKeep _keep(
  BigNum cap,
  BigNum keepAtLeast,
  Map<String, BigNum> used,
  String resourceId,
  BigNum hold,
  BigNum fed,
) {
  final local = used[resourceId] ?? _zero;
  final wanted = keepAtLeast + local + hold + fed;
  // The demand kept never pushes stock past the cap, where the end of the
  // tick would waste it instead.
  final most = keepAtLeast.max(cap);
  return (
    keepAtLeast: keepAtLeast,
    localUse: local,
    contractHold: hold,
    megaprojectHold: fed,
    keeps: wanted.min(most),
    cappedAtStorage: wanted > most,
  );
}

/// Resource id to the units [f]'s open contracts still need of it, in
/// board order.
Map<String, BigNum> _contractNeeds(FactionState f) {
  final need = <String, BigNum>{};
  for (final k in f.contracts) {
    need[k.resourceId] = (need[k.resourceId] ?? _zero) + k.remaining;
  }
  return need;
}

/// Body id to resource id to what [f]'s auto-sell rules hold back there
/// for its open contracts: each resource's need ([_contractNeeds]) less
/// what [f]'s bodies with no rule on it hold (they sell none of it), on
/// the bodies [f] owns with a rule on it, the one that holds the most of
/// it now first (the first in rule order on a tie): first what each holds,
/// so none of what is still owed is sold, then what is still owed as the
/// room each has left below its storage cap, for what comes in. Each holds
/// at most its cap. So an order larger than one store, which contracts may
/// ask for (they are sized by all of a faction's stores together), can be
/// filled from several. Written in body order of the fullest first.
Map<String, Map<String, BigNum>> _contractHolds(
  GameState s,
  StepCache cache,
  FactionState f,
) {
  if (f.contracts.isEmpty) return const {};
  final need = _contractNeeds(f);
  // Resource id to the bodies with a rule on it, in rule order.
  final ruled = <String, List<BodyState>>{};
  for (final rule in f.autoSell) {
    if (!need.containsKey(rule.resourceId)) continue;
    final body = s.body(rule.bodyId);
    if (body.ownerId != f.id) continue;
    final bodies = ruled[rule.resourceId] ??= [];
    if (!bodies.contains(body)) bodies.add(body);
  }
  final holds = <String, Map<String, BigNum>>{};
  for (final MapEntry(key: id, value: bodies) in ruled.entries) {
    var left = need[id]!;
    for (final b in s.bodies) {
      if (b.ownerId == f.id && !bodies.contains(b)) {
        left = left - (b.stock[id] ?? _zero);
      }
    }
    // The fullest first; a stable sort keeps rule order on a tie.
    final fullest = List.of(bodies);
    _byStockDescending(fullest, id);
    final held = <BodyState, BigNum>{};
    // First the goods each body has, so none of what is owed sells; then
    // what is still owed as room each has left below its cap, for what
    // comes in.
    for (final room in [false, true]) {
      for (final body in fullest) {
        if (left <= _zero) break;
        final stock = (body.stock[id] ?? _zero).max(_zero);
        final cap = cache.cap(body);
        final most = room
            ? (cap.max(stock) - stock).min(cap - (held[body] ?? _zero))
            : stock.min(cap);
        final hold = left.min(most.max(_zero));
        if (hold <= _zero) continue;
        held[body] = (held[body] ?? _zero) + hold;
        left = left - hold;
      }
    }
    for (final body in fullest) {
      if (held[body] case final v?) (holds[body.id] ??= {})[id] = v;
    }
  }
  return holds;
}

/// Sorts [bodies] by what they hold of [id], most first, keeping their
/// order on a tie.
void _byStockDescending(List<BodyState> bodies, String id) {
  final indexed = [for (final (i, b) in bodies.indexed) (i, b)]
    ..sort((x, y) {
      final byStock = (y.$2.stock[id] ?? _zero).compareTo(
        x.$2.stock[id] ?? _zero,
      );
      return byStock != 0 ? byStock : x.$1.compareTo(y.$1);
    });
  for (final (i, (_, b)) in indexed.indexed) {
    bodies[i] = b;
  }
}

/// Resource id to what the megaprojects [f] feeds goods to on their own
/// now ([megaprojectGoodsFed]: one fed near ready only while its stage is
/// being fed, so until then its goods sell) still need of it, summed: each
/// one's [megaprojectRemaining] while it takes deliveries
/// ([megaprojectTakesDeliveries]), in content order. Auto-sell holds it
/// back on every body with a rule on it, so what is made between the
/// minutes auto-delivery runs is there for it, however short the steps.
Map<String, BigNum> _megaprojectHolds(GameState s, Content c, FactionState f) {
  if (f.megaprojectAuto.isEmpty) return const {};
  final hold = <String, BigNum>{};
  for (final m in c.megaprojects.values) {
    if (!megaprojectGoodsFed(s, f, m)) continue;
    if (!megaprojectTakesDeliveries(s, c, f.id, m)) continue;
    for (final MapEntry(key: id, value: v) in megaprojectRemaining(
      s,
      c,
      f.id,
      m,
    ).entries) {
      if (id != creditsKey) hold[id] = (hold[id] ?? _zero) + v;
    }
  }
  return hold;
}

/// What auto-delivery to megaprojects leaves of each good on each body
/// [f] owns, in a step of [dt] seconds ([autoDeliveryKeeps]).
final class DeliveryKeeps {
  DeliveryKeeps._(
    this._cache,
    this._horizon,
    this._holds,
    this._rest,
    this._keepAtLeast,
  );

  final StepCache _cache;
  final double _horizon;
  final Map<String, Map<String, BigNum>> _holds;
  final Map<String, Map<String, BigNum>> _rest;
  final Map<String, Map<String, BigNum>> _keepAtLeast;

  /// Whole units of [resourceId] [body] can hand over: what it holds above
  /// what it keeps ([keeps]), rounded down; zero or less when nothing.
  /// With [atLeast], it keeps no less than that either.
  ///
  /// A body holding less than one unit above its `keepAtLeast` and contract
  /// share has nothing to give, and its buildings' use is not worked out.
  BigNum spare(BodyState body, String resourceId, {BigNum? atLeast}) {
    final held = body.stock[resourceId] ?? _zero;
    // The keep is at least these, so with less than a unit above them
    // there is nothing to give.
    final atLeastKept = _keepAtLeast[body.id]?[resourceId] ?? _zero;
    final floor = (atLeastKept + _hold(body, resourceId)).min(
      atLeastKept.max(_cache.cap(body)),
    );
    if (held - floor < _one) return _zero;
    if (atLeast != null && held - atLeast < _one) return _zero;
    var keep = keeps(body, resourceId);
    if (atLeast != null) keep = keep.max(atLeast);
    return (held - keep).floor();
  }

  /// Units of [resourceId] auto-delivery leaves on [body]: what auto-sell
  /// keeps there ([autoSellKeep]), but never the megaproject hold.
  BigNum keeps(BodyState body, String resourceId) => _keep(
    _cache.cap(body),
    _keepAtLeast[body.id]?[resourceId] ?? _zero,
    _cache.use(body, _horizon),
    resourceId,
    _hold(body, resourceId),
    _zero,
  ).keeps;

  /// Whole units of [resourceId] on [body] that auto-delivery leaves there
  /// only for its auto-sell rule's `keepAtLeast`: what [spare] would give
  /// with that at zero, less what it gives; zero when the keep holds back
  /// nothing.
  BigNum heldByKeepAtLeast(BodyState body, String resourceId) {
    if ((_keepAtLeast[body.id]?[resourceId] ?? _zero) <= _zero) return _zero;
    final held = body.stock[resourceId] ?? _zero;
    final without = _keep(
      _cache.cap(body),
      _zero,
      _cache.use(body, _horizon),
      resourceId,
      _hold(body, resourceId),
      _zero,
    ).keeps;
    final free = (held - without).floor();
    if (free < _one) return _zero;
    final kept = free - spare(body, resourceId).max(_zero);
    return kept < _one ? _zero : kept;
  }

  BigNum _hold(BodyState body, String id) =>
      _holds[body.id]?[id] ?? _rest[body.id]?[id] ?? _zero;
}

/// What auto-delivery to megaprojects leaves of each of [resourceIds] on
/// each body [f] owns, in a step of [dt] seconds: what auto-sell keeps
/// there ([autoSellKeep]: the body's rule's `keepAtLeast`, 0 with no rule,
/// plus its buildings' local use, plus the contract hold, at most the
/// storage cap unless `keepAtLeast` alone is), but never the megaproject
/// hold. With several rules on one body and good, the one keeping least
/// counts, as auto-sell sells down to it ([stepMarket]). Of each open
/// contract need, what the holding body does not keep stays on the
/// faction's other bodies, in body order, as much as each holds, so
/// deliveries never take what contracts still need.
///
/// Worked out as [cache] holds the state; each body's use only when it is
/// asked for and holds enough to give.
DeliveryKeeps autoDeliveryKeeps(
  GameState s,
  StepCache cache,
  FactionState f,
  List<String> resourceIds,
  double dt,
) {
  final owned = [
    for (final b in s.bodies)
      if (b.ownerId == f.id) b,
  ];
  final holds = _contractHolds(s, cache, f);
  final need = _contractNeeds(f);
  // The rest of each contract need, on the bodies that do not hold it.
  final rest = <String, Map<String, BigNum>>{};
  for (final id in resourceIds) {
    var left = need[id] ?? _zero;
    if (left <= _zero) continue;
    for (final b in owned) {
      left = left - (holds[b.id]?[id] ?? _zero);
    }
    for (final b in owned) {
      if (left <= _zero) break;
      if (holds[b.id]?.containsKey(id) ?? false) continue;
      final share = (b.stock[id] ?? _zero).min(left);
      if (share > _zero) (rest[b.id] ??= {})[id] = share;
      left = left - share;
    }
  }
  final keepAtLeast = <String, Map<String, BigNum>>{};
  for (final rule in f.autoSell) {
    final on = keepAtLeast[rule.bodyId] ??= {};
    final now = on[rule.resourceId];
    on[rule.resourceId] = now == null
        ? rule.keepAtLeast
        : now.min(rule.keepAtLeast);
  }
  return DeliveryKeeps._(
    cache,
    math.max(dt, cache.c.rules.shipmentMergeSeconds),
    holds,
    rest,
    keepAtLeast,
  );
}

/// Selling at a steady rate over [dt] seconds from saturation [s0] while
/// the market for [res] recovers: the average saturation the units sell at
/// ([priceShare]) and the saturation at the end. The sales cut [cut] of
/// the saturation a second: each seller's units a second over its market
/// depth, summed.
///
/// With recovery rate `r = 1 / marketRecoverySeconds` and sales cutting
/// `b = cut` of the saturation a second, `ds/dt = r(1 − s)
/// − b s`: the saturation moves exponentially, at rate `r + b`, toward
/// `r / (r + b)`, and stops at the floor if that lies below it.
({double priceShare, double end}) _sellOverStep(
  Content c,
  ResourceDef res,
  double s0,
  double cut,
  double dt,
) {
  final floor = marketFloorOf(c, res.id);
  final r = 1 / c.rules.marketRecoverySeconds;
  final k = r + cut;
  final eq = r / k;
  // Average saturation over the first t seconds, and the value at t.
  double average(double t) => eq + (s0 - eq) * (1 - math.exp(-k * t)) / (k * t);
  double at(double t) => eq + (s0 - eq) * math.exp(-k * t);
  if (eq >= floor) return (priceShare: average(dt), end: at(dt));
  if (s0 <= floor) return (priceShare: floor, end: floor);
  // Heading below the floor: it gets there at tf and stays.
  final tf = math.log((s0 - eq) / (floor - eq)) / k;
  if (tf >= dt) return (priceShare: average(dt), end: at(dt));
  final area = (tf > 0 ? average(tf) * tf : 0) + floor * (dt - tf);
  return (priceShare: area / dt, end: floor);
}

const _zero = BigNum.zero();

final _one = BigNum.from(1);

/// Pays [f] [revenue] for a sale of [resourceId], adding it to the
/// faction's [FactionState.salesRevenue] and
/// [FactionState.lifetimeCredits].
void _earn(FactionState f, String resourceId, BigNum revenue) {
  f.credits = f.credits + revenue;
  f.lifetimeCredits = f.lifetimeCredits + revenue;
  f.salesRevenue[resourceId] = (f.salesRevenue[resourceId] ?? _zero) + revenue;
}

/// Resource id to what [body]'s buildings use in [dt] at full supply,
/// their owner's crew working at [crewEff] with its [bonuses].
Map<String, BigNum> _stepDemand(
  Content c,
  BodyState body,
  double dt,
  double crewEff,
  EmpireBonuses bonuses,
) {
  final total = <String, BigNum>{};
  for (final b in body.buildings) {
    final inputs = fullRateFlow(
      c,
      body,
      b,
      dt,
      crewEff,
      bonuses: bonuses,
    ).inputs;
    for (final MapEntry(key: id, value: v) in inputs.entries) {
      total[id] = (total[id] ?? _zero) + v;
    }
  }
  return total;
}
