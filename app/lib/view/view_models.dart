import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/building_row_view.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/project_views.dart';

export 'package:space_idle/view/building_row_view.dart';

/// Read-only views of the game for the widgets: every number already
/// formatted, every name a display name. Built fresh from the controller
/// on each change; they change nothing.

/// The always-visible top bar.
@immutable
final class TopBarView {
  /// Creates a view.
  const TopBarView({
    required this.credits,
    required this.creditsRate,
    required this.crewFree,
    required this.crewTotal,
    required this.pinned,
  });

  /// Credits held, formatted.
  final String credits;

  /// What sales earn a second, as `+1.24K/s`.
  final String creditsRate;

  /// Crew still free to assign.
  final int crewFree;

  /// Crew the empire's housing supports.
  final int crewTotal;

  /// Up to 3 resources with the most stock on the player's bodies, most
  /// first, ties in content order.
  final List<NamedValue> pinned;
}

/// The top bar from [c]'s state.
TopBarView topBar(GameController c) {
  final s = c.state;
  final f = s.faction(c.playerId);
  final crew = crewTotals(s, c.content, c.playerId);
  final held = <String, BigNum>{};
  for (final b in s.bodies) {
    if (b.ownerId != c.playerId) continue;
    for (final MapEntry(key: id, value: v) in b.stock.entries) {
      held[id] = (held[id] ?? const BigNum.zero()) + v;
    }
  }
  final rank = {for (final (i, id) in c.content.resources.keys.indexed) id: i};
  final ids = [
    for (final id in rank.keys)
      if ((held[id] ?? const BigNum.zero()) > const BigNum.zero()) id,
  ];
  // Most first; content order breaks ties (List.sort is not stable).
  ids.sort((a, b) {
    final by = held[b]!.compareTo(held[a]!);
    return by != 0 ? by : rank[a]!.compareTo(rank[b]!);
  });
  return TopBarView(
    credits: formatNumber(f.credits),
    creditsRate: formatRate(c.flow.creditsPerSec),
    crewFree: crew.free,
    crewTotal: crew.supported,
    pinned: [
      for (final id in ids.take(3))
        NamedValue(
          c.content.resources[id]!.name,
          // Whole units held, never rounded up to more than there is.
          formatNumber(held[id]!.floor(), rounding: NumberRounding.down),
        ),
    ],
  );
}

/// What a store's row warns of.
enum StockAlert {
  /// Nothing.
  none,

  /// Full, and output is being wasted.
  full,

  /// Falling, and empty within [ResourceRowView.runningOutSeconds].
  runningOut,
}

/// One resource in a body's storage.
@immutable
final class ResourceRowView {
  /// Creates a row view.
  const ResourceRowView({
    required this.id,
    required this.name,
    required this.amount,
    required this.cap,
    required this.fill,
    required this.net,
    required this.price,
    required this.alert,
    required this.autoSell,
    required this.keepAtLeast,
    required this.held,
    required this.hasStock,
  });

  /// How soon a falling store counts as running out.
  static const double runningOutSeconds = 600;

  /// Resource id.
  final String id;

  /// Display name.
  final String name;

  /// Stock, formatted.
  final String amount;

  /// The body's storage cap, formatted.
  final String cap;

  /// Stock over cap, 0 to 1.
  final double fill;

  /// The stock's change a second, as `-3/s`.
  final String net;

  /// What a unit earns the player on the market now (its sale price,
  /// megaproject bonuses included), formatted.
  final String price;

  /// What the row warns of.
  final StockAlert alert;

  /// Whether the body auto-sells it.
  final bool autoSell;

  /// The auto-sell rule's "keep at least"; null with no rule.
  final BigNum? keepAtLeast;

  /// What the auto-sell rule holds back and why, from the core's
  /// `autoSellKeep`: "Auto-sell keeps 680: 100 you set, 80 for its
  /// buildings, 500 for contracts; nothing above that to sell". Null
  /// with no rule, or when it keeps nothing.
  final String? held;

  /// Whether there is any to sell.
  final bool hasStock;
}

/// The seconds of one live market step, the controller's tick, over
/// which an auto-sell rule's keep is worked out ([autoSellKeep]).
const double autoSellStepSeconds = 1;

/// How a route stands now.
enum RouteStatus {
  /// It is carrying cargo.
  moving,

  /// It could carry nothing now: its source has none to send, or its
  /// destination no room.
  waiting,

  /// Paused: its destination, with what is on its way, holds the stop
  /// level (the core's `routePaused`).
  stopped,
}

/// What holds a route to its throughput, completing "held by …".
String routeLimitText(RouteLimit limit) => switch (limit) {
  RouteLimit.rate => 'its set rate',
  RouteLimit.ships => 'its cargo ships',
  RouteLimit.destinationRoom => 'room at its destination',
  RouteLimit.sourceStock => 'what its source has to send',
  RouteLimit.stopLevel => 'its stop level',
};

