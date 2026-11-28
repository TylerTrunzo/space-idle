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
import '../sim/step_cache.dart';
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

  /// Share of full input supply it ran at, in `[0, 1]`; null for a
  /// building that runs no recipe (a warehouse such as a depot).
  final double? runFraction;

  /// Its actual output as a share of what it makes with its base crew
  /// slots full, every input supplied and the faction fully housed:
  /// `runFraction × crew / base slots × crew efficiency`.
  ///
  /// Shows staffing and housing as well as supply: a fully supplied
  /// building with half its slots crewed is at 0.5. Above 1 when capacity
  /// upgrades hold crew beyond the base slots; 0 for unstaffed buildings;
  /// null, as [runFraction], for one that runs no recipe. Speed upgrades
  /// do not count; see [outputsPerSec] for the rate.
  final double? effectiveFraction;

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

  /// Auto-delivery hands a megaproject a good the faction auto-sells, a
  /// tenth or more of what would otherwise sell of it
  /// ([Bottleneck.shareOfSales]): income it does not earn.
  megaprojectDiversion,

  /// A megaproject fed goods on its own still owes a good, and a body holds
  /// some that auto-delivery leaves there only because of its auto-sell
  /// rule's `keepAtLeast` ([Bottleneck.heldByKeep]).
  keepBlocksDelivery,

  /// A megaproject fed goods on its own still owes a good, and an open
  /// contract holds some of it on the faction's bodies, which auto-delivery
  /// leaves there for the contract ([Bottleneck.contractId],
  /// [Bottleneck.heldForContract]). New orders never ask for such a good,
  /// so this is one posted before feeding started. A kind of its own, not a
  /// cause of [keepBlocksDelivery]: it is faction-wide (no body), names a
  /// contract the player can deliver or discard rather than a rule to
  /// change, and is tracked over time by that contract.
  contractBlocksDelivery,

  /// A building is short of one of its inputs ([BottleneckKind.input]),
  /// the store it draws from is fed by a route, and that route is held
  /// back by something other than what its source has to send
  /// ([Bottleneck.routeId], [Bottleneck.binding]): its rate, its ships, its
  /// destination's room or its stop level. The same shortage as an input
  /// one, with its cause named: it is tracked and grouped under the input
  /// kind's keys ([Bottleneck.key], [Bottleneck.groupKey]).
  routeLimited,
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
    this.message = '',
    this.firstSeenAt = 0,
    this.lostCreditsPerHour,
    this.fromAbsence = false,
    this.count = 1,
    this.buildingIds = const [],
    this.megaprojectId,
    this.shareOfSales,
    this.heldByKeep,
    this.routeId,
    this.binding,
    this.routePerSec,
    this.contractId,
    this.heldForContract,
  });

  /// What holds it back.
  final BottleneckKind kind;

  /// Body the building or store is on, or that holds the good for
  /// [BottleneckKind.keepBlocksDelivery]; null for
  /// [BottleneckKind.crewShortage], [BottleneckKind.noSales],
  /// [BottleneckKind.megaprojectDiversion] and
  /// [BottleneckKind.contractBlocksDelivery], which are faction-wide.
  final String? bodyId;

  /// The held-back building; null for the kinds about no one building, and
  /// for a group of more than one ([groupBottlenecks]).
  final String? buildingId;

  /// The input a building is short of ([BottleneckKind.input]), the
  /// resource being wasted ([BottleneckKind.storageFull]), or the good a
  /// megaproject takes or is kept from ([BottleneckKind.megaprojectDiversion],
  /// [BottleneckKind.keepBlocksDelivery],
  /// [BottleneckKind.contractBlocksDelivery]); otherwise null.
  final String? resourceId;

  /// Buildings it stands for, at least 1: more than one once
  /// [groupBottlenecks] puts together the buildings held back by the same
  /// cause on one body; 1 for the kinds about no building.
  final int count;

  /// Ids of the buildings it stands for, in report order; empty for the
  /// kinds about no building.
  final List<String> buildingIds;

  /// The megaproject that takes the good
  /// ([BottleneckKind.megaprojectDiversion]) or is kept from it
  /// ([BottleneckKind.keepBlocksDelivery],
  /// [BottleneckKind.contractBlocksDelivery]); otherwise null.
  final String? megaprojectId;

  /// For [BottleneckKind.megaprojectDiversion], the share of what would
  /// sell of the good that goes to the megaproject instead, in
  /// `[0.1, 1]`: what it takes a second over that plus what auto-sell
  /// sells of it, both valued at current prices; otherwise null.
  final double? shareOfSales;

  /// For [BottleneckKind.keepBlocksDelivery], the whole units on the body
  /// that auto-delivery would hand over, up to what is owed, but for the
  /// rule's `keepAtLeast`; otherwise null.
  final BigNum? heldByKeep;

  /// For [BottleneckKind.contractBlocksDelivery], the open contract that
  /// holds the good; otherwise null.
  final String? contractId;

  /// For [BottleneckKind.contractBlocksDelivery], the whole units on the
  /// faction's bodies, summed, that auto-delivery would hand over, up to
  /// what is owed, but for [contractId]; otherwise null.
  final BigNum? heldForContract;

  /// For [BottleneckKind.routeLimited], the route into the store that
  /// holds it back; otherwise null.
  final String? routeId;

  /// For [BottleneckKind.routeLimited], what holds [routeId] back
  /// ([routeThroughput]); otherwise null.
  final RouteLimit? binding;

  /// For [BottleneckKind.routeLimited], the units a second [routeId] can
  /// carry at most ([routeThroughput]); otherwise null.
  final double? routePerSec;

  /// Share of full rate achieved, in `[0, 1)`: a building's run fraction,
  /// for [BottleneckKind.understaffed] its crew over its base slots (a
  /// group's lowest); for [BottleneckKind.crewShortage] the faction's crew
  /// efficiency; for [BottleneckKind.storageFull] the share of the body's
  /// own output of the resource that it kept (0 when only arriving cargo
  /// was wasted, or in an away summary when only the absence wasted it);
  /// for [BottleneckKind.megaprojectDiversion] the share that still sells,
  /// `1 − shareOfSales`; 0 for [BottleneckKind.noSales],
  /// [BottleneckKind.keepBlocksDelivery] and
  /// [BottleneckKind.contractBlocksDelivery].
  final double runFraction;

  /// Plain-English description using display names, such as
  /// "Smelter on Kora is running at 50%: not enough Iron Ore", for the
  /// kinds of stage 1.6 and before; empty for
  /// [BottleneckKind.megaprojectDiversion],
  /// [BottleneckKind.keepBlocksDelivery],
  /// [BottleneckKind.contractBlocksDelivery] and a [fromAbsence] entry, whose
  /// text a display builds from the typed fields. (Stage 2 builds every
  /// kind's text from them.)
  final String message;

  /// Whether an away summary shows this [BottleneckKind.storageFull] only
  /// for what the storage cap cut while the player was away: its store is
  /// not full now, in the report on return. False otherwise.
  final bool fromAbsence;

  /// Game time in seconds since which the faction has had it without a
  /// break, from [FactionState.seenBottlenecks]; the report's own time when
  /// it is new.
  final double firstSeenAt;

  /// Estimated credits it costs an hour, at current market prices, where
  /// that can be worked out: for [BottleneckKind.storageFull] the wasted
  /// units' value (in an away summary, the larger of that and what the
  /// absence wasted there an hour); for [BottleneckKind.input] the value
  /// of the output the building does not make; for
  /// [BottleneckKind.noSales] the value of the faction's net production of
  /// goods that sell; for [BottleneckKind.crewShortage] what full staffing
  /// would add to the faction's net production, more output less the
  /// extra inputs it draws, leaving out output a full store would cut
  /// (zero when none of its crewed buildings runs); for
  /// [BottleneckKind.megaprojectDiversion] what the goods the megaproject
  /// takes would sell for. The input figure is gross: the starved
  /// building's lost output, not net of the inputs it would use. A group's
  /// is the sum of its members'. Null for the other kinds.
  final BigNum? lostCreditsPerHour;

  /// Restores a bottleneck written by [toJson].
  factory Bottleneck.fromJson(Map<String, Object?> j) => Bottleneck(
    kind: BottleneckKind.values.byName(j['kind']! as String),
    bodyId: j['bodyId'] as String?,
    buildingId: j['buildingId'] as String?,
    resourceId: j['resourceId'] as String?,
    runFraction: (j['runFraction']! as num).toDouble(),
    message: (j['message'] as String?) ?? '',
    firstSeenAt: (j['firstSeenAt']! as num).toDouble(),
    lostCreditsPerHour: switch (j['lostCreditsPerHour']) {
      final String v => BigNum.fromJson(v),
      _ => null,
    },
    // Absent in bottlenecks from before grouping: one building or none.
    fromAbsence: (j['fromAbsence'] as bool?) ?? false,
    count: (j['count'] as int?) ?? 1,
    buildingIds: switch (j['buildingIds']) {
      final List<Object?> ids => ids.cast<String>(),
      _ => [?j['buildingId'] as String?],
    },
    megaprojectId: j['megaprojectId'] as String?,
    shareOfSales: (j['shareOfSales'] as num?)?.toDouble(),
    heldByKeep: switch (j['heldByKeep']) {
      final String v => BigNum.fromJson(v),
      _ => null,
    },
    routeId: j['routeId'] as String?,
    binding: switch (j['binding']) {
      final String v => RouteLimit.values.byName(v),
      _ => null,
    },
    routePerSec: (j['routePerSec'] as num?)?.toDouble(),
    contractId: j['contractId'] as String?,
    heldForContract: switch (j['heldForContract']) {
      final String v => BigNum.fromJson(v),
      _ => null,
    },
  );

  /// [kind], [bodyId], [buildingId] and [resourceId] as one key, as in
  /// [SeenBottleneck.key]; a [BottleneckKind.routeLimited] keys as the
  /// input shortage it is, so it keeps the time it was first seen however
  /// its route reads. A [BottleneckKind.contractBlocksDelivery] keys by its
  /// contract where a building would be, so it is tracked per contract.
  String get key => bottleneckKey(
    _trackedKind.name,
    bodyId,
    kind == BottleneckKind.contractBlocksDelivery ? contractId : buildingId,
    resourceId,
  );

  /// [kind] as it is tracked over time: [BottleneckKind.input] for a
  /// [BottleneckKind.routeLimited].
  BottleneckKind get _trackedKind =>
      kind == BottleneckKind.routeLimited ? BottleneckKind.input : kind;

  /// Its cause as one key: [kind], [bodyId], [resourceId] and
  /// [megaprojectId], but not the building. [groupBottlenecks] puts those
  /// with the same one together, and an away summary matches a group
  /// before and after the absence by it ([OfflineSummary.ongoingFor]).
  String get groupKey =>
      bottleneckKey(_trackedKind.name, bodyId, megaprojectId, resourceId);

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
    if (fromAbsence) 'fromAbsence': true,
    'count': count,
    if (buildingIds.isNotEmpty) 'buildingIds': buildingIds,
    'megaprojectId': ?megaprojectId,
    'shareOfSales': ?shareOfSales,
    'heldByKeep': ?heldByKeep?.toJson(),
    'routeId': ?routeId,
    'binding': ?binding?.name,
    'routePerSec': ?routePerSec,
    'contractId': ?contractId,
    'heldForContract': ?heldForContract?.toJson(),
  };

  /// This bottleneck with [firstSeenAt] and [lostCreditsPerHour] replaced
  /// where given.
  Bottleneck copyWith({double? firstSeenAt, BigNum? lostCreditsPerHour}) =>
      Bottleneck(
        kind: kind,
        bodyId: bodyId,
        buildingId: buildingId,
        resourceId: resourceId,
        runFraction: runFraction,
        message: message,
        firstSeenAt: firstSeenAt ?? this.firstSeenAt,
        lostCreditsPerHour: lostCreditsPerHour ?? this.lostCreditsPerHour,
        fromAbsence: fromAbsence,
        count: count,
        buildingIds: buildingIds,
        megaprojectId: megaprojectId,
        shareOfSales: shareOfSales,
        heldByKeep: heldByKeep,
        routeId: routeId,
        binding: binding,
        routePerSec: routePerSec,
        contractId: contractId,
        heldForContract: heldForContract,
      );

  /// This [BottleneckKind.input] as the [BottleneckKind.routeLimited] that
  /// route [routeId], held back as [t] says, makes it.
  Bottleneck _routeLimited(String routeId, RouteThroughput t) => Bottleneck(
    kind: BottleneckKind.routeLimited,
    bodyId: bodyId,
    buildingId: buildingId,
    resourceId: resourceId,
    runFraction: runFraction,
    firstSeenAt: firstSeenAt,
    lostCreditsPerHour: lostCreditsPerHour,
    fromAbsence: fromAbsence,
    count: count,
    buildingIds: buildingIds,
    routeId: routeId,
    binding: t.binding,
    routePerSec: t.perSec,
  );

  Bottleneck _with({double? firstSeenAt, BigNum? lostCreditsPerHour}) =>
      copyWith(
        firstSeenAt: firstSeenAt,
        lostCreditsPerHour: lostCreditsPerHour,
      );
}

