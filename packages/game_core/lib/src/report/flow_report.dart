import 'dart:convert';
import 'dart:math' as math;

import '../commands/apply.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../sim/crew.dart';
import '../sim/engine.dart';
import '../sim/production.dart';
import '../state/game_state.dart';

/// How one building ran in the report's sample step.
final class BuildingStatus {
  /// Creates a building status.
  const BuildingStatus({
    required this.buildingId,
    required this.defId,
    required this.runFraction,
    required this.limitReason,
    required this.crew,
    required this.slots,
  });

  /// The building's id.
  final String buildingId;

  /// Id of its [BuildingDef].
  final String defId;

  /// Share of full input supply it ran at, in `[0, 1]`; warehouses run no
  /// recipe and stay at 0.
  final double runFraction;

  /// `noCrew`, `input:<resourceId>`, or null when nothing held it back.
  final String? limitReason;

  /// Crew assigned.
  final int crew;

  /// Most crew it can hold, capacity upgrades included.
  final int slots;
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

  /// Habitats and base crew support fewer crew than the faction has
  /// assigned, so every crewed building works below its crew.
  crewShortage,
}

/// A building, or for a crew shortage every crewed building, running below
/// full rate, and why.
final class Bottleneck {
  /// Creates a bottleneck.
  const Bottleneck({
    required this.kind,
    required this.bodyId,
    required this.buildingId,
    required this.resourceId,
    required this.runFraction,
    required this.message,
  });

  /// What holds it back.
  final BottleneckKind kind;

  /// Body the building stands on.
  final String bodyId;

  /// The held-back building; for [BottleneckKind.crewShortage], which slows
  /// every crewed building, the faction's first crewed building.
  final String buildingId;

  /// The input it is short of; null unless [kind] is [BottleneckKind.input].
  final String? resourceId;

  /// Share of full rate it ran at, in `[0, 1)`; for
  /// [BottleneckKind.crewShortage], the faction's crew efficiency.
  final double runFraction;

  /// Plain-English description using display names, such as
  /// "Smelter on Kora is running at 50%: not enough Iron Ore".
  final String message;
}

/// A faction's resource flows and bottlenecks, per second.
final class FlowReport {
  /// Creates a report; the collections are copied unmodifiable.
  FlowReport({
    required List<BodyFlow> bodies,
    required Map<String, BigNum> empireNet,
    required List<Bottleneck> bottlenecks,
  }) : bodies = List.unmodifiable(bodies),
       empireNet = Map.unmodifiable(empireNet),
       bottlenecks = List.unmodifiable(bottlenecks);

  /// Flows of each body the faction owns, in body order.
  final List<BodyFlow> bodies;

  /// Resource id to the change in the faction's holdings, cargo in flight
  /// counted as held, so moving goods between its own bodies nets to zero.
  final Map<String, BigNum> empireNet;

  /// Buildings held back, lowest run fraction first, then body and building
  /// order; a crew shortage, if any, comes before buildings at the same run
  /// fraction.
  final List<Bottleneck> bottlenecks;
}

/// Seconds of the sample step the rates are measured over.
const double _sampleSeconds = 1;

