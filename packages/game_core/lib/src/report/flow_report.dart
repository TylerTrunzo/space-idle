import 'dart:math' as math;

import '../commands/apply.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../num/change.dart';
import '../sim/crew.dart';
import '../sim/logistics.dart';
import '../sim/market.dart';
import '../sim/production.dart';
import '../state/game_state.dart';

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
  /// [BottleneckKind.crewShortage], which is faction-wide.
  final String? bodyId;

  /// The held-back building; null for [BottleneckKind.crewShortage] and
  /// [BottleneckKind.storageFull].
  final String? buildingId;

  /// The input a building is short of ([BottleneckKind.input]) or the
  /// resource being wasted ([BottleneckKind.storageFull]); otherwise null.
  final String? resourceId;

  /// Share of full rate achieved, in `[0, 1)`: a building's run fraction,
  /// for [BottleneckKind.understaffed] its crew over its base slots;
  /// for [BottleneckKind.crewShortage] the faction's crew efficiency; for
  /// [BottleneckKind.storageFull] the share of the body's own output of the
  /// resource that it kept (0 when only arriving cargo was wasted).
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
  /// building does not make. Null for the other kinds.
  final BigNum? lostCreditsPerHour;

  /// [kind], [bodyId], [buildingId] and [resourceId] as one key, as in
  /// [SeenBottleneck.key].
  String get key => bottleneckKey(kind.name, bodyId, buildingId, resourceId);

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
  FlowReport({
    required List<BodyFlow> bodies,
    required Map<String, BigNum> empireNet,
    required this.creditsPerSec,
    required List<Bottleneck> bottlenecks,
  }) : bodies = List.unmodifiable(bodies),
       empireNet = Map.unmodifiable(empireNet),
       bottlenecks = List.unmodifiable(bottlenecks);

  /// Flows of each body the faction owns, in body order.
  final List<BodyFlow> bodies;

  /// Resource id to the change in the faction's holdings, cargo in flight
  /// counted as held, so moving goods between its own bodies nets to zero.
  final Map<String, BigNum> empireNet;

  /// Credits the faction earns per second in steady state: the auto-sale
  /// revenue of what the sample step made and landed, not of stock built
  /// up before it (see [buildFlowReport]); commands are not part of it.
  final BigNum creditsPerSec;

  /// Everything held back, lowest run fraction first, then in report order:
  /// a crew shortage first, then each body's buildings in order followed by
  /// its full stores in content resource order.
  final List<Bottleneck> bottlenecks;
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
/// So [FlowReport.creditsPerSec] is the auto-sale revenue of the step's
/// net production, and over a stable stretch of play matches the credits
/// actually earned per second. Net rates are stock differences across the
/// step; produced and consumed rates are each building's [fullRateFlow]
/// scaled by the run fraction the step settled on. All maps list
/// resources in content order and leave out zero rates. Throws if the
/// faction does not exist.
FlowReport buildFlowReport(GameState s, Content c, String factionId) {
  // First pass: what each route sends in a step from this state.
  final probe = s.copy();
  deliverShipments(probe);
  stepProduction(probe, c, _sampleSeconds);
  final routeFlow = sendCargo(probe, c, _sampleSeconds);

  final copy = s.copy()..shipments.clear();
  final owned = [
    for (final b in copy.bodies)
      if (b.ownerId == factionId) b,
  ];
  final stockBefore = [for (final b in owned) Map.of(b.stock)];
  final atStart = {for (final b in copy.bodies) b.id: Map.of(b.stock)};
  final holdingsBefore = _holdings(copy, factionId);
  final faction = copy.faction(factionId);
  final creditsBefore = faction.credits;
  // The tick computes crew efficiency from the state it starts in, so the
  // crew shortage is read from that state too.
  final crewEff = crewEfficiency(copy, c, factionId);
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
  stepProduction(copy, c, _sampleSeconds);
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
  final bottlenecks = <(int, Bottleneck)>[if (crewNeck != null) (0, crewNeck)];
  void addNeck(Bottleneck? neck) {
    if (neck != null) bottlenecks.add((bottlenecks.length, neck));
  }

  for (final (i, body) in owned.indexed) {
    final produced = <String, BigNum>{};
    final consumed = <String, BigNum>{};
    final statuses = <BuildingStatus>[];
    for (final b in body.buildings) {
      final def = c.buildings[b.defId]!;
      final flow = fullRateFlow(c, body, b, _sampleSeconds, crewEff);
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
              : b.lastRunFraction * b.crew / def.crewSlots * crewEff,
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
  bottlenecks.sort((x, y) {
    final byRun = x.$2.runFraction.compareTo(y.$2.runFraction);
    return byRun != 0 ? byRun : x.$1.compareTo(y.$1);
  });
  final since = {
    for (final seen in s.faction(factionId).seenBottlenecks)
      seen.key: seen.firstSeenAt,
  };
  return FlowReport(
    bodies: bodies,
    empireNet: _diff(c, _holdings(copy, factionId), holdingsBefore),
    creditsPerSec: faction.credits - creditsBefore,
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

    if (crewEfficiency(s, c, f.id) < 1) {
      see(BottleneckKind.crewShortage.name, null, null, null);
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
  if (crewEff >= 1) return null;
  final t = crewTotals(s, c, factionId);
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
