import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/building_row_view.dart';
import 'package:space_idle/view/format.dart';

/// One of the player's bodies as a place to build a catalog entry.
@immutable
final class CatalogHost {
  /// Creates a host.
  const CatalogHost({
    required this.bodyId,
    required this.bodyName,
    required this.reason,
  });

  /// Body id.
  final String bodyId;

  /// Its name.
  final String bodyName;

  /// Why it cannot be built there now ("no free build slot", "needs a
  /// Copper Ore deposit", "needs 600 credits (you have 250)"); null when
  /// it can.
  final String? reason;

  /// Whether it can be built there now.
  bool get canBuild => reason == null;
}

/// One thing the build catalog offers: a building type, or for an
/// extractor one resource it can mine ("Mine (Iron Ore)").
@immutable
final class CatalogEntryView {
  /// Creates an entry.
  const CatalogEntryView({
    required this.defId,
    required this.depositResourceId,
    required this.name,
    required this.cost,
    required this.price,
    required this.crewSlots,
    required this.uses,
    required this.makes,
    required this.hosts,
  });

  /// Building type id.
  final String defId;

  /// For an extractor, the resource this entry mines; else null.
  final String? depositResourceId;

  /// "Smelter", or "Mine (Iron Ore)".
  final String name;

  /// What it costs to build, such as "150 credits".
  final String cost;

  /// The credits part of its cost, as a number, for the spend confirm.
  final BigNum price;

  /// Its base crew slots.
  final int crewSlots;

  /// What it uses a second at level 1 with its base crew (`-0.4/s`).
  final List<NamedValue> uses;

  /// What it makes a second at level 1 with its base crew, an extractor
  /// at a richness of 1 (`+0.2/s`).
  final List<NamedValue> makes;

  /// Each of the player's bodies, in body order, and whether it can host
  /// this now.
  final List<CatalogHost> hosts;
}

/// The building types whose output includes [resourceId]: extractors that
/// mine it and recipes that make it, in content order.
List<String> makersOf(Content c, String resourceId) => [
  for (final d in c.buildings.values)
    if (d.kind == BuildingKind.extractor
        ? d.extracts.contains(resourceId)
        : d.outputs.containsKey(resourceId))
      d.id,
];

/// The build catalog: every building type (each extractor once per
/// resource it mines), or with [makes] only those that make it.
///
/// Whether a body can host an entry is worked out here from the slots,
/// deposits and costs the build command checks, until the core's own
/// host check (stage 2 Task 0) replaces it; the command itself still has
/// the last word when Build is tapped.
List<CatalogEntryView> catalogView(GameController c, {String? makes}) {
  final content = c.content;
  final owned = [
    for (final b in c.state.bodies)
      if (b.ownerId == c.playerId) b,
  ];
  return [
    for (final d in content.buildings.values)
      ...(d.kind == BuildingKind.extractor
          ? [
              for (final r in d.extracts)
                if (makes == null || makes == r)
                  _entry(c, d, owned, deposit: r),
            ]
          : [
              if (makes == null || d.outputs.containsKey(makes))
                _entry(c, d, owned),
            ]),
  ];
}

CatalogEntryView _entry(
  GameController c,
  BuildingDef d,
  List<BodyState> owned, {
  String? deposit,
}) {
  final content = c.content;
  String res(String id) => content.resources[id]!.name;
  List<NamedValue> perSecond(Map<String, double> m, {bool used = false}) => [
    if (runsRecipe(d))
      for (final MapEntry(key: id, value: v) in m.entries)
        if (deposit == null || id == deposit)
          NamedValue(
            res(id),
            formatRate(BigNum.from((used ? -v : v) / d.cycleSeconds)),
          ),
  ];
  return CatalogEntryView(
    defId: d.id,
    depositResourceId: deposit,
    name: deposit == null ? d.name : '${d.name} (${res(deposit)})',
    cost: _costText(content, d.buildCost),
    price: d.buildCost[creditsKey] ?? const BigNum.zero(),
    crewSlots: d.crewSlots,
    uses: perSecond(d.inputs, used: true),
    makes: perSecond(d.outputs),
    hosts: [
      for (final b in owned)
        CatalogHost(
          bodyId: b.id,
          bodyName: b.name,
          reason: _blocked(c, d, b, deposit),
        ),
    ],
  );
}

/// Why [d] cannot go on [body] now, in the order the build command
/// checks: a free slot, the deposit, then each cost.
String? _blocked(
  GameController c,
  BuildingDef d,
  BodyState body,
  String? deposit,
) {
  final content = c.content;
  if (body.buildings.length >= buildSlots(content, body)) {
    return 'no free build slot';
  }
  if (deposit != null && !body.deposits.any((x) => x.resourceId == deposit)) {
    return 'needs a ${content.resources[deposit]!.name} deposit';
  }
  for (final MapEntry(key: id, value: need) in d.buildCost.entries) {
    if (id == creditsKey) {
      final have = c.state.faction(c.playerId).credits;
      if (have < need) {
        return 'needs ${formatNumber(need)} credits '
            '(you have ${formatNumber(have, rounding: NumberRounding.down)})';
      }
    } else {
      final have = body.stock[id] ?? const BigNum.zero();
      if (have < need) {
        return 'needs ${formatNumber(need)} ${content.resources[id]!.name} '
            'on ${body.name}';
      }
    }
  }
  return null;
}

String _costText(Content c, Map<String, BigNum> cost) => [
  for (final MapEntry(key: id, value: v) in cost.entries)
    id == creditsKey
        ? '${formatNumber(v)} credits'
        : '${formatNumber(v)} ${c.resources[id]!.name}',
].join(' and ');