/// [necks] put together by cause ([Bottleneck.groupKey]: kind, body,
/// resource and megaproject), each group where its first member was:
/// [Bottleneck.count] and [Bottleneck.buildingIds] add up, as do the
/// credits lost an hour (null only when every member's is), the run
/// fraction is the lowest, the time first seen the earliest, and
/// [Bottleneck.heldByKeep] and [Bottleneck.shareOfSales] the sum and the
/// largest. A group of one is its member as it was; a larger group names
/// no one building ([Bottleneck.buildingId] null) and keeps its first
/// member's message, which a display can rebuild from the typed fields.
///
/// So 17 docks on one body short of the same input are one entry whose
/// loss is the 17 losses summed, and a cause that costs more on its own
/// is not hidden behind them.
List<Bottleneck> groupBottlenecks(List<Bottleneck> necks) {
  final groups = <String, List<Bottleneck>>{};
  for (final b in necks) {
    (groups[b.groupKey] ??= []).add(b);
  }
  return [
    for (final members in groups.values)
      if (members.length == 1) members.single else _merge(members),
  ];
}

/// [members], two or more with one [Bottleneck.groupKey], as one entry.
Bottleneck _merge(List<Bottleneck> members) {
  final first = members.first;
  BigNum? lost;
  var run = first.runFraction;
  var since = first.firstSeenAt;
  var count = 0;
  BigNum? held;
  double? share;
  for (final b in members) {
    if (b.lostCreditsPerHour case final v?) {
      lost = (lost ?? const BigNum.zero()) + v;
    }
    run = math.min(run, b.runFraction);
    since = math.min(since, b.firstSeenAt);
    count += b.count;
    if (b.heldByKeep case final v?) {
      held = (held ?? const BigNum.zero()) + v;
    }
    if (b.shareOfSales case final v?) share = math.max(share ?? v, v);
  }
  return Bottleneck(
    kind: first.kind,
    bodyId: first.bodyId,
    buildingId: null,
    resourceId: first.resourceId,
    runFraction: run,
    message: first.message,
    firstSeenAt: since,
    lostCreditsPerHour: lost,
    count: count,
    buildingIds: [for (final b in members) ...b.buildingIds],
    megaprojectId: first.megaprojectId,
    shareOfSales: share,
    heldByKeep: held,
    routeId: first.routeId,
    binding: first.binding,
    routePerSec: first.routePerSec,
    contractId: first.contractId,
    heldForContract: first.heldForContract,
  );
}

