import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/lazy_list.dart';
import 'package:space_idle/ui/planet/building_row.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/tabs_view.dart';

/// What the Production tab lists.
sealed class _Filter {
  const _Filter();
}

final class _All extends _Filter {
  const _All();
}

final class _Problems extends _Filter {
  const _Problems();
}

final class _Body extends _Filter {
  const _Body(this.id);
  final String id;

  @override
  bool operator ==(Object other) => other is _Body && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Every building of the player's, as the planet panel's rows, grouped by
/// body; filtered to All, Problems (not ok, the worst first) or one body.
/// A body's header shows it on the map.
///
/// The list is built lazily, and the rows' payback lines ask for their own
/// previews as they are drawn, so a big empire costs only what is on
/// screen.
class ProductionTab extends StatefulWidget {
  /// Creates the tab.
  const ProductionTab({super.key});

  /// How many times any Production tab has been built, for tests: a hidden
  /// tab must not rebuild on a tick.
  @visibleForTesting
  static int debugBuilds = 0;

  @override
  State<ProductionTab> createState() => _ProductionTabState();
}

class _ProductionTabState extends State<ProductionTab> {
  _Filter _filter = const _All();

  @override
  Widget build(BuildContext context) {
    ProductionTab.debugBuilds++;
    final c = ControllerScope.of(context);
    final view = productionView(c);
    final text = Theme.of(context).textTheme;
    // A body filter for a body no longer the player's falls back to All.
    final filter = switch (_filter) {
      _Body(:final id) when !view.bodies.any((b) => b.id == id) => const _All(),
      final f => f,
    };
    Widget chip(String key, String label, _Filter f) => ChoiceChip(
      key: ValueKey(key),
      label: Text(label),
      selected: filter == f,
      onSelected: (_) => setState(() => _filter = f),
    );
    final items = <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip('filter-all', 'All', const _All()),
          chip(
            'filter-problems',
            'Problems (${view.problems.length})',
            const _Problems(),
          ),
          for (final b in view.bodies)
            chip('filter-body-${b.id}', b.name, _Body(b.id)),
        ],
      ),
      const SizedBox(height: 8),
      ...switch (filter) {
        _Problems() => [
          if (view.problems.isEmpty)
            Text(
              'Nothing is held back.',
              style: text.bodyMedium?.copyWith(color: Palette.muted),
            ),
          for (final p in view.problems) ...[
            Text(
              p.bodyName,
              style: text.labelMedium?.copyWith(color: Palette.muted),
            ),
            BuildingRow(key: ValueKey(p.row.id), view: p.row),
          ],
        ],
        _All() || _Body() => [
          for (final b in view.bodies)
            if (filter is _All || filter == _Body(b.id)) ...[
              _BodyHeader(id: b.id, name: b.name, count: b.rows.length),
              for (final r in b.rows) BuildingRow(key: ValueKey(r.id), view: r),
            ],
        ],
      },
    ];
    return ColoredBox(
      color: Palette.panel,
      child: LazyList(padding: const EdgeInsets.all(16), items: items),
    );
  }
}

/// A body's name and building count; a tap shows it on the map.
class _BodyHeader extends StatelessWidget {
  const _BodyHeader({
    required this.id,
    required this.name,
    required this.count,
  });

  final String id;
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$name, show on the map',
      excludeSemantics: true,
      onTap: () => ShellScope.of(context).openOnMap(id),
      child: InkWell(
        key: ValueKey('production-body-$id'),
        onTap: () => ShellScope.of(context).openOnMap(id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$name · ${count == 1 ? '1 building' : '$count buildings'}',
                    style: text.titleMedium,
                  ),
                ),
                const Icon(Icons.public, color: Palette.cyan),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
