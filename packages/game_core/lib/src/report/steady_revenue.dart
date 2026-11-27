import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../sim/logistics.dart';
import '../sim/market.dart';
import '../sim/megaprojects.dart';
import '../sim/production.dart';
import '../state/game_state.dart';

/// Rounds of [steadySaleRevenue]'s balance at most; each one only lowers
/// rates, and a few settle any chain the content has.
const int _maxRounds = 100;

/// Game seconds [measuredSaleRevenue] plays before it starts measuring,
/// so stock above an auto-sell keep has sold and lots in flight have
/// landed.
const double _warmUpSeconds = 300;

/// Game seconds [measuredSaleRevenue] measures over.
const double _measureSeconds = 600;

/// Step of [measuredSaleRevenue]'s ticks: the engine's default.
const double _stepSeconds = 60;

/// Credits a second [factionId] earns from auto-sales in steady play:
/// the lower of [steadySaleRevenue] and [measuredSaleRevenue], never
/// below zero. What `FlowReport.creditsPerSec` reports.
///
/// Each is an upper estimate in its own way. Steady flows leave out what
/// only playing shows: routes whose stop levels make them run in bursts
/// and leave their destination dry between lots, and lots too big for a
/// store. A short run shows those, but cannot tell goods made from a
/// stock nothing refills from goods made from steady supply. The lower
/// of the two is what the empire keeps earning.
///
/// Neither counts the faction's open contracts: what auto-sell holds back
/// for them fills once and then sells as before, so holding it is not
/// lost income; and an order just posted must not lower the income that
/// sizes the next one's reward. Both copies' boards are cleared for it.
///
/// [s] is a copy of the state to work from, played forward here; its
/// buildings, routes and stock must be the state's, though a second's
/// production may have moved it on. [steady] is the faction's
/// [steadyFlows] in it. [market] is another copy whose market is the
/// state's, give or take a second of sales, on which the steady sales are
/// made; it is changed too.
BigNum saleRevenuePerSec(
  GameState s,
  Content c,
  String factionId, {
  required SteadyFlows steady,
  required GameState market,
}) {
  s.faction(factionId).contracts.clear();
  market.faction(factionId).contracts.clear();
  final steadyRevenue = steadySaleRevenue(
    c,
    factionId,
    steady: steady,
    market: market,
  );
  if (steadyRevenue <= const BigNum.zero()) return const BigNum.zero();
  return steadyRevenue
      .min(measuredSaleRevenue(s, c, factionId))
      .max(const BigNum.zero());
}

/// Credits a second [factionId]'s auto-sales earn over [_measureSeconds]
/// of play from [s], after [_warmUpSeconds] of it, in 60 s ticks of the
/// economy: what `GameEngine.tick` runs, without projects, contracts,
/// milestones or bottleneck notes, so nothing but the economy moves.
///
/// [s] is played forward; pass a copy.
BigNum measuredSaleRevenue(GameState s, Content c, String factionId) {
  BigNum sales() {
    var total = const BigNum.zero();
    for (final v in s.faction(factionId).salesRevenue.values) {
      total = total + v;
    }
    return total;
  }

  void play(double seconds) {
    for (var t = 0.0; t < seconds; t += _stepSeconds) {
      for (final b in s.bodies) {
        b.wastedThisStep.clear();
      }
      final kept = stockOverCap(s, c);
      deliverShipments(s);
      stepProduction(s, c, _stepSeconds);
      sendCargo(s, c, _stepSeconds);
      stepMarket(s, c, _stepSeconds);
      clampStorage(s, c, kept);
      s.time += _stepSeconds;
      landArrivals(s, c);
    }
  }

  play(_warmUpSeconds);
  final before = sales();
  play(_measureSeconds);
  return (sales() - before).mulDouble(1 / _measureSeconds);
}

/// A faction's flows a second once its stocks stop moving, with every
/// flow steady (see [steadyFlows]).
final class SteadyFlows {
  SteadyFlows._(this._netByBody, this.produced, this.surplus);

  /// Body and resource ([_key]) to what is left over there.
  final Map<String, BigNum> _netByBody;

  /// Resource id to what the faction's buildings make of it, before
  /// anything uses it; zero rates left out.
  final Map<String, BigNum> produced;