/// Reports [factionId]'s per-second flows and bottlenecks.
///
/// Rates come from one engine tick of 1 s run on a deep copy of [s], so [s]
/// is never changed. Net rates are stock differences across that tick;
/// produced and consumed rates are each building's [fullRateFlow] scaled
/// by the run fraction the tick settled on. All maps list resources in
/// content order and leave out zero rates. Throws if the faction does not
/// exist.
FlowReport buildFlowReport(GameState s, Content c, String factionId) {
  final copy = GameState.fromJson(
    jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
  );
  final owned = [
    for (final b in copy.bodies)
      if (b.ownerId == factionId) b,
  ];
  final stockBefore = [for (final b in owned) Map.of(b.stock)];
  final holdingsBefore = _holdings(copy, factionId);
  // The tick computes crew efficiency from the state it starts in, so the
  // crew shortage is read from that state too.
  final crewEff = crewEfficiency(copy, c, factionId);
  final crewNeck = _crewShortage(copy, c, factionId, owned, crewEff);

  GameEngine(c).tick(copy, _sampleSeconds);

  final bodies = <BodyFlow>[];
  final bottlenecks = <(int, Bottleneck)>[if (crewNeck != null) (0, crewNeck)];
  for (final (i, body) in owned.indexed) {
    final produced = <String, BigNum>{};
    final consumed = <String, BigNum>{};
    for (final b in body.buildings) {
      final flow = fullRateFlow(c, body, b, _sampleSeconds, crewEff);
      _addScaled(produced, flow.outputs, b.lastRunFraction);
      _addScaled(consumed, flow.inputs, b.lastRunFraction);
      final neck = _bottleneck(c, body, b);
      if (neck != null) bottlenecks.add((bottlenecks.length, neck));
    }
    bodies.add(
      BodyFlow(
        bodyId: body.id,
        producedPerSec: _ordered(c, produced),
        consumedPerSec: _ordered(c, consumed),
        netPerSec: _diff(c, body.stock, stockBefore[i]),
        wastedPerSec: _ordered(c, body.wastedThisStep),
        buildings: [
          for (final b in body.buildings)
            BuildingStatus(
              buildingId: b.id,
              defId: b.defId,
              runFraction: b.lastRunFraction,
              limitReason: b.lastLimitReason,
              crew: b.crew,
              slots: maxCrew(c.rules, c.buildings[b.defId]!, b),
            ),
        ],
      ),
    );
  }
  bottlenecks.sort((x, y) {
    final byRun = x.$2.runFraction.compareTo(y.$2.runFraction);
    return byRun != 0 ? byRun : x.$1.compareTo(y.$1);
  });
  return FlowReport(
    bodies: bodies,
    empireNet: _diff(c, _holdings(copy, factionId), holdingsBefore),
    bottlenecks: [for (final (_, b) in bottlenecks) b],
  );
}

/// The crew-shortage bottleneck of [factionId], whose bodies are [owned],
/// or null when its crew efficiency [crewEff] is 1.
///
/// [s] must be the state before the sample tick, so the crew counts match
/// [crewEff].
Bottleneck? _crewShortage(
  GameState s,
  Content c,
  String factionId,
  List<BodyState> owned,
  double crewEff,
) {
  if (crewEff >= 1) return null;
  var assigned = 0;
  (BodyState, BuildingState)? first;
  for (final body in owned) {
    for (final b in body.buildings) {
      if (b.crew == 0) continue;
      assigned += b.crew;
      first ??= (body, b);
    }
  }
  // Efficiency below 1 means some crew is assigned, so [first] is set.
  final (body, b) = first!;
  final supported = assigned + availableCrew(s, c, factionId);
  return Bottleneck(
    kind: BottleneckKind.crewShortage,
    bodyId: body.id,
    buildingId: b.id,
    resourceId: null,
    runFraction: crewEff,
    message:
        'Your empire is short on crew: habitats and base crew support '
        '$supported of $assigned assigned',
  );
}

/// The bottleneck building [b] on [body] shows after the sample step, or
/// null when it ran unhindered or runs no recipe.
Bottleneck? _bottleneck(Content c, BodyState body, BuildingState b) {
  final def = c.buildings[b.defId]!;
  final reason = b.lastLimitReason;
  if (def.crewSlots == 0 || reason == null) return null;
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

/// Adds `amount × fraction` for each entry of [amounts] into [into].
void _addScaled(
  Map<String, BigNum> into,
  Map<String, BigNum> amounts,
  double fraction,
) {
  if (fraction == 0) return;
  for (final MapEntry(key: id, value: v) in amounts.entries) {
    final scaled = v.mulDouble(fraction);
    if (!scaled.isZero) into[id] = (into[id] ?? const BigNum.zero()) + scaled;
  }
}

/// `after − before` per resource in content order, leaving out changes that
/// are zero or only float residue of the larger side.
Map<String, BigNum> _diff(
  Content c,
  Map<String, BigNum> after,
  Map<String, BigNum> before,
) {
  final out = <String, BigNum>{};
  for (final id in c.resources.keys) {
    final a = after[id] ?? const BigNum.zero();
    final b = before[id] ?? const BigNum.zero();
    final d = a - b;
    final residue = a.max(b).mulDouble(1e-12);
    if (d > residue || d < -residue) out[id] = d;
  }
  return out;
}

/// The non-zero entries of [m] in content resource order.
Map<String, BigNum> _ordered(Content c, Map<String, BigNum> m) => {
  for (final id in c.resources.keys)
    if (m[id] case final v? when !v.isZero) id: v,
};
