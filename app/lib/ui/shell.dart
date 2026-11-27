import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/away_dialog.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/map/star_map.dart';
import 'package:space_idle/ui/settings_sheet.dart';
import 'package:space_idle/ui/top_bar.dart';
import 'package:space_idle/view/view_models.dart';

/// The selected body, and how to change it, for any widget in the shell.
class ShellScope extends InheritedWidget {
  /// Creates the scope.
  const ShellScope({
    super.key,
    required this.selectedId,
    required this.selectBody,
    required this.clearSelection,
    required super.child,
  });

  /// The body whose panel is open, or null.
  final String? selectedId;

  /// Opens body [id]'s panel.
  final void Function(String id) selectBody;

  /// Closes the panel.
  final VoidCallback clearSelection;

  /// The scope above [context].
  static ShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(ShellScope old) => old.selectedId != selectedId;
}

/// The app's frame: the top bar, the tabs, and the bottom navigation.
///
/// The Map tab is the star map with the selected body's panel: a sheet
/// that drags to full screen below [wideWidth], a [panelWidth] side panel
/// at and above it, hidden until a body is selected.
class Shell extends StatefulWidget {
  /// Creates the shell.
  const Shell({super.key});

  /// Width from which the panel sits beside the map.
  static const double wideWidth = 840;

  /// The side panel's width.
  static const double panelWidth = 400;

  /// Key of the side panel, for tests.
  static const Key sidePanelKey = ValueKey('planet-side-panel');

  /// Key of the phone sheet, for tests.
  static const Key sheetKey = ValueKey('planet-sheet');

  @override
  State<Shell> createState() => _ShellState();
}

enum _Tab {
  map('Map', Icons.public),
  production('Production', Icons.factory_outlined),
  crew('Crew', Icons.groups_outlined),
  trade('Trade', Icons.swap_horiz);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ShellState extends State<Shell> {
  _Tab _tab = _Tab.map;
  String? _selected;

  /// Whether the phone sheet covers the whole map.
  bool _mapCovered = false;

  void _select(String id) => setState(() => _selected = id);

  void _clear() => setState(() {
    _selected = null;
    _mapCovered = false;
  });

  void _onCovered(bool covered) {
    if (covered != _mapCovered) setState(() => _mapCovered = covered);
  }

  @override
  Widget build(BuildContext context) {
    return ShellScope(
      selectedId: _selected,
      selectBody: _select,
      clearSelection: _clear,
      // Back closes the selected body's panel before it leaves the app.
      child: PopScope(
        canPop: _selected == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _clear();
        },
        child: _frame(context),
      ),
    );
  }

  Widget _frame(BuildContext context) {
    return AwaySummaryGate(
      child: Scaffold(
        body: Column(
          children: [
            TopBar(onSettings: () => showSettingsSheet(context)),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: [
                  for (final t in _Tab.values)
                    // Only the shown tab's animations run.
                    TickerMode(enabled: t == _tab, child: _tabBody(t)),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab.index,
          onDestinationSelected: (i) => setState(() => _tab = _Tab.values[i]),
          destinations: [
            for (final t in _Tab.values)
              NavigationDestination(icon: Icon(t.icon), label: t.label),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(_Tab t) => switch (t) {
    _Tab.map => _MapTab(
      selectedId: _selected,
      onSelect: _select,
      covered: _mapCovered,
      onCovered: _onCovered,
    ),
    // Tasks 7 and 8 fill these.
    _Tab.production || _Tab.crew || _Tab.trade => Center(
      key: ValueKey('tab-${t.label}'),
      child: Text('${t.label} is on its way'),
    ),
  };
}

class _MapTab extends StatelessWidget {
  const _MapTab({
    required this.selectedId,
    required this.onSelect,
    required this.covered,
    required this.onCovered,
  });

  /// Extent from which the sheet counts as covering the map.
  static const double _fullExtent = 0.99;

  final String? selectedId;
  final void Function(String id) onSelect;

  /// Whether the sheet covers the whole map, so its animation can stop.
  final bool covered;

  /// Reports whether the sheet now covers the whole map.
  final void Function(bool covered) onCovered;

  @override
  Widget build(BuildContext context) {
    final map = StarMap(
      controller: ControllerScope.of(context),
      selectedId: selectedId,
      onSelect: onSelect,
      // Task 10 opens the Projects tab's Survey row here.
      onSignalTap: (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Surveys arrive with the Projects tab')),
      ),
    );
    final id = selectedId;
    if (MediaQuery.sizeOf(context).width >= Shell.wideWidth) {
      return Row(
        children: [
          Expanded(child: map),
          if (id != null)
            SizedBox(
              key: Shell.sidePanelKey,
              width: Shell.panelWidth,
              child: _PanelPlaceholder(bodyId: id),
            ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          // Nothing of the map shows under a full sheet: no need to animate.
          child: TickerMode(enabled: !covered, child: map),
        ),
        if (id != null)
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              onCovered(n.extent >= _fullExtent);
              return false;
            },
            child: DraggableScrollableSheet(
              key: Shell.sheetKey,
              initialChildSize: 0.45,
              minChildSize: 0.2,
              maxChildSize: 1,
              builder: (context, scroll) =>
                  _PanelPlaceholder(bodyId: id, scroll: scroll),
            ),
          ),
      ],
    );
  }
}

/// The selected body's panel until Mission Control lands (Task 6): its
/// name and type, and a close button.
class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder({required this.bodyId, this.scroll});

  final String bodyId;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final view = bodyView(ControllerScope.of(context), bodyId);
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.panel,
      shape: const Border(top: BorderSide(color: Palette.border)),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(view?.name ?? bodyId, style: text.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: ShellScope.of(context).clearSelection,
              ),
            ],
          ),
          if (view != null)
            Text(
              '${view.typeName} · ${view.owned ? 'Yours' : 'Unclaimed'}',
              style: text.bodyMedium?.copyWith(color: Palette.muted),
            ),
          const SizedBox(height: 16),
          Text(
            'Mission Control for this body is on its way.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}
