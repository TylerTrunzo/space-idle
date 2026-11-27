import 'dart:math' as math;

import '../commands/apply.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../sim/crew.dart';
import '../sim/logistics.dart';
import '../sim/market.dart';
import '../sim/megaprojects.dart';
import '../sim/production.dart';
import '../state/game_state.dart';
import 'steady_revenue.dart';

/// How one building ran in the report's sample step.
final class BuildingStatus {
  /// Creates a building status; the maps are copied unmodifiable.
  BuildingStatus({
    required this.buildingId,
    required this.defId,
    required this.runFraction,
    required this.effectiveFraction,
    required this.limitReason,
    required this.crew,
    required this.slots,
    required Map<String, BigNum> inputsPerSec,
    required Map<String, BigNum> outputsPerSec,
  }) : inputsPerSec = Map.unmodifiable(inputsPerSec),
       outputsPerSec = Map.unmodifiable(outputsPerSec);

  /// The building's id.
  final String buildingId;

  /// Id of its [BuildingDef].
  final String defId;

  /// Share of full input supply it ran at, in `[0, 1]`; warehouses run no
  /// recipe and stay at 0.
  final double runFraction;

  /// Its actual output as a share of what it makes with its base crew
  /// slots full, every input supplied and the faction fully housed:
  /// `runFraction × crew / base slots × crew efficiency`.
  ///
  /// Shows staffing and housing as well as supply: a fully supplied
  /// building with half its slots crewed is at 0.5. Above 1 when capacity
  /// upgrades hold crew beyond the base slots; 0 for warehouses and
  /// unstaffed buildings. Speed upgrades do not count; see [outputsPerSec]
  /// for the rate.
  final double effectiveFraction;

  /// `noCrew`, `input:<resourceId>`, `understaffed` (fully supplied, crew
  /// below its base slots), or null when nothing held it back.
  final String? limitReason;

  /// Crew assigned.
  final int crew;

  /// Most crew it can hold, capacity upgrades included.
  final int slots;

  /// Resource id to units it actually used per second, in content order;
  /// zero rates left out.
  final Map<String, BigNum> inputsPerSec;

  /// Resource id to units it actually made per second, before the storage
  /// cap, in content order; zero rates left out.
  final Map<String, BigNum> outputsPerSec;
}

/// Per-second flows on one body.
final class BodyFlow {
  /// Creates a body flow; the collections are copied unmodifiable.
  BodyFlow({
    required this.bodyId,
    required Map<String, BigNum> producedPerSec,
    required Map<String, BigNum> consumedPerSec,
    required Map<String, BigNum> netPerSec,
    required Map<String, BigNum> wastedPerSec,
    required List<BuildingStatus> buildings,
  }) : producedPerSec = Map.unmodifiable(producedPerSec),
       consumedPerSec = Map.unmodifiable(consumedPerSec),
       netPerSec = Map.unmodifiable(netPerSec),
       wastedPerSec = Map.unmodifiable(wastedPerSec),
       buildings = List.unmodifiable(buildings);

  /// The body's id.
  final String bodyId;

  /// Resource id to units its buildings made, before the storage cap.
  final Map<String, BigNum> producedPerSec;

  /// Resource id to units its buildings used up.
  final Map<String, BigNum> consumedPerSec;

  /// Resource id to the change in its stock: production, consumption,
  /// waste, cargo sent and landed, and auto-sales all included.
  final Map<String, BigNum> netPerSec;

  /// Resource id to units lost to its storage cap.
  final Map<String, BigNum> wastedPerSec;

  /// Its buildings in list order.
  final List<BuildingStatus> buildings;
}

/// What holds a [Bottleneck] back.
enum BottleneckKind {
  /// A building is short of one of its inputs.
  input,

  /// A building has no crew assigned.
  noCrew,

  /// A building has every input but fewer crew than its base slots.
  understaffed,

  /// Habitats and base crew support fewer crew than the faction has
  /// assigned, so every crewed building works below its crew.
  crewShortage,

  /// A body's stock of one resource is at its storage cap and what more
  /// arrives is wasted.
  storageFull,

