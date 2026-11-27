import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/spend_confirm.dart';
import 'package:space_idle/view/catalog_view.dart';
import 'package:space_idle/view/view_models.dart';

/// Opens the build catalog, or with [makes] only what makes that
/// resource. The sheet gets the caller's controller, wherever the route
/// is mounted.
Future<void> showCatalog(BuildContext context, {String? makes}) {
  final c = ControllerScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ControllerScope(
      controller: c,
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: CatalogSheet(makes: makes),
      ),
    ),
  );
}

/// The "Build" button under a body's buildings.
class BuildPicker extends StatelessWidget {
  /// Creates the button.
  const BuildPicker({super.key});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    icon: const Icon(Icons.add_business_outlined),
    label: const Text('Build'),
    onPressed: () => showCatalog(context),
  );
}

/// Every building the player can put up, what each costs, uses and makes
/// a second, and on which of the player's bodies it can go now, or why
/// not. Builds take crew from the free crew (`autoCrew`).
class CatalogSheet extends StatelessWidget {
  /// Creates the sheet; [makes] filters it to that resource's makers.
  const CatalogSheet({super.key, this.makes});

  /// Resource id to show the makers of; null for everything.
  final String? makes;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final entries = catalogView(c, makes: makes);
    final text = Theme.of(context).textTheme;
    final title = makes == null
        ? 'Build'
        : 'What makes ${c.content.resources[makes]?.name ?? makes}';
    return Material(
      color: Palette.panel,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(title, style: text.titleLarge),
            const SizedBox(height: 8),
            for (final e in entries) _Entry(entry: e),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry});

  final CatalogEntryView entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final mono = monoText(text.bodyMedium);
    String line(List<NamedValue> items) =>
        items.map((n) => '${n.name} ${n.value}').join(', ');
    final flows = [
      if (e.uses.isNotEmpty) line(e.uses),
      if (e.makes.isNotEmpty) line(e.makes),
    ].join('  →  ');
    return Card(
      key: ValueKey('catalog-${e.name}'),
      color: Palette.background,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Palette.border),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.name, style: text.titleMedium),
            Text(e.cost, style: mono),
            if (flows.isNotEmpty) Text(flows, style: mono),
            if (e.crewSlots > 0)
              Text(
                '${e.crewSlots} crew ${e.crewSlots == 1 ? 'slot' : 'slots'}',
                style: text.bodySmall?.copyWith(color: Palette.muted),
              ),
            const SizedBox(height: 4),
            SpendConfirm(
              id: 'catalog-${e.name}',
              builder: (context, ask) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in e.hosts)
                    if (h.canBuild)
                      TextButton.icon(
                        key: ValueKey(
                          e.depositResourceId == null
                              ? 'build-${e.defId}-${h.bodyId}'
                              : 'build-${e.defId}-${e.depositResourceId}'
                                    '-${h.bodyId}',
                        ),
                        icon: const Icon(Icons.add),
                        label: Text('Build on ${h.bodyName}'),
                        onPressed: () => ask(_spend(context, c, h)),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${h.bodyName}: ${h.reason}',
                          style: text.bodySmall?.copyWith(color: Palette.muted),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Building this entry on [h]; the sheet closes once it is built.
  Spend _spend(BuildContext context, GameController c, CatalogHost h) => Spend(
    price: entry.price,
    what: 'on ${entry.name} on ${h.bodyName}',
    run: () {
      final r = runAndReport(
        context,
        c,
        BuildCommand(
          c.playerId,
          h.bodyId,
          entry.defId,
          depositResourceId: entry.depositResourceId,
        ),
        announce: true,
      );
      if (r is CommandOk) Navigator.of(context).maybePop();
    },
  );
}