/// How a route stands and its sentence, from whether it is [paused]
/// (`routePaused`) and its [throughput] (`routeThroughput`).
///
/// A paused route is stopped at its stop level. One that could carry
/// nothing now is waiting, on what its binding limit names: its source's
/// stock, room at its destination, or, for a stop-level route not paused
/// yet, the cargo other routes have on its way, which already fills the
/// stop level they share. Otherwise it is moving.
({RouteStatus status, String text}) routeStatusOf({
  required bool paused,
  required RouteThroughput throughput,
  required String fromName,
  required String toName,
  required String resourceName,
}) {
  if (paused) {
    return (
      status: RouteStatus.stopped,
      text: 'Stopped: $toName holds its stop level',
    );
  }
  if (throughput.perSec > 0) {
    return (status: RouteStatus.moving, text: 'Moving');
  }
  return (
    status: RouteStatus.waiting,
    text: switch (throughput.binding) {
      RouteLimit.sourceStock => 'Waiting for $resourceName at $fromName',
      RouteLimit.destinationRoom => 'Waiting for room at $toName',
      RouteLimit.stopLevel =>
        "Waiting: cargo on its way fills $toName's stop level",
      // The core keeps a rate above zero and at least one ship.
      RouteLimit.rate || RouteLimit.ships => 'Waiting',
    },
  );
}

/// A route on a body's panel.
@immutable
final class RouteView {
  /// Creates a route view.
  const RouteView({
    required this.id,
    required this.fromName,
    required this.toName,
    required this.resourceName,
    required this.rate,
    required this.ships,
    required this.travel,
    required this.fromBodyId,
    required this.toBodyId,
    required this.resourceId,
    required this.throughput,
    required this.limit,
    required this.status,
    required this.statusText,
    required this.stop,
    required this.stopValue,
    required this.rateValue,
    required this.spareShips,
  });

  /// Route id.
  final String id;

  /// Source body's name.
  final String fromName;

  /// Destination body's name.
  final String toName;

  /// The resource carried.
  final String resourceName;

  /// Its set rate, as `0.5/s`.
  final String rate;

  /// Cargo ships assigned.
  final int ships;

  /// One trip's travel time, as `2m`.
  final String travel;

  /// Source body id.
  final String fromBodyId;

  /// Destination body id.
  final String toBodyId;

  /// Resource id carried.
  final String resourceId;

  /// What it could carry a second at most, sustained (the core's
  /// `routeThroughput`), as `0.4/s`.
  final String throughput;

  /// What holds it to that ([routeLimitText]).
  final String limit;

  /// How it stands now.
  final RouteStatus status;

  /// [status] as a sentence: "Moving", "Waiting for Iron Ore at Kora",
  /// "Stopped: Brine holds its stop level".
  final String statusText;

  /// Its stop level, formatted; null for none.
  final String? stop;

  /// Its stop level; null for none.
  final BigNum? stopValue;

  /// Its set rate, units a second.
  final BigNum rateValue;

  /// Whole cargo ships in its source's stock, which an edit can add.
  final int spareShips;
}

/// What claiming an unowned body takes.
@immutable
final class ClaimView {
  /// Creates a claim view.
  const ClaimView({
    required this.creditsCost,
    required this.price,
    required this.kitsNeeded,
    required this.affordable,
    required this.sourceBodyIds,
    required this.time,
    this.blockedReason,
    this.running,
  });

  /// Credits it costs, formatted.
  final String creditsCost;

  /// Its price in credits, as a number, for the spend confirm.
  final BigNum price;

  /// Outpost kits it takes; 0 for the first claim.
  final int kitsNeeded;

  /// Whether a claim can start now: no claim on the body is under way,
  /// and the player has the credits and a body with the kits.
  final bool affordable;

  /// Owned bodies holding enough kits to pay from, or every owned body
  /// when none are needed.
  final List<String> sourceBodyIds;

  /// The claim on the body already under way (the player's or anyone's),
  /// for the panel to show its countdown instead of a button; null when
  /// none is.
  final ProjectView? running;

  /// How long the claim takes once started, such as "30m".
  final String time;

  /// Why it cannot start now ("needs 5K credits (you have 250)", "needs
  /// 10 Outpost Kit on one of your bodies"); null when it can, or while a
  /// claim is [running].
  final String? blockedReason;
}

/// A body's Mission Control panel.
@immutable
final class BodyView {
  /// Creates a body view.
  const BodyView({
    required this.id,
    required this.name,
    required this.typeName,
    required this.owned,
    required this.ownerName,
    required this.depositNames,
    required this.slotsUsed,
    required this.slotsTotal,
    required this.buildings,
    required this.storage,
    required this.routesOut,
    required this.routesIn,
    required this.claim,
  });