/// A faction's resource flows and bottlenecks, per second.
final class FlowReport {
  /// Creates a report; the collections are copied unmodifiable.
  ///
  /// [income] is called the first time [FlowReport.creditsPerSec] or
  /// what goes to megaprojects is read, and only then; [steady] the first
  /// time a steady rate is read: resource id to what the faction's
  /// buildings make, and resource id to what is left over, with every
  /// flow steady. [prices], resource id to price, values the goods
  /// auto-delivered; it need list only those.
  FlowReport({
    required List<BodyFlow> bodies,
    required Map<String, BigNum> empireNet,
    required SteadyIncome Function() income,
    required (Map<String, BigNum>, Map<String, BigNum>) Function() steady,
    required List<Bottleneck> bottlenecks,
    Map<String, BigNum> prices = const {},
    List<Bottleneck> keepBlocks = const [],
    List<Bottleneck> contractBlocks = const [],
    List<Bottleneck> Function(SteadyIncome income)? diversions,
  }) : _income = income,
       _steady = steady,
       _keepBlocks = List.unmodifiable(keepBlocks),
       contractBlocks = List.unmodifiable(contractBlocks),
       _diversions = diversions,
       _prices = Map.unmodifiable(prices),
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
  /// valued at the prices the market settles at over the next hours, and
  /// no more than a short run of play earns (`saleRevenuePerSec`).
  /// Stock drawn down by consumers, or sold from above an auto-sell keep,
  /// does not count; commands (sales, contracts) are not part of it.
  ///
  /// Worked out the first time it is read, from the state the report was
  /// built from: it plays a copy of it forward, which costs several ticks
  /// (a reading of the same state again reuses it). Until then the report
  /// keeps two copies of that state; it drops them once this is read.
  ///
  /// It is what sales earn, before auto-delivery pays any of it to
  /// megaprojects; goods auto-delivery takes never sell, so they are not
  /// in it. See [autoDeliveredPerSec].
  BigNum get creditsPerSec => _measured.creditsPerSec;

  /// Megaproject id to what the faction's auto-delivery hands it a second
  /// in the same short run of play as [creditsPerSec], by cost key
  /// (`credits` or a resource id); empty when it feeds none.
  ///
  /// Credits paid in come out of what [creditsPerSec] earns: summed over
  /// the megaprojects they are never more than it, and income less them
  /// is what the faction keeps a second. So the two are not to be added;
  /// the app can show "income 78/s, 60/s of it to projects". Goods are
  /// what goes in instead of being sold, at no cost to [creditsPerSec].
  /// The run keeps the open contracts, so goods a contract still needs do
  /// not go in, as in play.
  Map<String, Map<String, BigNum>> get autoDeliveredPerSec =>
      _measured.deliveredPerSec;

  /// What [autoDeliveredPerSec] is worth a second, every megaproject
  /// together: the credits, plus each good at its market price as the
  /// report was built.
  late final BigNum autoDeliveredValuePerSec = () {
    var total = const BigNum.zero();
    for (final got in autoDeliveredPerSec.values) {
      for (final MapEntry(key: id, value: v) in got.entries) {
        total =
            total +
            (id == 'credits' ? v : v * (_prices[id] ?? const BigNum.zero()));
      }
    }
    return total;
  }();