  /// The faction's buildings make goods that sell, but it has no auto-sell
  /// rule on any body it owns, so nothing sells unless it sells by hand.
  noSales,
}

/// Something running below full rate, and why: a building, a body's full
/// store of one resource, or for a crew shortage the whole faction.
final class Bottleneck {
  /// Creates a bottleneck.
  const Bottleneck({
    required this.kind,
    required this.bodyId,
    required this.buildingId,
    required this.resourceId,
    required this.runFraction,
    required this.message,
    this.firstSeenAt = 0,
    this.lostCreditsPerHour,
  });

  /// What holds it back.
  final BottleneckKind kind;

  /// Body the building or store is on; null for
  /// [BottleneckKind.crewShortage] and [BottleneckKind.noSales], which are
  /// faction-wide.
  final String? bodyId;

  /// The held-back building; null for [BottleneckKind.crewShortage],
  /// [BottleneckKind.storageFull] and [BottleneckKind.noSales].
  final String? buildingId;

  /// The input a building is short of ([BottleneckKind.input]) or the
  /// resource being wasted ([BottleneckKind.storageFull]); otherwise null.
  final String? resourceId;

  /// Share of full rate achieved, in `[0, 1)`: a building's run fraction,
  /// for [BottleneckKind.understaffed] its crew over its base slots;
  /// for [BottleneckKind.crewShortage] the faction's crew efficiency; for
  /// [BottleneckKind.storageFull] the share of the body's own output of the
  /// resource that it kept (0 when only arriving cargo was wasted); 0 for
  /// [BottleneckKind.noSales].
  final double runFraction;

  /// Plain-English description using display names, such as
  /// "Smelter on Kora is running at 50%: not enough Iron Ore".
  final String message;

  /// Game time in seconds since which the faction has had it without a
  /// break, from [FactionState.seenBottlenecks]; the report's own time when
  /// it is new.
  final double firstSeenAt;

  /// Estimated credits it costs an hour, at current market prices, where
  /// that can be worked out: for [BottleneckKind.storageFull] the wasted
  /// units' value; for [BottleneckKind.input] the value of the output the
  /// building does not make; for [BottleneckKind.noSales] the value of
  /// the faction's net production of goods that sell; for
  /// [BottleneckKind.crewShortage] the value of the output its crewed
  /// buildings do not make at their run fractions against full staffing
  /// (zero when none of them runs). Null for the other kinds.
  final BigNum? lostCreditsPerHour;

  /// Restores a bottleneck written by [toJson].
  factory Bottleneck.fromJson(Map<String, Object?> j) => Bottleneck(
    kind: BottleneckKind.values.byName(j['kind']! as String),
    bodyId: j['bodyId'] as String?,
    buildingId: j['buildingId'] as String?,
    resourceId: j['resourceId'] as String?,
    runFraction: (j['runFraction']! as num).toDouble(),
    message: j['message']! as String,
    firstSeenAt: (j['firstSeenAt']! as num).toDouble(),
    lostCreditsPerHour: switch (j['lostCreditsPerHour']) {
      final String v => BigNum.fromJson(v),
      _ => null,
    },
  );

  /// [kind], [bodyId], [buildingId] and [resourceId] as one key, as in
  /// [SeenBottleneck.key].
  String get key => bottleneckKey(kind.name, bodyId, buildingId, resourceId);

  /// This bottleneck as JSON, null fields left out.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'bodyId': ?bodyId,
    'buildingId': ?buildingId,
    'resourceId': ?resourceId,
    'runFraction': runFraction,
    'message': message,
    'firstSeenAt': firstSeenAt,
    'lostCreditsPerHour': ?lostCreditsPerHour?.toJson(),
  };

  Bottleneck _with({double? firstSeenAt, BigNum? lostCreditsPerHour}) =>
      Bottleneck(
        kind: kind,
        bodyId: bodyId,
        buildingId: buildingId,
        resourceId: resourceId,
        runFraction: runFraction,
        message: message,
        firstSeenAt: firstSeenAt ?? this.firstSeenAt,
        lostCreditsPerHour: lostCreditsPerHour ?? this.lostCreditsPerHour,
      );
}