  /// Body id.
  final String id;

  /// Display name.
  final String name;

  /// Its body type's name, such as "Rocky World".
  final String typeName;

  /// Whether the player owns it.
  final bool owned;

  /// The owning faction's name; null when nobody owns it.
  final String? ownerName;

  /// Its deposits' resource names.
  final List<String> depositNames;

  /// Buildings on it.
  final int slotsUsed;

  /// Buildings it can hold.
  final int slotsTotal;

  /// Its buildings, in list order.
  final List<BuildingRowView> buildings;

  /// Resources it holds or moves, in content order.
  final List<ResourceRowView> storage;

  /// Player routes leaving it.
  final List<RouteView> routesOut;

  /// Player routes arriving at it.
  final List<RouteView> routesIn;

  /// What claiming it takes; null when someone owns it.
  final ClaimView? claim;
}

/// Body [bodyId]'s panel, or null for a body the player cannot see.
BodyView? bodyView(GameController c, String bodyId) {
  final s = c.state;
  final content = c.content;
  final player = c.playerId;
  final body = s.bodies.where((b) => b.id == bodyId).firstOrNull;
  if (body == null || !isVisible(s, body, player)) return null;
  final flow = c.flow;
  final bodyFlow = flow.bodies.where((b) => b.bodyId == bodyId).firstOrNull;
  final rows = RowContext.of(s, content, player, body, flow.bottlenecks);
  final statuses = {
    for (final st in bodyFlow?.buildings ?? const <BuildingStatus>[])
      st.buildingId: st,
  };
  // The controller works them out once per state, for every panel.
  Map<String, RouteThroughput> throughputs() => c.throughputs;
  return BodyView(
    id: body.id,
    name: body.name,
    typeName: content.bodyTypes[body.typeId]?.name ?? body.typeId,
    owned: body.ownerId == player,
    ownerName: s.factions.where((f) => f.id == body.ownerId).firstOrNull?.name,
    depositNames: [
      for (final d in body.deposits) content.resources[d.resourceId]!.name,
    ],
    slotsUsed: body.buildings.length,
    slotsTotal: buildSlots(content, body),
    buildings: [
      for (final b in body.buildings)
        buildingRowView(s, content, player, b, statuses[b.id], rows),
    ],
    storage: _storage(c, body, bodyFlow),
    routesOut: [
      for (final r in s.routes)
        if (r.ownerId == player && r.fromBodyId == bodyId)
          _route(c, r, throughputs()),
    ],
    routesIn: [
      for (final r in s.routes)
        if (r.ownerId == player && r.toBodyId == bodyId)
          _route(c, r, throughputs()),
    ],
    claim: body.ownerId == null ? _claim(c, body) : null,
  );
}

List<ResourceRowView> _storage(
  GameController c,
  BodyState body,
  BodyFlow? flow,
) {
  final s = c.state;
  final cap = storageCap(s, c.content, body);
  // One bonus lookup for every row's sale price (the core's salePrice is
  // price x salePriceMultiplierFor(tier); a test pins the two together).
  final bonuses = bonusesFor(s, c.content, c.playerId);
  final rules = {
    for (final r in s.faction(c.playerId).autoSell)
      if (r.bodyId == body.id) r.resourceId: r,
  };
  final selling = rules.keys.toSet();
  const zero = BigNum.zero();
  // A resource it holds, moves, or auto-sells: a rule that has sold the
  // store empty keeps its row, so it can still be turned off.
  return [
    for (final MapEntry(key: id, value: def) in c.content.resources.entries)
      if ((body.stock[id] ?? zero) > zero ||
          !(flow?.netPerSec[id] ?? zero).isZero ||
          selling.contains(id))
        _resourceRow(
          c,
          id,
          def.name,
          stock: body.stock[id] ?? zero,
          cap: cap,
          net: flow?.netPerSec[id] ?? zero,
          wasted: flow?.wastedPerSec[id] ?? zero,
          autoSell: selling.contains(id),
          rule: rules[id],
          salePrice: price(
            s,
            c.content,
            id,
          ).mulDouble(bonuses.salePriceMultiplierFor(def.tier)),
        ),
  ];
}

ResourceRowView _resourceRow(
  GameController c,
  String id,
  String name, {
  required BigNum stock,
  required BigNum cap,
  required BigNum net,
  required BigNum wasted,
  required bool autoSell,
  required BigNum salePrice,
  AutoSellRule? rule,
}) {
  final capD = cap.toDouble();
  final fill = capD <= 0 ? 0.0 : (stock.toDouble() / capD).clamp(0.0, 1.0);
  final StockAlert alert;
  if (wasted > const BigNum.zero() && stock >= cap) {
    alert = StockAlert.full;
  } else if (net.isNegative &&
      stock.toDouble() / -net.toDouble() < ResourceRowView.runningOutSeconds) {
    alert = StockAlert.runningOut;
  } else {
    alert = StockAlert.none;
  }
  return ResourceRowView(
    id: id,
    name: name,
    amount: formatNumber(stock),
    cap: formatNumber(cap),
    fill: fill,
    net: formatRate(net),
    price: formatAmount(salePrice),
    alert: alert,
    autoSell: autoSell,
    keepAtLeast: rule?.keepAtLeast,
    held: rule == null ? null : _held(c, rule, stock),
    hasStock: stock > const BigNum.zero(),
  );
}