  late final SteadyIncome _measured = _income();

  final SteadyIncome Function() _income;

  final Map<String, BigNum> _prices;

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
  /// its full stores in content resource order. One entry per building;
  /// [groupedBottlenecks] has them by cause, with the megaproject kinds.
  final List<Bottleneck> bottlenecks;

  final List<Bottleneck> _keepBlocks;

  /// The open contracts that hold goods a megaproject the faction feeds on
  /// its own still owes ([BottleneckKind.contractBlocksDelivery]): for each
  /// such megaproject, in content order, each good it owes in cost order
  /// that a contract holds. Also in [groupedBottlenecks]; read here, it
  /// costs no short run of play.
  final List<Bottleneck> contractBlocks;

  final List<Bottleneck> Function(SteadyIncome income)? _diversions;

  /// [bottlenecks] grouped by cause ([groupBottlenecks]), in their order,
  /// then the goods a keep holds back from a megaproject that still owes
  /// them ([BottleneckKind.keepBlocksDelivery]), megaprojects in content
  /// order, then those a contract holds back ([contractBlocks]), then the
  /// goods auto-delivery takes from sales
  /// ([BottleneckKind.megaprojectDiversion]), as [autoDeliveredPerSec]
  /// lists them.
  ///
  /// The diversions come from the same short run of play as
  /// [creditsPerSec], so the first read of this works that out too. Of the
  /// megaproject kinds, only [BottleneckKind.contractBlocksDelivery] is
  /// tracked over time (by its contract); the others'
  /// [Bottleneck.firstSeenAt] is the report's own time.
  late final List<Bottleneck> groupedBottlenecks = [
    ...groupBottlenecks(bottlenecks),
    ..._keepBlocks,
    ...contractBlocks,
    ...?_diversions?.call(_measured),
  ];

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

/// Game seconds of a full step, the engine's catch-up step: the window
/// over which a building fed by cargo lots is given its share of them.
const double _fullStepSeconds = 60;

/// [sent], route id to what each route sent in the probe step from [s],
/// with each route that has a stop level and nothing in flight held to
/// what it can carry ([routeThroughput]) over that step. Such a route
/// refills in the probe step what its store just used, which is more than
/// it keeps sending when its store's room holds it back: so a store fed a
/// cap's worth a trip reads the same with its lot just landed as with the
/// lot on its way. [throughput] gives [routeThroughputs] of [s], worked
/// out once per report and only when asked for.
Map<String, BigNum> _steadySends(
  GameState s,
  Map<String, BigNum> sent,
  Map<String, RouteThroughput> Function() throughput,
) {
  final out = Map.of(sent);
  for (final r in s.routes) {
    final v = sent[r.id];
    if (v == null || r.stopAtDestination == null) continue;
    if (s.shipments.any((sh) => sh.routeId == r.id)) continue;
    final most = BigNum.from(throughput()[r.id]!.perSec * _sampleSeconds);
    if (v > most) out[r.id] = most;
  }
  return out;
}

/// Body id to resource id to the units a second cargo brings [factionId]'s
/// bodies on average, for each store its routes or shipments feed: the
/// larger of two readings.
///
/// - What is on its way and there, spread over the trip: each route's
///   cargo in flight over its trip ([travelSeconds]), as a route's
///   pipeline holds one trip of what it delivers, plus the store's stock
///   and shipments of no route over the longest of those trips (a full
///   step when there is none). It does not jump as a lot lands: the lot
///   moves from in flight into the store. A store whose stock and cargo
///   together never pass its cap reads one cap's worth a trip, either
///   side of a landing.
/// - What the routes send: each route without a stop level, or with
///   nothing in flight, at the rate the probe step saw it send
///   ([routeFlow], route id to units sent in [_sampleSeconds]); each with
///   a stop level and lots in flight by those lots over its trip, as what
///   it sends in a second swings with the room its store has just then.
///   This one is right for a route its rate or its source holds back, as
///   a step shorter than its lots can leave the first reading short.
///
/// A store holding more than its buildings use at full supply over the
/// longest trip is not waiting on its lots: its stock lasts until the next
/// ones land, so the first reading counts it in full, over a full step.
Map<String, Map<String, BigNum>> _cargoSupply(
  GameState s,
  Content c,
  String factionId,
  Map<String, BigNum> routeFlow,
) {
  final routes = {
    for (final r in s.routes)
      if (r.ownerId == factionId &&
          s.body(r.toBodyId).ownerId == factionId &&
          s.body(r.fromBodyId).ownerId == factionId)
        r.id: r,
  };
  final inFlight = <String, BigNum>{};
  // Body id to resource id to cargo in flight of no route.
  final loose = <String, Map<String, BigNum>>{};
  void add(
    Map<String, Map<String, BigNum>> into,
    String b,
    String id,
    BigNum v,
  ) {
    final got = into[b] ??= {};
    got[id] = (got[id] ?? const BigNum.zero()) + v;
  }

  for (final sh in s.shipments) {
    if (sh.ownerId != factionId) continue;
    if (s.body(sh.toBodyId).ownerId != factionId) continue;
    if (routes.containsKey(sh.routeId)) {
      inFlight[sh.routeId] =
          (inFlight[sh.routeId] ?? const BigNum.zero()) + sh.amount;
    } else {
      add(loose, sh.toBodyId, sh.resourceId, sh.amount);
    }
  }
  // Body id to resource id to the two readings' route parts, and the
  // longest trip into the store.
  final piped = <String, Map<String, BigNum>>{};
  final sending = <String, Map<String, BigNum>>{};
  final trips = <String, Map<String, double>>{};
  for (final r in routes.values) {
    final trip = travelSeconds(s, c, s.body(r.fromBodyId), s.body(r.toBodyId));
    final on = trips[r.toBodyId] ??= {};
    on[r.resourceId] = math.max(on[r.resourceId] ?? 0, trip);
    final lots = inFlight[r.id] ?? const BigNum.zero();
    final pipe = lots.mulDouble(1 / trip);
    add(piped, r.toBodyId, r.resourceId, pipe);
    add(
      sending,
      r.toBodyId,
      r.resourceId,
      r.stopAtDestination != null && lots > const BigNum.zero()
          ? pipe
          : (routeFlow[r.id] ?? const BigNum.zero()).mulDouble(
              1 / _sampleSeconds,
            ),
    );
  }
  for (final MapEntry(key: b, value: got) in loose.entries) {
    for (final id in got.keys) {
      add(piped, b, id, const BigNum.zero());
    }
  }
  final cache = StepCache(s, c);
  BigNum perSec(String b, String id, BigNum pipe) {
    final body = s.body(b);
    final trip = trips[b]?[id] ?? _fullStepSeconds;
    final held = body.stock[id] ?? const BigNum.zero();
    final loaded = loose[b]?[id] ?? const BigNum.zero();
    final stocked =
        held > const BigNum.zero() &&
            held > (cache.use(body, trip)[id] ?? const BigNum.zero())
        ? held.mulDouble(1 / _fullStepSeconds) + loaded.mulDouble(1 / trip)
        : (held + loaded).mulDouble(1 / trip);
    return (pipe + stocked).max(sending[b]?[id] ?? const BigNum.zero());
  }

  return {
    for (final MapEntry(key: b, value: got) in piped.entries)
      b: {
        for (final MapEntry(key: id, value: v) in got.entries)
          id: perSec(b, id, v),
      },
  };
}

/// Building id to the share of full rate a full step from [s] runs it at,
/// for [factionId]'s buildings that use an input a store [supply] lists
/// ([_cargoSupply]) cannot keep up with, and the input that holds each
/// back most; at crew efficiency [crewEff] when given, else the
/// faction's own now.
///
/// Over a full step a store's buildings share what it gets a second and
/// what the body itself makes of the input (at its makers' last run
/// fractions), in proportion to what they use at full rate: each runs at
/// that over their use, where it is below 1. A store fed by lots holds a
/// lot just after one lands and nothing just before: a short step sees
/// either, a full one the share of the lots its buildings get. So the
/// sample step's buildings run at no more than this ([stepProduction]'s
/// `runCaps`), and a report a few seconds before a lot lands reads as one
/// a few seconds after.
///
/// Nor at more than a full step of play gives them, played on a copy of
/// [s] whose stores hold a full step of that supply: play shares an input
/// out by recipe depth, shallow first ([stepProduction]), so a deeper
/// building can get none of a short input another building on its body
/// uses first, whatever its part of the store's use.
Map<String, RunCap> _fullStepCaps(
  GameState s,
  Content c,
  String factionId,
  Map<String, Map<String, BigNum>> supply,
  double? crewEff,
) {
  if (supply.isEmpty) return const {};
  final eff = crewEff ?? crewEfficiency(s, c, factionId);
  final bonuses = bonusesFor(s, c, factionId);
  final caps = <String, RunCap>{};
  for (final MapEntry(key: id, value: got) in supply.entries) {
    final body = s.body(id);
    final use = <String, BigNum>{};
    final made = <String, BigNum>{};
    for (final b in body.buildings) {
      final flow = fullRateFlow(c, body, b, 1, eff, bonuses: bonuses);
      for (final res in got.keys) {
        if (flow.inputs[res] case final v?) {
          use[res] = (use[res] ?? const BigNum.zero()) + v;
        }
        if (flow.outputs[res] case final v? when b.lastRunFraction > 0) {
          made[res] =
              (made[res] ?? const BigNum.zero()) +
              v.mulDouble(b.lastRunFraction);
        }
      }
    }
    // Share of its full-rate use each input short here gets.
    final share = <String, double>{
      for (final MapEntry(key: res, value: wanted) in use.entries)
        if (wanted > const BigNum.zero())
          if (((got[res]! + (made[res] ?? const BigNum.zero())) / wanted)
                  .toDouble()
              case final r when r < 1)
            res: math.max(0, r),
    };
    if (share.isEmpty) continue;
    for (final b in body.buildings) {
      if (!runsRecipe(c.buildings[b.defId]!)) continue;
      RunCap? cap;
      for (final res in c.buildings[b.defId]!.inputs.keys) {
        final r = share[res];
        if (r != null && (cap == null || r < cap.fraction)) {
          cap = (fraction: r, inputId: res);
        }
      }
      if (cap != null) caps[b.id] = cap;
    }
  }
  if (caps.isEmpty) return caps;
  // That share assumes every building of a store gets its part; play
  // runs the shallower recipes first ([stepProduction]), which can take a
  // short input before the deeper ones see any. So a full step of play is
  // run on a copy, its stores holding a full step of their supply, and no
  // building fed by cargo runs faster than it ran there.
  final step = s.copy()..shipments.clear();
  for (final MapEntry(key: id, value: got) in supply.entries) {
    final stock = step.body(id).stock;
    for (final MapEntry(key: res, value: v) in got.entries) {
      stock[res] = v.mulDouble(_fullStepSeconds);
    }
  }
  stepProduction(
    step,
    c,
    _fullStepSeconds,
    crewEfficiencyOf: crewEff == null ? const {} : {factionId: crewEff},
  );
  for (final MapEntry(key: id, value: got) in supply.entries) {
    for (final b in step.body(id).buildings) {
      final def = c.buildings[b.defId]!;
      if (!runsRecipe(def) || !def.inputs.keys.any(got.containsKey)) continue;
      final limit = b.lastLimitReason;
      if (limit == null || !limit.startsWith('input:')) continue;
      final now = caps[b.id];
      if (now == null || b.lastRunFraction < now.fraction) {
        caps[b.id] = (
          fraction: b.lastRunFraction,
          inputId: limit.substring('input:'.length),
        );
      }
    }
  }
  return caps;
}

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
///   out as such. A building held back by an input cargo brings runs at
///   no more than the share a full 60 s step of its store's average
///   supply gives it ([_cargoSupply]: what is there and on its way, spread
///   over the trip), with a second of that supply there for it; so a
///   report just before a lot lands reads as one just after, and neither
///   shows a store that refills each minute as empty or full.
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
  // Every route's throughput, worked out once and only if needed.
  Map<String, RouteThroughput>? throughput;
  Map<String, RouteThroughput> throughputs() =>
      throughput ??= routeThroughputs(s, c);
  final routeFlow = _steadySends(
    s,
    sendCargo(probe, c, _sampleSeconds),
    throughputs,
  );
  // Cargo lands in lots, so a store a route feeds can be empty a second
  // before a lot lands and full a second after: the sample step runs such
  // buildings at the share a full step of their average supply gives them.
  final supply = _cargoSupply(s, c, factionId, routeFlow);
  Map<String, RunCap> capsAt([double? crewEff]) =>
      _fullStepCaps(s, c, factionId, supply, crewEff);