/// A faction's resource flows and bottlenecks, per second.
final class FlowReport {
  /// Creates a report; the collections are copied unmodifiable.
  ///
  /// [creditsPerSec] is called the first time [FlowReport.creditsPerSec]
  /// is read, and only then; [steady] the first time a steady rate is
  /// read: resource id to what the faction's buildings make, and resource
  /// id to what is left over, with every flow steady.
  FlowReport({
    required List<BodyFlow> bodies,
    required Map<String, BigNum> empireNet,
    required BigNum Function() creditsPerSec,
    required (Map<String, BigNum>, Map<String, BigNum>) Function() steady,
    required List<Bottleneck> bottlenecks,
  }) : _creditsPerSec = creditsPerSec,
       _steady = steady,
       bodies = List.unmodifiable(bodies),
       empireNet = Map.unmodifiable(empireNet),
       bottlenecks = List.unmodifiable(bottlenecks);

  /// Flows of each body the faction owns, in body order.
  final List<BodyFlow> bodies;

  /// Resource id to the change in the faction's holdings, cargo in flight
  /// counted as held, so moving goods between its own bodies nets to zero.
  final Map<String, BigNum> empireNet;

  /// Credits the faction earns per second in steady state: the auto-sale
  /// revenue of its net production once stocks stop moving, with every
  /// building held to the inputs it can get without drawing stock down,
  /// and no more than a short run of play earns (`saleRevenuePerSec`).
  /// Stock drawn down by consumers, or sold from above an auto-sell keep,
  /// does not count; commands (sales, contracts) are not part of it.
  ///
  /// Worked out the first time it is read, from the state the report was
  /// built from: it plays a copy of it forward, which costs several ticks.
  /// Until then the report keeps two copies of that state; it drops them
  /// once this is read.
  late final BigNum creditsPerSec = _creditsPerSec();

  final BigNum Function() _creditsPerSec;

  late final (Map<String, BigNum>, Map<String, BigNum>) _steadyRates =
      _steady();

  final (Map<String, BigNum>, Map<String, BigNum>) Function() _steady;

  /// Units of [resourceId] the faction's buildings make a second with
  /// every flow steady: each building held to the share of full rate its
  /// inputs can keep up with from what is made and what routes bring in
  /// steadily, never from stock, as in [creditsPerSec]. Gross of what
  /// buildings use; zero when only a stock nothing refills feeds it.
  BigNum steadyProducedPerSec(String resourceId) =>
      _steadyRates.$1[resourceId] ?? const BigNum.zero();

  /// Units of [resourceId] left over a second with every flow steady (see
  /// [steadyProducedPerSec]): on each of the faction's bodies, what its
  /// buildings make and routes bring less what its buildings use and
  /// routes take, where that is above zero, summed.
  BigNum steadySurplusPerSec(String resourceId) =>
      _steadyRates.$2[resourceId] ?? const BigNum.zero();

  /// Everything held back, lowest run fraction first, then in report order:
  /// goods made with nothing selling them ([BottleneckKind.noSales]) and a
  /// crew shortage first, then each body's buildings in order followed by
  /// its full stores in content resource order.
  final List<Bottleneck> bottlenecks;

  /// Units of [resourceId] the faction's buildings make a second, summed
  /// over its bodies ([BodyFlow.producedPerSec]): their output at the run
  /// fractions of the sample step, before the storage cap, whatever uses
  /// it up.
  BigNum producedPerSec(String resourceId) {
    var made = const BigNum.zero();
    for (final b in bodies) {
      made = made + (b.producedPerSec[resourceId] ?? const BigNum.zero());
    }
    return made;
  }

  /// Units of [resourceId] the faction's buildings make a second less what
  /// they use, summed over its bodies: [BodyFlow.producedPerSec] minus
  /// [BodyFlow.consumedPerSec]. Before the storage cap, cargo and sales;
  /// negative when its buildings use more than they make.
  BigNum netProducedPerSec(String resourceId) {
    var net = const BigNum.zero();
    for (final b in bodies) {
      net =
          net +
          (b.producedPerSec[resourceId] ?? const BigNum.zero()) -
          (b.consumedPerSec[resourceId] ?? const BigNum.zero());
    }
    return net;
  }
}

