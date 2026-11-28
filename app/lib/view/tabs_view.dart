import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/format.dart';
import 'package:space_idle/view/view_models.dart';

// Views for the Production, Crew and Trade tabs: the whole empire at once,
// from the same rows and figures the planet panel uses.

/// One body's buildings on the Production tab.
@immutable
final class ProductionBodyView {
  /// Creates a view.
  const ProductionBodyView({
    required this.id,
    required this.name,
    required this.rows,
  });

  /// Body id.
  final String id;

  /// Its name.
  final String name;

  /// Its buildings' rows, in list order, as the planet panel shows them.
  final List<BuildingRowView> rows;
}

/// A building held back, for the Problems filter.
@immutable
final class ProblemView {
  /// Creates a view.
  const ProblemView({
    required this.bodyId,
    required this.bodyName,
    required this.row,
    required this.lostPerHour,
  });

  /// The body it is on.
  final String bodyId;

  /// That body's name.
  final String bodyName;

  /// Its row.
  final BuildingRowView row;

  /// Credits an hour its trouble costs, from the flow report's
  /// bottleneck naming it (`lostCreditsPerHour`); zero when none says.
  final BigNum lostPerHour;
}

/// The Production tab: every one of the player's buildings, by body, and
/// those held back.
@immutable
final class ProductionView {
  /// Creates a view.
  const ProductionView({required this.bodies, required this.problems});

  /// The player's bodies with buildings, in body order.
  final List<ProductionBodyView> bodies;

  /// Every building whose severity is not ok: stopped first, then held
  /// back, each by credits lost an hour, most first, ties in body and
  /// list order.
  final List<ProblemView> problems;
}

/// The Production tab's view from [c]: no upgrade previews (each row's
/// payback line asks for its own as it is drawn).
ProductionView productionView(GameController c) {
  final s = c.state;
  final flow = c.flow;
  final statuses = {
    for (final b in flow.bodies)
      for (final st in b.buildings) st.buildingId: st,
  };
  // Building id to what its trouble costs an hour, the most any
  // bottleneck naming it says.
  final lost = <String, BigNum>{};
  for (final n in flow.bottlenecks) {
    final v = n.lostCreditsPerHour;
    if (v == null) continue;
    for (final id in [?n.buildingId, ...n.buildingIds]) {
      if (lost[id] == null || v > lost[id]!) lost[id] = v;
    }
  }
  final bodies = <ProductionBodyView>[];
  final problems = <ProblemView>[];
  for (final body in s.bodies) {
    if (body.ownerId != c.playerId || body.buildings.isEmpty) continue;
    final ctx = RowContext.of(s, c.content, c.playerId, body, flow.bottlenecks);
    final rows = [
      for (final b in body.buildings)
        buildingRowView(s, c.content, c.playerId, b, statuses[b.id], ctx),
    ];
    bodies.add(ProductionBodyView(id: body.id, name: body.name, rows: rows));
    for (final r in rows) {
      if (r.severity == Severity.ok) continue;
      problems.add(
        ProblemView(
          bodyId: body.id,
          bodyName: body.name,
          row: r,
          lostPerHour: lost[r.id] ?? const BigNum.zero(),
        ),
      );
    }
  }
  // Stable: ties keep body and list order.
  final order = {for (final (i, p) in problems.indexed) p: i};
  problems.sort((a, b) {
    final bySeverity = b.row.severity.index.compareTo(a.row.severity.index);
    if (bySeverity != 0) return bySeverity;
    final byLoss = b.lostPerHour.compareTo(a.lostPerHour);
    return byLoss != 0 ? byLoss : order[a]!.compareTo(order[b]!);
  });
  return ProductionView(bodies: bodies, problems: problems);
}

/// A habitat on the Crew tab.
@immutable
final class HabitatView {
  /// Creates a view.
  const HabitatView({
    required this.bodyId,
    required this.bodyName,
    required this.row,
    required this.houses,
    required this.housesAtFull,
  });

  /// The body it is on.
  final String bodyId;

  /// That body's name.
  final String bodyName;

  /// Its row (its status, problem and severity).
  final BuildingRowView row;

  /// Crew it houses now: its housing at its last run fraction, with the
  /// housing bonus, rounded down.
  final int houses;

  /// Crew it houses at full rate.
  final int housesAtFull;
}

/// A crewed building on the Crew tab.
@immutable
final class CrewedView {
  /// Creates a view.
  const CrewedView({required this.bodyName, required this.row});

  /// The body it is on.
  final String bodyName;

  /// Its row, for its crew and its − and +.
  final BuildingRowView row;
}

/// The Crew tab, but for the forecast (the controller's
/// `crewForecastNow`, worked out after a frame).
@immutable
final class CrewView {
  /// Creates a view.
  const CrewView({
    required this.free,
    required this.assigned,
    required this.supported,
    required this.habitats,
    required this.crewed,
    required this.habitatBodyId,
  });

  /// Crew free to assign.
  final int free;

  /// Crew assigned.
  final int assigned;

  /// Crew the housing supports.
  final int supported;

  /// Every habitat of the player's, by body.
  final List<HabitatView> habitats;

  /// Every building with crew slots, by body.
  final List<CrewedView> crewed;

  /// Where a new habitat could go: the first body that can take one now
  /// (the core's `hostsFor`), else the first with a free build slot; null
  /// when none has room.
  final String? habitatBodyId;
}