  /// Resource id to what is left over of it, summed over the faction's
  /// bodies: on each body, what its buildings make and routes bring less
  /// what its buildings use and routes take, where that is above zero;
  /// zero rates left out.
  final Map<String, BigNum> surplus;
}

/// [factionId]'s flows a second with every rate steady, its buildings
/// working at [crewEff] with [bonuses], the faction's.
///
/// Every building of the faction runs at the share of full rate its
/// inputs can keep up with from what its body makes and what routes bring
/// in steadily, never from stock: a press on a stock nothing refills makes
/// nothing here, as it will once the stock runs out. Routes carry at most
/// their rate and capacity, and no more than their source makes spare; a
/// route with a stop level carries only what its destination uses, the
/// rest staying at the source. Rates start at full and are lowered round
/// by round until every input is covered (`supply ≥ demand` on each body),
/// so the result is the fastest the empire can run without drawing stock
/// down. Stock plays no part, so the flows of a copy whose stock moved on
/// are the state's.
SteadyFlows steadyFlows(
  GameState s,
  Content c,
  String factionId, {
  required double crewEff,
  required EmpireBonuses bonuses,
}) => _steadyNet(s, c, factionId, crewEff, bonuses);

/// Credits a second [factionId] earns from auto-selling its net production
/// once its stocks stop moving, with every flow steady ([steady]).
///
/// What is left over on a body is its net production; each auto-sell rule
/// sells that much of its resource a second, once its keep is full
/// ([autoSellKeep]), at the market's current saturation, as one second of
/// [stepMarket] would. Stock already above a keep is not counted: it sells
/// once and is gone.
///
/// [market] is a copy of the state the sales are made on; it is changed.
BigNum steadySaleRevenue(
  Content c,
  String factionId, {
  required SteadyFlows steady,
  required GameState market,
}) {
  final net = steady._netByBody;
  final limits = <String, Map<String, BigNum>>{};
  final f = market.faction(factionId);
  for (final rule in f.autoSell) {
    final body = market.body(rule.bodyId);
    if (body.ownerId != factionId) continue;
    final spare = net[_key(body.id, rule.resourceId)];
    if (spare == null || spare <= const BigNum.zero()) continue;
    if (limits[body.id]?.containsKey(rule.resourceId) ?? false) continue;
    (limits[body.id] ??= {})[rule.resourceId] = spare;
    // A full keep, as in steady play, plus this second's spare.
    final keep = autoSellKeep(market, c, rule, 1).keeps;
    body.stock[rule.resourceId] = keep.min(storageCap(market, c, body)) + spare;
  }
  if (limits.isEmpty) return const BigNum.zero();
  final before = f.credits;
  stepMarket(market, c, 1, limits: limits);
  return f.credits - before;
}

/// One building's full-rate flow a second, and the share of it it runs at.
final class _Run {
  _Run(this.bodyId, this.inputs, this.outputs);

  final String bodyId;
  final Map<String, BigNum> inputs;
  final Map<String, BigNum> outputs;
  double share = 1;
}

/// One route's most a second, and the share of it it carries.
final class _Leg {
  _Leg(this.route, this.most);

  final RouteState route;
  final BigNum most;
  double share = 1;

  BigNum get carried => most.mulDouble(share);
}

String _key(String bodyId, String resourceId) => '$bodyId/$resourceId';