/// Seconds of the sample step the rates are measured over.
const double _sampleSeconds = 1;

/// Reports [factionId]'s per-second flows and bottlenecks.
///
/// The rates are steady-state rates: what one second of play moves once
/// the economy runs as it does now, not one tick's catch-up. They come
/// from a sample step of 1 s run on a deep copy of [s], so [s] is never
/// changed. The step runs the engine's tick in order (production, cargo,
/// market, storage cap) with two changes that take out one-off lumps:
///
/// - Cargo flows steadily: each route's cargo lands at its destination
///   at the rate the route sends it (measured by a first pass over another
///   copy), while cargo already in flight, which lands in lumps, is left
///   out.
/// - Auto-sell sells only what the step added to a body's stock, never
///   stock built up before it, such as the step's demand kept back by a
///   long tick that a 1 s step no longer needs.
///
/// [FlowReport.creditsPerSec] is worked out apart from the sample step,
/// when first read (`saleRevenuePerSec`): a sample second can run a
/// factory on stock it will not have once the stock runs out, or on a lot
/// that just landed from a route that will leave it dry for a minute. So
/// over a stable stretch of play it matches the credits actually earned
/// per second.
///
/// Net rates are stock differences across the step; produced and consumed
/// rates are each building's [fullRateFlow] scaled by the run fraction the
/// step settled on. All maps list resources in content order and leave out
/// zero rates. Throws if the faction does not exist.
FlowReport buildFlowReport(GameState s, Content c, String factionId) {
  // First pass: what each route sends in a step from this state.
  final probe = s.copy();
  deliverShipments(probe);
  stepProduction(probe, c, _sampleSeconds);
  final playedEff = crewEfficiency(probe, c, factionId);
  final routeFlow = sendCargo(probe, c, _sampleSeconds);

  final copy = s.copy()..shipments.clear();
  final owned = [
    for (final b in copy.bodies)
      if (b.ownerId == factionId) b,
  ];
  final stockBefore = [for (final b in owned) Map.of(b.stock)];
  final atStart = {for (final b in copy.bodies) b.id: Map.of(b.stock)};
  final holdingsBefore = _holdings(copy, factionId);
  // The crew shortage is read from the state as it is, so its counts are
  // the ones `crewTotals` gives; the sample step then settles on its own
  // housing (`stepProduction`), which after a tick of play is the same.
  final crewEff = crewEfficiency(copy, c, factionId);
  final bonuses = bonusesFor(copy, c, factionId);
  final crewNeck = _crewShortage(copy, c, factionId, crewEff);

  final kept = stockOverCap(copy, c);
  // Steady cargo: what each route sends lands as it leaves. It counts as
  // held in flight before the step, so moving it nets to zero.
  for (final r in copy.routes) {
    final amount = routeFlow[r.id];
    if (amount == null) continue;
    final to = copy.body(r.toBodyId);
    to.stock[r.resourceId] =
        (to.stock[r.resourceId] ?? const BigNum.zero()) + amount;
    if (r.ownerId == factionId) {
      holdingsBefore[r.resourceId] =
          (holdingsBefore[r.resourceId] ?? const BigNum.zero()) + amount;
    }
  }
  // With a crew shortage, the same production step on a copy at full
  // staffing shows what the shortage costs.
  final staffed = crewNeck == null ? null : copy.copy();
  stepProduction(copy, c, _sampleSeconds);
  final crewLost = staffed == null
      ? null
      : _staffingGain(s, c, factionId, staffed, copy);
  // The efficiency the sample step settled on, which its run fractions
  // go with.
  final settledEff = crewEfficiency(copy, c, factionId);
  sendCargo(copy, c, _sampleSeconds);
  stepMarket(
    copy,
    c,
    _sampleSeconds,
    limits: {
      for (final b in copy.bodies)
        b.id: {
          for (final MapEntry(key: id, value: v) in b.stock.entries)
            if (v - (atStart[b.id]![id] ?? const BigNum.zero()) case final added
                when added > const BigNum.zero())
              id: added,
        },
    },
  );
  clampStorage(copy, c, kept);

  final bodies = <BodyFlow>[];
  final bottlenecks = <(int, Bottleneck)>[
    if (crewNeck != null) (0, crewNeck._with(lostCreditsPerHour: crewLost)),
  ];
  void addNeck(Bottleneck? neck) {
    if (neck != null) bottlenecks.add((bottlenecks.length, neck));
  }

  for (final (i, body) in owned.indexed) {
    final produced = <String, BigNum>{};
    final consumed = <String, BigNum>{};
    final statuses = <BuildingStatus>[];
    for (final b in body.buildings) {
      final def = c.buildings[b.defId]!;
      final flow = fullRateFlow(
        c,
        body,
        b,
        _sampleSeconds,
        settledEff,
        bonuses: bonuses,
      );
      final inputs = _scaled(flow.inputs, b.lastRunFraction);
      final outputs = _scaled(flow.outputs, b.lastRunFraction);
      _addAll(produced, outputs);
      _addAll(consumed, inputs);
      final neck = _bottleneck(c, body, b);
      addNeck(
        neck?.kind == BottleneckKind.input
            ? neck!._with(
                lostCreditsPerHour: _valuePerHour(
                  s,
                  c,
                  _scaled(flow.outputs, 1 - b.lastRunFraction),
                ),
              )
            : neck,
      );
      statuses.add(
        BuildingStatus(
          buildingId: b.id,
          defId: b.defId,
          runFraction: b.lastRunFraction,
          effectiveFraction: runsWithoutCrew(def)
              ? b.lastRunFraction
              : def.crewSlots == 0
              ? 0
              : b.lastRunFraction * b.crew / def.crewSlots * settledEff,
          limitReason: b.lastLimitReason,
          crew: b.crew,
          slots: maxCrew(c.rules, def, b),
          inputsPerSec: _ordered(c, inputs),
          outputsPerSec: _ordered(c, outputs),
        ),
      );
    }
    final cap = storageCap(copy, c, body);
    for (final id in c.resources.keys) {
      addNeck(
        _storageFull(c, body, id, cap, produced[id])?._with(
          lostCreditsPerHour: _valuePerHour(s, c, {
            id: body.wastedThisStep[id]!,
          }),
        ),
      );
    }
    bodies.add(
      BodyFlow(
        bodyId: body.id,
        producedPerSec: _ordered(c, produced),
        consumedPerSec: _ordered(c, consumed),
        netPerSec: _diff(c, body.stock, stockBefore[i]),
        wastedPerSec: _ordered(c, body.wastedThisStep),
        buildings: statuses,
      ),
    );
  }
  final unsold = _unsoldNet(
    c,
    copy.faction(factionId),
    owned,
    settledEff,
    bonuses,
  );
  if (unsold.isNotEmpty) {
    // Faction-wide: first in report order.
    bottlenecks.add((
      -1,
      _noSales._with(lostCreditsPerHour: _valuePerHour(s, c, unsold)),
    ));
  }
  bottlenecks.sort((x, y) {
    final byRun = x.$2.runFraction.compareTo(y.$2.runFraction);
    return byRun != 0 ? byRun : x.$1.compareTo(y.$1);
  });
  final since = {
    for (final seen in s.faction(factionId).seenBottlenecks)
      seen.key: seen.firstSeenAt,
  };
  // Credits per second is worked out only when asked for, on the two
  // copies, which nothing else reads once the report is built; the report
  // lets go of them once it has, so it holds no state but its own.
  GameState? played = probe;
  GameState? sold = copy;
  // Steady flows take no stock into account, so the played copy gives the
  // state's; worked out once, for credits per second and steady rates.
  SteadyFlows? steady;
  SteadyFlows steadyOf() => steady ??= steadyFlows(
    played!,
    c,
    factionId,
    crewEff: playedEff,
    bonuses: bonuses,
  );
  return FlowReport(
    bodies: bodies,
    empireNet: _diff(c, _holdings(copy, factionId), holdingsBefore),
    creditsPerSec: () {
      final v = saleRevenuePerSec(
        played!,
        c,
        factionId,
        steady: steadyOf(),
        market: sold!,
      );
      played = null;
      sold = null;
      return v;
    },
    steady: () {
      final f = steadyOf();
      return (f.produced, f.surplus);
    },
    bottlenecks: [
      for (final (_, b) in bottlenecks)
        b._with(firstSeenAt: since[b.key] ?? s.time),
    ],
  );
}