/// The Crew tab's view from [c].
CrewView crewView(GameController c) {
  final s = c.state;
  final content = c.content;
  final flow = c.flow;
  final totals = crewTotals(s, content, c.playerId);
  final bonus = bonusesFor(s, content, c.playerId).housingMultiplier;
  final statuses = {
    for (final b in flow.bodies)
      for (final st in b.buildings) st.buildingId: st,
  };
  final habitats = <HabitatView>[];
  final crewed = <CrewedView>[];
  for (final body in s.bodies) {
    if (body.ownerId != c.playerId) continue;
    final ctx = RowContext.of(s, content, c.playerId, body, flow.bottlenecks);
    for (final b in body.buildings) {
      final def = content.buildings[b.defId]!;
      final row = buildingRowView(
        s,
        content,
        c.playerId,
        b,
        statuses[b.id],
        ctx,
      );
      if (def.kind == BuildingKind.habitat) {
        final full = habitatHousing(content.rules, def, b) * bonus;
        habitats.add(
          HabitatView(
            bodyId: body.id,
            bodyName: body.name,
            row: row,
            houses: (full * b.lastRunFraction + housingTolerance).floor(),
            housesAtFull: (full + housingTolerance).floor(),
          ),
        );
      }
      if (row.crewMax > 0) {
        crewed.add(CrewedView(bodyName: body.name, row: row));
      }
    }
  }
  final hosts = hostsFor(s, content, c.playerId, 'habitat');
  final roomy = [
    for (final h in hostChecks(s, content, c.playerId, 'habitat'))
      if (h.block?.kind != BuildBlockKind.noFreeSlot) h.bodyId,
  ];
  return CrewView(
    free: totals.free,
    assigned: totals.assigned,
    supported: totals.supported,
    habitats: habitats,
    crewed: crewed,
    habitatBodyId: hosts.firstOrNull ?? roomy.firstOrNull,
  );
}

/// The Crew tab's warning from [f], or null while the crew holds: "Crew
/// runs short in 2h", or "Crew is short now".
String? crewWarningText(CrewForecast? f) => switch (f?.secondsUntilShortage) {
  null => null,
  final t when t <= 0 => 'Crew is short now',
  final t => 'Crew runs short in ${formatDuration(t)}',
};

/// One resource on the Trade tab's market.
@immutable
final class MarketRowView {
  /// Creates a view.
  const MarketRowView({
    required this.id,
    required this.name,
    required this.price,
    required this.saturation,
    required this.saturationText,
    required this.worthPerHour,
  });

  /// Resource id.
  final String id;

  /// Its name.
  final String name;

  /// What a unit earns the player now: the core's `salePrice`, bonuses
  /// such as the Mass Driver's included, formatted.
  final String price;

  /// The market's saturation of it, 0 to 1: what share of its base price
  /// the market pays before bonuses.
  final double saturation;

  /// [saturation] in words: "92% of base price".
  final String saturationText;

  /// What the player's net production of it is worth an hour at [price],
  /// signed ("+1.2K/h", "-40/h"); null when it nets to nothing.
  final String? worthPerHour;
}

/// One auto-sell rule on the Trade tab.
@immutable
final class AutoSellRuleView {
  /// Creates a view.
  const AutoSellRuleView({
    required this.bodyId,
    required this.bodyName,
    required this.resourceId,
    required this.resourceName,
    required this.keep,
  });

  /// Body whose stock it sells.
  final String bodyId;

  /// That body's name.
  final String bodyName;

  /// Resource sold.
  final String resourceId;

  /// Its name.
  final String resourceName;

  /// What it keeps, formatted.
  final String keep;
}

/// The Trade tab.
@immutable
final class TradeView {
  /// Creates a view.
  const TradeView({
    required this.market,
    required this.rules,
    required this.routes,
  });

  /// Every resource in content order.
  final List<MarketRowView> market;

  /// The player's auto-sell rules, in rule order.
  final List<AutoSellRuleView> rules;

  /// Every route of the player's, in route order.
  final List<RouteView> routes;
}

/// The Trade tab's view from [c].
TradeView tradeView(GameController c) {
  final s = c.state;
  final content = c.content;
  final flow = c.flow;
  String body(String id) => s.body(id).name;
  return TradeView(
    market: [
      for (final MapEntry(key: id, value: def) in content.resources.entries)
        () {
          final price = salePrice(s, content, c.playerId, id);
          final sat = s.market.saturation[id] ?? 1;
          final net = flow.netProducedPerSec(id);
          final worth = net * price * BigNum.from(3600);
          return MarketRowView(
            id: id,
            name: def.name,
            price: formatAmount(price),
            saturation: sat.clamp(0.0, 1.0),
            saturationText: '${formatPercent(sat)} of base price',
            worthPerHour: worth.isZero
                ? null
                : '${worth.isNegative ? '-' : '+'}'
                      '${formatNumber(worth.isNegative ? -worth : worth)}/h',
          );
        }(),
    ],
    rules: [
      for (final r in s.faction(c.playerId).autoSell)
        AutoSellRuleView(
          bodyId: r.bodyId,
          bodyName: body(r.bodyId),
          resourceId: r.resourceId,
          resourceName: content.resources[r.resourceId]!.name,
          keep: formatNumber(r.keepAtLeast),
        ),
    ],
    routes: playerRoutes(c),
  );
}