/// [factionId]'s [SteadyFlows]: what its bodies make and receive a second
/// less what they use and send, by body and resource ([_key]), with every
/// rate balanced as [steadyFlows] describes; zero entries left out.
SteadyFlows _steadyNet(
  GameState s,
  Content c,
  String factionId,
  double crewEff,
  EmpireBonuses bonuses,
) {
  final runs = <_Run>[];
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    for (final b in body.buildings) {
      final flow = fullRateFlow(c, body, b, 1, crewEff, bonuses: bonuses);
      if (flow.outputs.isEmpty && flow.inputs.isEmpty) continue;
      runs.add(_Run(body.id, flow.inputs, flow.outputs));
    }
  }
  final legs = [
    for (final r in s.routes)
      if (r.ownerId == factionId &&
          s.body(r.fromBodyId).ownerId == factionId &&
          s.body(r.toBodyId).ownerId == factionId)
        _Leg(r, r.ratePerSecond.min(routeCapacity(c, r))),
  ];

  var supply = <String, BigNum>{};
  var demand = <String, BigNum>{};
  void tally() {
    supply = {};
    demand = {};
    void add(Map<String, BigNum> into, String key, BigNum v) {
      if (!v.isZero) into[key] = (into[key] ?? const BigNum.zero()) + v;
    }

    for (final run in runs) {
      for (final MapEntry(key: id, value: v) in run.outputs.entries) {
        add(supply, _key(run.bodyId, id), v.mulDouble(run.share));
      }
      for (final MapEntry(key: id, value: v) in run.inputs.entries) {
        add(demand, _key(run.bodyId, id), v.mulDouble(run.share));
      }
    }
    for (final leg in legs) {
      final r = leg.route;
      add(supply, _key(r.toBodyId, r.resourceId), leg.carried);
      add(demand, _key(r.fromBodyId, r.resourceId), leg.carried);
    }
  }

  /// Share of the demand on [key] its supply covers, at most 1.
  double covered(String key) {
    final want = demand[key];
    if (want == null || want.isZero) return 1;
    final have = supply[key] ?? const BigNum.zero();
    return have >= want ? 1 : (have / want).toDouble().clamp(0.0, 1.0);
  }

  for (var round = 0; round < _maxRounds; round++) {
    tally();
    var moved = 0.0;
    void lower(double from, double to, void Function(double) set) {
      if (to < from) {
        moved = math.max(moved, from - to);
        set(to);
      }
    }

    // Spare on each destination of a stop-level route, to be left at the
    // source instead: what the stop-level routes into it carry, shared in
    // proportion.
    final stopInflow = <String, BigNum>{};
    for (final leg in legs) {
      if (leg.route.stopAtDestination == null) continue;
      final key = _key(leg.route.toBodyId, leg.route.resourceId);
      stopInflow[key] = (stopInflow[key] ?? const BigNum.zero()) + leg.carried;
    }
    final legShares = <_Leg, double>{};
    for (final leg in legs) {
      final r = leg.route;
      var share = leg.share * covered(_key(r.fromBodyId, r.resourceId));
      final key = _key(r.toBodyId, r.resourceId);
      final inflow = stopInflow[key];
      if (r.stopAtDestination != null && inflow != null && !inflow.isZero) {
        final spare =
            (supply[key] ?? const BigNum.zero()) -
            (demand[key] ?? const BigNum.zero());
        if (spare > const BigNum.zero() && !leg.most.isZero) {
          final cut = spare.min(inflow) * (leg.carried / inflow);
          final left = ((leg.carried - cut) / leg.most).toDouble();
          share = math.min(share, left.clamp(0.0, 1.0));
        }
      }
      legShares[leg] = share;
    }
    for (final run in runs) {
      var share = run.share;
      for (final id in run.inputs.keys) {
        share = math.min(share, run.share * covered(_key(run.bodyId, id)));
      }
      lower(run.share, share, (v) => run.share = v);
    }
    for (final MapEntry(key: leg, value: share) in legShares.entries) {
      lower(leg.share, share, (v) => leg.share = v);
    }
    if (moved < 1e-9) break;
  }
  tally();
  final net = {
    for (final MapEntry(key: key, value: made) in supply.entries)
      if (made - (demand[key] ?? const BigNum.zero()) case final left
          when left > const BigNum.zero())
        key: left,
  };
  void add(Map<String, BigNum> into, String id, BigNum v) {
    if (!v.isZero) into[id] = (into[id] ?? const BigNum.zero()) + v;
  }

  final produced = <String, BigNum>{};
  for (final run in runs) {
    for (final MapEntry(key: id, value: v) in run.outputs.entries) {
      add(produced, id, v.mulDouble(run.share));
    }
  }
  final surplus = <String, BigNum>{};
  for (final MapEntry(key: key, value: v) in net.entries) {
    add(surplus, key.substring(key.lastIndexOf('/') + 1), v);
  }
  return SteadyFlows._(net, produced, surplus);
}