/// Credits an hour that [perSec] (resource id to units a second) is worth
/// at the current market prices of [s].
BigNum _valuePerHour(GameState s, Content c, Map<String, BigNum> perSec) {
  var total = const BigNum.zero();
  for (final MapEntry(key: id, value: v) in perSec.entries) {
    total = total + v * price(s, c, id);
  }
  return total.mulDouble(3600);
}

/// Refreshes every faction's [FactionState.seenBottlenecks] from the tick
/// that just ran: a bottleneck still there keeps its first-seen time, a
/// new one is seen [at], and one that cleared is dropped.
///
/// Reads what the tick left in [s], as the report does: each building's
/// [BuildingState.lastLimitReason], each full store that wasted output
/// ([BodyState.wastedThisStep]), and a crew efficiency below 1. The engine
/// calls it at the end of every tick with the tick's start time.
void noteBottlenecks(GameState s, Content c, double at) {
  for (final f in s.factions) {
    final before = {for (final b in f.seenBottlenecks) b.key: b.firstSeenAt};
    final now = <SeenBottleneck>[];
    void see(String kind, String? body, String? building, String? resource) {
      now.add(
        SeenBottleneck(
          kind: kind,
          bodyId: body,
          buildingId: building,
          resourceId: resource,
          firstSeenAt:
              before[bottleneckKey(kind, body, building, resource)] ?? at,
        ),
      );
    }

    if (crewEfficiency(s, c, f.id) < 1 &&
        crewTotals(s, c, f.id).overAssigned > 0) {
      see(BottleneckKind.crewShortage.name, null, null, null);
    }
    final owned = [
      for (final b in s.bodies)
        if (b.ownerId == f.id) b,
    ];
    final unsold = _unsoldNet(
      c,
      f,
      owned,
      crewEfficiency(s, c, f.id),
      bonusesFor(s, c, f.id),
    );
    if (unsold.isNotEmpty) {
      see(BottleneckKind.noSales.name, null, null, null);
    }
    for (final body in s.bodies) {
      if (body.ownerId != f.id) continue;
      for (final b in body.buildings) {
        final reason = b.lastLimitReason;
        if (reason == null || !runsRecipe(c.buildings[b.defId]!)) continue;
        if (reason.startsWith('input:')) {
          see(
            BottleneckKind.input.name,
            body.id,
            b.id,
            reason.substring('input:'.length),
          );
        } else {
          see(reason, body.id, b.id, null);
        }
      }
      if (body.wastedThisStep.isEmpty) continue;
      final cap = storageCap(s, c, body);
      for (final id in c.resources.keys) {
        final wasted = body.wastedThisStep[id];
        if (wasted == null || wasted.isZero) continue;
        if ((body.stock[id] ?? const BigNum.zero()) < cap) continue;
        see(BottleneckKind.storageFull.name, body.id, null, id);
      }
    }
    f.seenBottlenecks
      ..clear()
      ..addAll(now);
  }
}

