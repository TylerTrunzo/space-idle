import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/ui/away_dialog.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/goals/goal_strip.dart';
import 'package:space_idle/ui/map/star_map.dart';
import 'package:space_idle/ui/milestone_banner.dart';
import 'package:space_idle/ui/planet/planet_panel.dart';
import 'package:space_idle/ui/projects/projects_tab.dart';
import 'package:space_idle/ui/settings_sheet.dart';
import 'package:space_idle/ui/tabs/crew_tab.dart';
import 'package:space_idle/ui/tabs/production_tab.dart';
import 'package:space_idle/ui/tabs/trade_tab.dart';
import 'package:space_idle/ui/top_bar.dart';

/// The selected body, and how to change it, for any widget in the shell.
class ShellScope extends InheritedWidget {
  /// Creates the scope.
  const ShellScope({
    super.key,
    required this.selectedId,
    required this.selectBody,
    required this.clearSelection,
    this.showOnMap,
    this.showProjects,
    required super.child,
  });

  /// The body whose panel is open, or null.
  final String? selectedId;

  /// Opens body [id]'s panel.
  final void Function(String id) selectBody;

  /// Closes the panel.
  final VoidCallback clearSelection;

  /// Switches to the Map tab with body [id] selected; null where the
  /// scope has no tabs to switch ([openOnMap] then only selects).
  final void Function(String id)? showOnMap;

  /// Switches to the Projects tab at a row ([ProjectsAnchor]) with id
  /// [id]; null where the scope has no tabs.
  final void Function(ProjectsAnchor anchor, String id)? showProjects;

  /// Opens body [id]'s panel on the Map tab, from another tab.
  void openOnMap(String id) => (showOnMap ?? selectBody)(id);