/// What auto-sell [rule] holds back and why ([autoSellKeep]), with
/// [stock] held; null when it keeps nothing.
String? _held(GameController c, AutoSellRule rule, BigNum stock) {
  final k = autoSellKeep(c.state, c.content, rule, autoSellStepSeconds);
  if (k.keeps <= const BigNum.zero()) return null;
  String n(BigNum v) => formatNumber(v);
  final parts = [
    if (k.keepAtLeast > const BigNum.zero()) '${n(k.keepAtLeast)} you set',
    if (k.localUse > const BigNum.zero()) '${n(k.localUse)} for its buildings',
    if (k.contractHold > const BigNum.zero())
      '${n(k.contractHold)} for contracts',
    if (k.megaprojectHold > const BigNum.zero())
      '${n(k.megaprojectHold)} for megaprojects',
  ];
  return [
    'Auto-sell keeps ${n(k.keeps)}',
    if (parts.isNotEmpty) ': ${parts.join(', ')}',
    if (k.cappedAtStorage) ', cut to the storage cap',
    if (stock <= k.keeps) '; nothing above that to sell',
  ].join();
}

RouteView _route(
  GameController c,
  RouteState r,
  Map<String, RouteThroughput> throughputs,
) {
  final s = c.state;
  final from = s.body(r.fromBodyId);
  final to = s.body(r.toBodyId);
  final res = c.content.resources[r.resourceId]!.name;
  final t = throughputs[r.id] ?? (perSec: 0.0, binding: RouteLimit.rate);
  final (:status, text: statusText) = routeStatusOf(
    paused: routePaused(s, c.content, r),
    throughput: t,
    fromName: from.name,
    toName: to.name,
    resourceName: res,
  );
  final stop = r.stopAtDestination;
  return RouteView(
    id: r.id,
    fromName: from.name,
    toName: to.name,
    resourceName: res,
    rate: '${formatAmount(r.ratePerSecond)}/s',
    ships: r.cargoShips,
    travel: formatDuration(travelSeconds(s, c.content, from, to)),
    fromBodyId: from.id,
    toBodyId: to.id,
    resourceId: r.resourceId,
    throughput: '${formatAmount(BigNum.from(t.perSec))}/s',
    limit: routeLimitText(t.binding),
    status: status,
    statusText: statusText,
    stop: stop == null ? null : formatNumber(stop),
    stopValue: stop,
    rateValue: r.ratePerSecond,
    spareShips: _wholeShips(c, from),
  );
}

ClaimView _claim(GameController c, BodyState body) {
  final s = c.state;
  final running = projectOn(s, ProjectKind.claim, body.id);
  final cost = claimCost(s, c.content, c.playerId);
  final kit = c.content.rules.outpostKitResource;
  final credits = cost[creditsKey] ?? const BigNum.zero();
  final kits = cost[kit] ?? const BigNum.zero();
  final sources = [
    for (final b in s.bodies)
      if (b.ownerId == c.playerId &&
          (b.stock[kit] ?? const BigNum.zero()) >= kits)
        b.id,
  ];
  final have = s.faction(c.playerId).credits;
  final String? blocked;
  if (running != null) {
    blocked = null;
  } else if (have < credits) {
    blocked =
        'needs ${formatNumber(credits)} credits '
        '(you have ${formatNumber(have, rounding: NumberRounding.down)})';
  } else if (sources.isEmpty) {
    blocked =
        'needs ${formatNumber(kits)} ${c.content.resources[kit]!.name} '
        'on one of your bodies';
  } else {
    blocked = null;
  }
  return ClaimView(
    creditsCost: formatNumber(credits),
    price: credits,
    kitsNeeded: kits.toDouble().round(),
    affordable: running == null && blocked == null,
    sourceBodyIds: sources,
    time: formatDuration(claimSeconds(s, c.content, c.playerId)),
    blockedReason: blocked,
    running: running == null ? null : projectView(c, running),
  );
}

/// Whole cargo ships in [body]'s stock.
int _wholeShips(GameController c, BodyState body) {
  final n =
      (body.stock[c.content.rules.cargoShipResource] ?? const BigNum.zero())
          .floor()
          .toDouble();
  return n.isFinite && n > 0 ? n.round() : 0;
}