/// The no-sales bottleneck, before its lost credits are worked out.
const _noSales = Bottleneck(
  kind: BottleneckKind.noSales,
  bodyId: null,
  buildingId: null,
  resourceId: null,
  runFraction: 0,
  message: 'Nothing is being sold: turn on auto-sell or sell goods',
);

/// Resource id to what [f]'s buildings on the [owned] bodies make a
/// second of each good with a price beyond what they use, at the run
/// fractions they last settled on ([fullRateFlow] at [crewEff] with
/// [bonuses]), the positive entries only, in content order; empty when
/// [f] has an auto-sell rule on one of those bodies.
///
/// The one test for [BottleneckKind.noSales], in the report and in
/// [noteBottlenecks] alike, so the time it was first seen matches what
/// the report shows.
Map<String, BigNum> _unsoldNet(
  Content c,
  FactionState f,
  List<BodyState> owned,
  double crewEff,
  EmpireBonuses bonuses,
) {
  final ids = {for (final b in owned) b.id};
  if (f.autoSell.any((r) => ids.contains(r.bodyId))) return const {};
  final made = <String, BigNum>{};
  final used = <String, BigNum>{};
  for (final body in owned) {
    for (final b in body.buildings) {
      if (b.lastRunFraction == 0) continue;
      final flow = fullRateFlow(c, body, b, 1, crewEff, bonuses: bonuses);
      _addAll(made, _scaled(flow.outputs, b.lastRunFraction));
      _addAll(used, _scaled(flow.inputs, b.lastRunFraction));
    }
  }
  // Float residue of made ≈ used snaps to zero (see [changeBetween]).
  return {
    for (final r in c.resources.values)
      if (!r.basePrice.isZero)
        if (changeBetween(
              made[r.id] ?? const BigNum.zero(),
              used[r.id] ?? const BigNum.zero(),
            )
            case final v when v > const BigNum.zero())
          r.id: v,
  };
}

