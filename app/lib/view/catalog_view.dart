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

/// The build catalog: every building type (each extractor once per
/// resource it mines), or with [makes] only those that make it (the
/// core's `makersOf`).
///
/// Whether each of the player's bodies can host an entry is the core's
/// `hostChecks`, which checks it as the build command does; this only
/// words its reason.
List<CatalogEntryView> catalogView(GameController c, {String? makes}) {
  final content = c.content;
  final makers = makes == null ? null : makersOf(content, makes).toSet();
  return [
    for (final d in content.buildings.values)
      if (makers == null || makers.contains(d.id))
        ...(d.kind == BuildingKind.extractor
            ? [
                for (final r in d.extracts)
                  if (makes == null || makes == r) _entry(c, d, deposit: r),
              ]
            : [_entry(c, d)]),
  ];
}

CatalogEntryView _entry(GameController c, BuildingDef d, {String? deposit}) {
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
      for (final h in hostChecks(
        c.state,
        content,
        c.playerId,
        d.id,
        depositResourceId: deposit,
      ))
        CatalogHost(
          bodyId: h.bodyId,
          bodyName: c.state.body(h.bodyId).name,
          reason: switch (h.block) {
            null => null,
            final b => buildBlockText(content, c.state.body(h.bodyId), b),
          },
        ),
    ],
  );
}

/// [block] on [body] in words: "no free build slot", "needs an Iron Ore
/// deposit", "needs 600 credits (you have 250)", "needs 10 Steel on Kora".
String buildBlockText(Content c, BodyState body, BuildBlock block) {
  String n(BigNum? v) => formatNumber(v ?? const BigNum.zero());
  return switch (block.kind) {
    BuildBlockKind.noFreeSlot => 'no free build slot',
    BuildBlockKind.noDeposit => switch (block.resourceId) {
      final id? => () {
        final name = c.resources[id]?.name ?? id;
        return 'needs ${_article(name)} $name deposit';
      }(),
      null => 'needs a deposit to mine',
    },
    BuildBlockKind.short when block.resourceId == creditsKey =>
      'needs ${n(block.need)} credits (you have '
          '${formatNumber(block.have ?? const BigNum.zero(), rounding: NumberRounding.down)})',
    BuildBlockKind.short =>
      'needs ${n(block.need)} '
          '${c.resources[block.resourceId]?.name ?? block.resourceId} '
          'on ${body.name}',
  };
}

String _costText(Content c, Map<String, BigNum> cost) => [
  for (final MapEntry(key: id, value: v) in cost.entries)
    id == creditsKey
        ? '${formatNumber(v)} credits'
        : '${formatNumber(v)} ${c.resources[id]!.name}',
].join(' and ');

/// "a" or "an" before [word], by its first letter.
String _article(String word) => 'AEIOUaeiou'.contains(word[0]) ? 'an' : 'a';
