import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/build_picker.dart';
import 'package:space_idle/ui/planet/building_row.dart';
import 'package:space_idle/ui/planet/claim_section.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/view/body_actions_view.dart';
import 'package:space_idle/view/view_models.dart';

/// Mission Control for one body: in the phone sheet or the wide side
/// panel.
///
/// An owned body shows Buy max, its slot expansion, its buildings and the
/// Build button; an unowned one its deposits and how to claim it. Every
/// figure comes from the view models and every change goes through the
/// game controller.
class PlanetPanel extends StatefulWidget {
  /// Creates the panel for [bodyId].
  const PlanetPanel({
    super.key,
    required this.bodyId,
    this.scroll,
    this.onClose,
  });

  /// The body shown.
  final String bodyId;

  /// The sheet's scroll controller, so dragging the content drags it.
  final ScrollController? scroll;

  /// Closes the panel; null hides the close button.
  final VoidCallback? onClose;

  @override
  State<PlanetPanel> createState() => _PlanetPanelState();
}

class _PlanetPanelState extends State<PlanetPanel> {
  /// Buy max is waiting for its second, confirming tap.
  bool _confirmBuyMax = false;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final view = bodyView(c, widget.bodyId);
    final text = Theme.of(context).textTheme;
    return Material(
      color: Palette.panel,
      shape: const Border(top: BorderSide(color: Palette.border)),
      child: ListView(
        controller: widget.scroll,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 24),
        children: [
          _Header(view: view, bodyId: widget.bodyId, onClose: widget.onClose),
          if (view == null)
            Text(
              'Nothing is known about this body yet.',
              style: text.bodyMedium,
            )
          else if (view.owned) ...[
            _buyMax(context),
            if (expandSlotsView(c, view.id) case final slots?)
              _ExpandSlots(view: slots, bodyId: view.id),
            const Divider(color: Palette.border),
            for (final b in view.buildings) BuildingRow(view: b),
            const SizedBox(height: 8),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: BuildPicker(),
            ),
            const SizedBox(height: 16),
            Text(
              'Storage and routes for this body are on their way.',
              style: text.bodySmall?.copyWith(color: Palette.muted),
            ),
          ] else
            ClaimSection(view: view),
        ],
      ),
    );
  }

  /// Buy max: what it would buy and cost, a second tap above half the
  /// credits, and the reason when it would buy nothing.
  Widget _buyMax(BuildContext context) {
    final c = ControllerScope.of(context);
    final v = buyMaxView(c);
    final mono = monoText(Theme.of(context).textTheme.bodyMedium);
    void buy() {
      setState(() => _confirmBuyMax = false);
      runAndReport(
        context,
        c,
        BuyUpgradesCommand(c.playerId, c.state.faction(c.playerId).credits),
        announce: true,
      );
    }

    final levels = v.levels == 1 ? '1 level' : '${v.levels} levels';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(
            key: const ValueKey('buy-max'),
            onPressed: v.levels == 0
                ? null
                : () =>
                      v.confirm ? setState(() => _confirmBuyMax = true) : buy(),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Buy max upgrades  '),
                  TextSpan(text: '$levels · ${v.cost} credits', style: mono),
                ],
              ),
            ),
          ),
          if (v.blockedReason case final why?)
            Text(
              'Buy max: $why',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Palette.muted),
            ),
          if (_confirmBuyMax && v.levels > 0)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Spend ${v.cost} of '
                  '${formatNumber(c.state.faction(c.playerId).credits)} '
                  'credits on $levels?',
                ),
                FilledButton(
                  key: const ValueKey('buy-max-confirm'),
                  onPressed: buy,
                  child: const Text('Buy'),
                ),
                TextButton(
                  onPressed: () => setState(() => _confirmBuyMax = false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The body's name, type and slots, and the close button.
class _Header extends StatelessWidget {
  const _Header({required this.view, required this.bodyId, this.onClose});

  final BodyView? view;
  final String bodyId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(v?.name ?? bodyId, style: text.titleLarge)),
            if (onClose case final close?)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: close,
              ),
          ],
        ),
        if (v != null)
          Text(
            '${v.typeName} · ${v.owned ? 'Yours' : 'Unclaimed'} · '
            '${v.slotsUsed}/${v.slotsTotal} slots',
            style: text.bodyMedium?.copyWith(color: Palette.muted),
          ),
      ],
    );
  }
}

/// "Expand slots (+1)": its price and time, or the slot under way.
class _ExpandSlots extends StatelessWidget {
  const _ExpandSlots({required this.view, required this.bodyId});

  final ExpandSlotsView view;
  final String bodyId;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    if (view.running case final p?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.title}… ${p.remaining} left', style: text.bodyMedium),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: p.progress),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(
            key: const ValueKey('expand-slots'),
            onPressed: view.affordable
                ? () => runAndReport(
                    context,
                    c,
                    ExpandSlotsCommand(c.playerId, bodyId),
                    announce: true,
                  )
                : null,
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Expand slots (+1)  '),
                  TextSpan(
                    text: '${view.cost} · ${view.time}',
                    style: monoText(text.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
          if (view.blockedReason case final why?)
            Text(why, style: text.bodySmall?.copyWith(color: Palette.muted)),
        ],
      ),
    );
  }
}