/// Credits an hour [factionId]'s production would gain at full staffing:
/// [staffed], a copy of [actual] from before its sample production step,
/// runs that step at crew efficiency 1, and the change in each resource
/// over the faction's bodies is set against [actual]'s, valued at the
/// current market prices of [s]. Never below zero.
///
/// So a building held back by its inputs gains nothing, and goods made
/// only to be used up on the same body (ore a smelter takes) count only
/// through what is made from them.
BigNum _staffingGain(
  GameState s,
  Content c,
  String factionId,
  GameState staffed,
  GameState actual,
) {
  stepProduction(staffed, c, _sampleSeconds, crewEfficiencyOf: {factionId: 1});
  Map<String, BigNum> held(GameState g) {
    final total = <String, BigNum>{};
    for (final b in g.bodies) {
      if (b.ownerId != factionId) continue;
      _addAll(total, b.stock);
    }
    return total;
  }

  final more = held(staffed);
  final now = held(actual);
  final gain = <String, BigNum>{
    for (final id in c.resources.keys)
      if (changeBetween(
            more[id] ?? const BigNum.zero(),
            now[id] ?? const BigNum.zero(),
          )
          case final d when !d.isZero)
        id: d,
  };
  return _valuePerHour(s, c, gain).max(const BigNum.zero());
}

/// The crew-shortage bottleneck of [factionId], or null when its crew
/// efficiency [crewEff] is 1.
///
/// [s] must be the state before the sample tick, so the crew counts match
/// [crewEff].
Bottleneck? _crewShortage(
  GameState s,
  Content c,
  String factionId,
  double crewEff,
) {
  final t = crewTotals(s, c, factionId);
  // A shortage only when housing truly falls short of the crew assigned:
  // the same test, within the same tolerance, as the crew counts.
  if (crewEff >= 1 || t.overAssigned == 0) return null;
  return Bottleneck(
    kind: BottleneckKind.crewShortage,
    bodyId: null,
    buildingId: null,
    resourceId: null,
    runFraction: crewEff,
    message:
        'Your empire is short on crew: habitats and base crew support '
        '${t.supported} of ${t.assigned} assigned',
  );
}