  final copy = s.copy()..shipments.clear();
  // A second of that supply is there for the sample step's buildings, as
  // held already (so it nets to zero) and kept from auto-sell; only what
  // fits below the cap, so none is wasted.
  for (final MapEntry(key: id, value: got) in supply.entries) {
    final body = copy.body(id);
    final cap = storageCap(copy, c, body);
    for (final MapEntry(key: res, value: v) in got.entries) {
      final held = body.stock[res] ?? const BigNum.zero();
      final room = cap - held;
      final more = v.mulDouble(_sampleSeconds).min(room);
      if (more > const BigNum.zero()) body.stock[res] = held + more;
    }
  }
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
  stepProduction(copy, c, _sampleSeconds, runCaps: capsAt());
  final crewLost = staffed == null
      ? null
      : _staffingGain(s, c, factionId, staffed, copy, capsAt(1));
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

  final causes = _RouteCauses(s, c, factionId, throughputs);
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
            ? causes.explain(
                neck!._with(
                  lostCreditsPerHour: _valuePerHour(
                    s,
                    c,
                    factionId,
                    _scaled(flow.outputs, 1 - b.lastRunFraction),
                  ),
                ),
              )
            : neck,
      );
      statuses.add(
        BuildingStatus(
          buildingId: b.id,
          defId: b.defId,
          runFraction: runsRecipe(def) ? b.lastRunFraction : null,
          effectiveFraction: !runsRecipe(def)
              ? null
              : runsWithoutCrew(def)
              ? b.lastRunFraction
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
          lostCreditsPerHour: _valuePerHour(s, c, factionId, {
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
      _noSales._with(
        lostCreditsPerHour: _valuePerHour(s, c, factionId, unsold),
      ),
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
  // lets go of them once it has. One exception: when the income came from
  // the cache, no steady flows were worked out, so the played copy is kept
  // for the steady rates for as long as the report lives.
  GameState? played = probe;
  GameState? sold = copy;
  // Steady flows take no stock into account, so the played copy gives the
  // state's; worked out once, for credits per second and steady rates.
  SteadyFlows? steady;
  // Prices as the report is built, for goods fed to megaprojects.
  final prices = {
    for (final m in c.megaprojects.values)
      if (megaprojectGoodsFed(s, s.faction(factionId), m))
        for (final id in m.baseCost.keys)
          if (id != creditsKey) id: salePrice(s, c, factionId, id),
  };
  // What the diversions read of the state, taken now: the report holds no
  // state but its own.
  final now = s.time;
  final market = {
    for (final r in s.faction(factionId).autoSell)
      if (s.body(r.bodyId).ownerId == factionId &&
          prices.containsKey(r.resourceId))
        r.resourceId: (
          saturation: s.market.saturation[r.resourceId] ?? 1,
          depth: marketDepthFor(s, c, factionId, r.resourceId),
          bonus: saleMultiplierFor(s, c, factionId, r.resourceId),
        ),
  };
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
    prices: prices,
    keepBlocks: _keepBlocks(s, c, factionId),
    contractBlocks: [
      for (final b in _contractBlocks(s, c, factionId))
        b.copyWith(firstSeenAt: since[b.key] ?? s.time),
    ],
    diversions: (income) => _diversions(c, income, market, now),
    income: () {
      final v = saleRevenuePerSec(
        played!,
        c,
        factionId,
        steady: steadyOf,
        market: sold!,
      );
      // The steady rates still need [played] when the income came from
      // the cache, which works out no steady flows.
      if (steady != null) played = null;
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

/// Input shortages explained by the routes that feed their stores, for
/// one faction's report: a [BottleneckKind.input] on a body, short of a
/// resource its owner's routes bring there, becomes a
/// [BottleneckKind.routeLimited] when those routes and the body's own
/// makers together carry less a second than its buildings use at full
/// supply, and one of the routes is held back by something other than
/// what its source has to send ([RouteLimit.sourceStock]): of those, the
/// one that carries most ([routeThroughput]), the first in route order on
/// a tie. Otherwise it stays as it is: a route its source holds back is
/// not the cause, and nor is one that could carry enough. Worked out once
/// per store, from the state the report is built from.
final class _RouteCauses {
  _RouteCauses(this.s, this.c, this.factionId, this._throughput);

  final GameState s;
  final Content c;
  final String factionId;

  /// [routeThroughputs] of [s], shared with the rest of the report.
  final Map<String, RouteThroughput> Function() _throughput;
  StepCache? _cache;

  /// Store ([bottleneckKey] of body and resource) to the route that holds
  /// it back and how, or null for none.
  final _known = <String, (String, RouteThroughput)?>{};

  /// [neck], an input shortage, as a route-limited one where a route is its
  /// cause; else [neck].
  Bottleneck explain(Bottleneck neck) {
    final bodyId = neck.bodyId!;
    final resourceId = neck.resourceId!;
    final key = bottleneckKey('', bodyId, null, resourceId);
    final cause = _known.containsKey(key)
        ? _known[key]
        : (_known[key] = _cause(bodyId, resourceId));
    return cause == null ? neck : neck._routeLimited(cause.$1, cause.$2);
  }

  (String, RouteThroughput)? _cause(String bodyId, String resourceId) {
    final body = s.body(bodyId);
    if (body.ownerId != factionId) return null;
    final feeding = [
      for (final r in s.routes)
        if (r.ownerId == factionId &&
            r.toBodyId == bodyId &&
            r.resourceId == resourceId &&
            s.body(r.fromBodyId).ownerId == factionId)
          r,
    ];
    if (feeding.isEmpty) return null;
    final through = _throughput();
    final cache = _cache ??= StepCache(s, c);
    final wanted = (cache.use(body, 1)[resourceId] ?? const BigNum.zero())
        .toDouble();
    final eff = cache.crewEff(factionId);
    final bonuses = bonusesFor(s, c, factionId);
    var supply = 0.0;
    for (final b in body.buildings) {
      if (b.lastRunFraction == 0) continue;
      final made = fullRateFlow(
        c,
        body,
        b,
        1,
        eff,
        bonuses: bonuses,
      ).outputs[resourceId];
      if (made != null) supply += made.toDouble() * b.lastRunFraction;
    }
    for (final r in feeding) {
      supply += through[r.id]!.perSec;
    }
    if (supply >= wanted) return null;
    (String, RouteThroughput)? best;
    for (final r in feeding) {
      final t = through[r.id]!;
      if (t.binding == RouteLimit.sourceStock) continue;
      if (best == null || t.perSec > best.$2.perSec) best = (r.id, t);
    }
    return best;
  }
}

/// Share of what would sell of a good that auto-delivery must take for a
/// [BottleneckKind.megaprojectDiversion]: a tenth.
const double minDiversionShare = 0.1;

/// The [BottleneckKind.megaprojectDiversion]s of [income], the faction's
/// steady income in the report, seen at [now]: for each good a megaproject
/// is handed a second there that the faction auto-sells ([market],
/// resource id to its saturation and the faction's market depth as the
/// report was built), where it is [minDiversionShare] or more of what
/// would otherwise sell of it.
///
/// What sells now, in units, is what auto-sell earns of the good a second
/// ([SteadyIncome.soldPerSec]) at today's price. The goods taken are valued
/// at the price the good would fetch if they sold too: the saturation that
/// selling both a second settles the market at, `1 / (1 + rate ×
/// marketRecoverySeconds / depth)`, no lower than its floor (as
/// `stepMarket` settles it). So a good the megaproject takes all of, whose
/// market sits near full price for want of sales, is not valued at that
/// price.
List<Bottleneck> _diversions(
  Content c,
  SteadyIncome income,
  Map<String, ({double saturation, double depth, double bonus})> market,
  double now,
) {
  final out = <Bottleneck>[];
  for (final MapEntry(key: m, value: got) in income.deliveredPerSec.entries) {
    for (final MapEntry(key: id, value: taken) in got.entries) {
      final (:saturation, :depth, :bonus) =
          market[id] ?? (saturation: 0.0, depth: 0.0, bonus: 1.0);
      if (id == creditsKey || depth <= 0 || taken <= const BigNum.zero()) {
        continue;
      }
      // What a unit earns the faction at full saturation: its sales are
      // paid the sale-price bonus too.
      final base = c.resources[id]!.basePrice.mulDouble(bonus);
      final today = base.mulDouble(saturation);
      final sold = today.isZero
          ? 0.0
          : ((income.soldPerSec[id] ?? const BigNum.zero()) / today).toDouble();
      final share = taken.toDouble() / (taken.toDouble() + sold);
      if (share < minDiversionShare) continue;
      final both = taken.toDouble() + sold;
      final settled = math.max(
        marketFloorOf(c, id),
        1 / (1 + both * c.rules.marketRecoverySeconds / depth),
      );
      out.add(
        Bottleneck(
          kind: BottleneckKind.megaprojectDiversion,
          bodyId: null,
          buildingId: null,
          resourceId: id,
          megaprojectId: m,
          shareOfSales: share,
          runFraction: 1 - share,
          lostCreditsPerHour: (taken * base).mulDouble(settled * 3600),
          firstSeenAt: now,
        ),
      );
    }
  }
  return out;
}

/// The [BottleneckKind.keepBlocksDelivery]s of [factionId] in [s]: for
/// each megaproject it feeds goods on its own that takes deliveries and
/// still owes a good, in content order, each body with an auto-sell rule
/// on the good, in rule order, whose `keepAtLeast` holds back units that
/// auto-delivery would hand over ([DeliveryKeeps.heldByKeepAtLeast]), up
/// to what is owed.
List<Bottleneck> _keepBlocks(GameState s, Content c, String factionId) {
  final f = s.faction(factionId);
  final rules = <(String, String)>{
    for (final r in f.autoSell)
      if (r.keepAtLeast > const BigNum.zero() &&
          s.body(r.bodyId).ownerId == factionId)
        (r.bodyId, r.resourceId),
  };
  if (rules.isEmpty) return const [];
  final fed = [
    for (final m in c.megaprojects.values)
      if (megaprojectGoodsFed(s, f, m) &&
          megaprojectTakesDeliveries(s, c, factionId, m))
        m,
  ];
  if (fed.isEmpty) return const [];
  // A rule's body holding a whole unit of a good a fed megaproject owes,
  // before working out what auto-delivery keeps there.
  final one = BigNum.from(1);
  final owing = [
    for (final m in fed)
      if (megaprojectRemaining(s, c, factionId, m) case final owed)
        for (final (bodyId, id) in rules)
          if (owed[id] case final need? when id != creditsKey)
            if ((s.body(bodyId).stock[id] ?? const BigNum.zero()) >= one)
              (m, bodyId, id, need),
  ];
  if (owing.isEmpty) return const [];
  final goods = {
    for (final m in fed)
      for (final id in m.baseCost.keys)
        if (id != creditsKey) id,
  }.toList();
  final keeps = autoDeliveryKeeps(
    s,
    StepCache(s, c),
    f,
    goods,
    _fullStepSeconds,
  );
  return [
    for (final (m, bodyId, id, need) in owing)
      if (keeps.heldByKeepAtLeast(s.body(bodyId), id).min(need.ceil())
          case final held when held >= one)
        Bottleneck(
          kind: BottleneckKind.keepBlocksDelivery,
          bodyId: bodyId,
          buildingId: null,
          resourceId: id,
          megaprojectId: m.id,
          heldByKeep: held,
          runFraction: 0,
          firstSeenAt: s.time,
        ),
  ];
}

/// The [BottleneckKind.contractBlocksDelivery]s of [factionId] in [s],
/// each first seen at `s.time`: for each megaproject it feeds goods on its
/// own that takes deliveries, in content order, each good it still owes,
/// in cost order, that an open contract asks for, where the contract
/// keeps at least a whole unit of what is owed from it: what the
/// faction's bodies could hand over without the contracts' holds
/// ([DeliveryKeeps.spareWithoutContracts]), up to what is owed, less what
/// they can hand over ([DeliveryKeeps.spare]), up to it too. A good is on
/// the board at most once, so one contract holds it. The same test as
/// [noteBottlenecks] tracks it by.
List<Bottleneck> _contractBlocks(GameState s, Content c, String factionId) {
  final f = s.faction(factionId);
  if (f.contracts.isEmpty || f.megaprojectAuto.isEmpty) return const [];
  final asked = {for (final k in f.contracts) k.resourceId: k};
  // Cheap first, as the engine asks every tick: does a megaproject set to
  // take goods cost any good on the board at all?
  if (!c.megaprojects.values.any(
    (m) =>
        (f.megaprojectAuto[m.id]?.goods ?? GoodsFeedMode.off) !=
            GoodsFeedMode.off &&
        m.baseCost.keys.any(asked.containsKey),
  )) {
    return const [];
  }
  final owing = [
    for (final m in c.megaprojects.values)
      if (megaprojectGoodsFed(s, f, m) &&
          megaprojectTakesDeliveries(s, c, factionId, m))
        for (final MapEntry(key: id, value: need) in megaprojectRemaining(
          s,
          c,
          factionId,
          m,
        ).entries)
          if (asked[id] case final k?) (m, k, need),
  ];
  if (owing.isEmpty) return const [];
  final goods = {for (final (_, k, _) in owing) k.resourceId}.toList();
  final keeps = autoDeliveryKeeps(
    s,
    StepCache(s, c),
    f,
    goods,
    _fullStepSeconds,
  );
  final owned = [
    for (final b in s.bodies)
      if (b.ownerId == factionId) b,
  ];
  // Of each good, what the bodies can hand over, and what they could
  // without the contracts' holds.
  final spare = {
    for (final id in goods)
      id: owned.fold(
        const BigNum.zero(),
        (t, b) => t + keeps.spare(b, id).max(const BigNum.zero()),
      ),
  };
  final without = {
    for (final id in goods)
      id: owned.fold(
        const BigNum.zero(),
        (t, b) => t + keeps.spareWithoutContracts(b, id),
      ),
  };
  final one = BigNum.from(1);
  return [
    for (final (m, k, need) in owing)
      if (without[k.resourceId]!.min(need) - spare[k.resourceId]!.min(need)
          case final v when v >= one)
        Bottleneck(
          kind: BottleneckKind.contractBlocksDelivery,
          bodyId: null,
          buildingId: null,
          resourceId: k.resourceId,
          megaprojectId: m.id,
          contractId: k.id,
          heldForContract: v,
          runFraction: 0,
          firstSeenAt: s.time,
        ),
  ];
}

/// Credits an hour that [perSec] (resource id to units a second) is worth
/// to [factionId] at the current market prices of [s]: what its sales of
/// them would earn ([salePrice]).
BigNum _valuePerHour(
  GameState s,
  Content c,
  String factionId,
  Map<String, BigNum> perSec,
) {
  var total = const BigNum.zero();
  for (final MapEntry(key: id, value: v) in perSec.entries) {
    total = total + v * salePrice(s, c, factionId, id);
  }
  return total.mulDouble(3600);
}

/// Refreshes every faction's [FactionState.seenBottlenecks] from the tick
/// that just ran: a bottleneck still there keeps its first-seen time, a
/// new one is seen [at], and one that cleared is dropped.
///
/// Reads what the tick left in [s], as the report does: each building's
/// [BuildingState.lastLimitReason], each full store that wasted output
/// ([BodyState.wastedThisStep]), a crew efficiency below 1, and each open
/// contract holding goods a megaproject fed on its own owes
/// ([BottleneckKind.contractBlocksDelivery], keyed by the contract). The engine
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
    // One record per contract, though more than one megaproject may owe
    // its good.
    final blocked = <String>{};
    for (final b in _contractBlocks(s, c, f.id)) {
      if (blocked.add(b.contractId!)) {
        see(b.kind.name, null, b.contractId, b.resourceId);
      }
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
/// through what is made from them. Nor does more of a good count on a
/// body whose store of it is full, where nothing sells, ships or feeds it
/// to a megaproject (one fed goods on its own, taking deliveries, whose
/// stage still owes the good): the tick's storage cap would cut it.
BigNum _staffingGain(
  GameState s,
  Content c,
  String factionId,
  GameState staffed,
  GameState actual,
  Map<String, RunCap> caps,
) {
  stepProduction(
    staffed,
    c,
    _sampleSeconds,
    crewEfficiencyOf: {factionId: 1},
    runCaps: caps,
  );
  final f = actual.faction(factionId);
  // Body and resource pairs whose extra output goes somewhere.
  // Goods a megaproject is fed on its own go in, from every body, as they
  // would sell, while it takes deliveries and its stage still owes them.
  final fed = {
    for (final m in c.megaprojects.values)
      if (megaprojectGoodsFed(actual, f, m) &&
          megaprojectTakesDeliveries(actual, c, factionId, m))
        for (final id in megaprojectRemaining(actual, c, factionId, m).keys)
          if (id != 'credits') id,
  };
  final moved = <(String, String)>{
    for (final r in f.autoSell) (r.bodyId, r.resourceId),
    for (final r in actual.routes)
      if (r.ownerId == factionId) (r.fromBodyId, r.resourceId),
    for (final b in actual.bodies)
      if (b.ownerId == factionId)
        for (final id in fed) (b.id, id),
  };
  final more = <String, BigNum>{};
  final now = <String, BigNum>{};
  for (final (i, b) in actual.bodies.indexed) {
    if (b.ownerId != factionId) continue;
    final cap = storageCap(actual, c, b);
    _addAll(now, b.stock);
    for (final MapEntry(key: id, value: v) in staffed.bodies[i].stock.entries) {
      final was = b.stock[id] ?? const BigNum.zero();
      // Past what the store keeps, more of a good nothing moves is cut.
      final kept = v > was && !moved.contains((b.id, id))
          ? v.min(cap.max(was))
          : v;
      more[id] = (more[id] ?? const BigNum.zero()) + kept;
    }
  }
  final gain = <String, BigNum>{
    for (final id in c.resources.keys)
      if (changeBetween(
            more[id] ?? const BigNum.zero(),
            now[id] ?? const BigNum.zero(),
          )
          case final d when !d.isZero)
        id: d,
  };
  return _valuePerHour(s, c, factionId, gain).max(const BigNum.zero());
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
      buildingIds: [b.id],
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
    buildingIds: [b.id],
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