  /// Shows the Projects tab's [anchor] row for [id], where there is one.
  void openProjects(ProjectsAnchor anchor, String id) =>
      showProjects?.call(anchor, id);

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
  trade('Trade', Icons.swap_horiz),
  projects('Projects', Icons.assignment_outlined);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _ShellState extends State<Shell> {
  _Tab _tab = _Tab.map;
  String? _selected;

  /// The row the Projects tab shows, from the star map's signal marker or
  /// the away summary; its serial counts the requests.
  ProjectsFocus? _projectsFocus;

  /// Whether the phone sheet covers the whole map.
  bool _mapCovered = false;

  /// How much of the map tab the phone sheet covers, 0 to 1, as it drags;
  /// the map fits the area above it.
  final ValueNotifier<double> _sheetExtent = ValueNotifier(
    _MapTab.initialExtent,
  );

  /// The phone sheet, so a tap on its header can open or shrink it.
  final DraggableScrollableController _sheet = DraggableScrollableController();

  @override
  void dispose() {
    _sheetExtent.dispose();
    _sheet.dispose();
    super.dispose();
  }

  void _select(String id) => setState(() {
    // A sheet that opens starts at its first size.
    if (_selected == null) _sheetExtent.value = _MapTab.initialExtent;
    _selected = id;
  });

  void _clear() => setState(() {
    _selected = null;
    _mapCovered = false;
    _sheetExtent.value = _MapTab.initialExtent;
  });

  /// Opens the phone sheet to full, or a full one back to its first size:
  /// for a mouse or a tap, where a swipe is not to hand.
  void _toggleSheet() {
    if (!_sheet.isAttached) return;
    final to = _sheet.size >= _MapTab.fullExtent ? _MapTab.initialExtent : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheet.jumpTo(to);
    } else {
      _sheet.animateTo(
        to,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// A tap on a system's signal marker: the Projects tab, at that
  /// system's Survey row.
  void _onSignal(String systemId) =>
      _showProjects(ProjectsAnchor.survey, systemId);

  void _showProjects(ProjectsAnchor anchor, String id) => setState(() {
    _tab = _Tab.projects;
    _projectsFocus = ProjectsFocus(
      anchor,
      id,
      (_projectsFocus?.serial ?? 0) + 1,
    );
  });

  void _onCovered(bool covered) {
    if (covered != _mapCovered) setState(() => _mapCovered = covered);
  }

  @override
  Widget build(BuildContext context) {
    // The flag belongs to the phone sheet: wide, there is none, and a
    // sheet made again on narrowing starts below full.
    if (MediaQuery.sizeOf(context).width >= Shell.wideWidth) {
      _mapCovered = false;
    }
    return ShellScope(
      selectedId: _selected,
      selectBody: _select,
      clearSelection: _clear,
      showOnMap: (id) {
        _select(id);
        setState(() => _tab = _Tab.map);
      },
      showProjects: _showProjects,
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
            const GoalStrip(),
            Expanded(
              child: MilestoneBanner(
                child: IndexedStack(
                  index: _tab.index,
                  children: [
                    for (final t in _Tab.values)
                      // Only the shown tab's animations run.
                      TickerMode(enabled: t == _tab, child: _tabBody(t)),
                  ],
                ),
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
      sheetExtent: _sheetExtent,
      sheet: _sheet,
      onHeaderTap: _toggleSheet,
      onSignal: _onSignal,
    ),
    _Tab.production => ProductionTab(key: ValueKey('tab-${t.label}')),
    _Tab.crew => CrewTab(key: ValueKey('tab-${t.label}')),
    _Tab.trade => TradeTab(key: ValueKey('tab-${t.label}')),
    _Tab.projects => ProjectsTab(
      key: ValueKey('tab-${t.label}'),
      focus: _projectsFocus,
    ),
  };
}

class _MapTab extends StatelessWidget {
  const _MapTab({
    required this.selectedId,
    required this.onSelect,
    required this.covered,
    required this.onCovered,
    required this.sheetExtent,
    required this.sheet,
    required this.onHeaderTap,
    required this.onSignal,
  });

  /// A tap on system [systemId]'s signal marker.
  final void Function(String systemId) onSignal;

  /// Extent from which the sheet counts as covering the map.
  static const double _coverExtent = 0.99;

  /// The sheet's size when it opens.
  static const double initialExtent = 0.45;

  /// From this size a header tap shrinks the sheet back.
  static const double fullExtent = 0.9;

  /// The most of the tab the map gives up to the sheet: past it the map
  /// stops shrinking, and the sheet covers the rest of it anyway.
  static const double _mostShrink = 0.8;

  /// How much of the tab the sheet covers now.
  final ValueNotifier<double> sheetExtent;

  /// The sheet's controller.
  final DraggableScrollableController sheet;

  /// A tap on the sheet's header.
  final VoidCallback onHeaderTap;

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
      onSignalTap: onSignal,
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
              child: PlanetPanel(
                // One per body: another body's panel starts with nothing
                // pending or picked.
                key: ValueKey(id),
                bodyId: id,
                onClose: ShellScope.of(context).clearSelection,
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          // The map fits the area above the sheet, so the selected body
          // and its system stay in view while the sheet is open; only this
          // rebuilds as the sheet drags.
          ValueListenableBuilder<double>(
            valueListenable: sheetExtent,
            // Nothing of the map shows under a full sheet: no need to
            // animate.
            child: TickerMode(enabled: !covered, child: map),
            builder: (context, extent, child) => Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: id == null
                  ? 0
                  : box.maxHeight * extent.clamp(0.0, _mostShrink),
              child: child!,
            ),
          ),
          if (id != null)
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                onCovered(n.extent >= _coverExtent);
                sheetExtent.value = n.extent;
                return false;
              },
              child: DraggableScrollableSheet(
                key: Shell.sheetKey,
                controller: sheet,
                initialChildSize: initialExtent,
                minChildSize: 0.2,
                maxChildSize: 1,
                // A mouse drags it too, on the web and desktops.
                builder: (context, scroll) => ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                  child: PlanetPanel(
                    key: ValueKey(id),
                    bodyId: id,
                    scroll: scroll,
                    onClose: ShellScope.of(context).clearSelection,
                    onHeaderTap: onHeaderTap,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