/// The storage-full bottleneck of resource [id] on [body] after the sample
/// step, or null unless its stock is at the storage [cap] and some was
/// wasted; [produced] is what the body's buildings made of it.
Bottleneck? _storageFull(
  Content c,
  BodyState body,
  String id,
  BigNum cap,
  BigNum? produced,
) {
  final wasted = body.wastedThisStep[id];
  if (wasted == null || wasted.isZero) return null;
  if ((body.stock[id] ?? const BigNum.zero()) < cap) return null;
  final made = produced ?? const BigNum.zero();
  // Kept units, with float residue of waste ≈ output snapped to zero.
  final kept = changeBetween(made, wasted);
  final share = made.isZero || kept.isNegative ? 0.0 : (kept / made).toDouble();
  return Bottleneck(
    kind: BottleneckKind.storageFull,
    bodyId: body.id,
    buildingId: null,
    resourceId: id,
    runFraction: share.clamp(0, 1).toDouble(),
    message:
        '${body.name} storage is full of ${c.resources[id]!.name}: '
        'output is being wasted',
  );
}

/// The bottleneck building [b] on [body] shows after the sample step, or
/// null when it ran unhindered or runs no recipe.
Bottleneck? _bottleneck(Content c, BodyState body, BuildingState b) {
  final def = c.buildings[b.defId]!;
  final reason = b.lastLimitReason;
  if (!runsRecipe(def) || reason == null) return null;
  final where = '${def.name} on ${body.name}';
  final BottleneckKind kind;
  final String? resourceId;
  final String message;
  if (reason.startsWith('input:')) {
    kind = BottleneckKind.input;
    resourceId = reason.substring('input:'.length);
    // Rounded, but never shown as 100% while held back.
    final pct = math.min(99, (b.lastRunFraction * 100).round());
    message =
        '$where is running at $pct%: '
        'not enough ${c.resources[resourceId]!.name}';
  } else if (reason == 'understaffed') {
    return Bottleneck(
      kind: BottleneckKind.understaffed,
      bodyId: body.id,
      buildingId: b.id,
      resourceId: null,
      runFraction: b.lastRunFraction * b.crew / def.crewSlots,
      message: '$where is understaffed: ${b.crew} of ${def.crewSlots} crew',
    );
  } else {
    kind = BottleneckKind.noCrew;
    resourceId = null;
    message = '$where has no crew';
  }
  return Bottleneck(
    kind: kind,
    bodyId: body.id,
    buildingId: b.id,
    resourceId: resourceId,
    runFraction: b.lastRunFraction,
    message: message,
  );
}

/// Resource id to units [factionId] holds: the stock of every body it owns
/// plus the cargo in flight in its shipments.
Map<String, BigNum> _holdings(GameState s, String factionId) {
  final total = <String, BigNum>{};
  void add(String id, BigNum v) =>
      total[id] = (total[id] ?? const BigNum.zero()) + v;
  for (final b in s.bodies) {
    if (b.ownerId != factionId) continue;
    b.stock.forEach(add);
  }
  for (final sh in s.shipments) {
    if (sh.ownerId == factionId) add(sh.resourceId, sh.amount);
  }
  return total;
}

/// Each entry of [amounts] times [fraction], leaving out zeros.
Map<String, BigNum> _scaled(Map<String, BigNum> amounts, double fraction) => {
  if (fraction != 0)
    for (final MapEntry(key: id, value: v) in amounts.entries)
      if (v.mulDouble(fraction) case final scaled when !scaled.isZero)
        id: scaled,
};

/// Adds each entry of [amounts] into [into].
void _addAll(Map<String, BigNum> into, Map<String, BigNum> amounts) {
  for (final MapEntry(key: id, value: v) in amounts.entries) {
    into[id] = (into[id] ?? const BigNum.zero()) + v;
  }
}

/// `after − before` per resource in content order, leaving out changes that
/// are zero or only float residue (see [changeBetween]).
Map<String, BigNum> _diff(
  Content c,
  Map<String, BigNum> after,
  Map<String, BigNum> before,
) => {
  for (final id in c.resources.keys)
    if (changeBetween(
          after[id] ?? const BigNum.zero(),
          before[id] ?? const BigNum.zero(),
        )
        case final d when !d.isZero)
      id: d,
};

/// The non-zero entries of [m] in content resource order.
Map<String, BigNum> _ordered(Content c, Map<String, BigNum> m) => {
  for (final id in c.resources.keys)
    if (m[id] case final v? when !v.isZero) id: v,
};
