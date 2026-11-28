import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/lazy_list.dart';
import 'package:space_idle/ui/planet/build_picker.dart';
import 'package:space_idle/ui/planet/building_row.dart';
import 'package:space_idle/ui/planet/claim_section.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/routes_section.dart';
import 'package:space_idle/ui/planet/spend_confirm.dart';
import 'package:space_idle/ui/planet/storage_section.dart';
import 'package:space_idle/view/body_actions_view.dart';
import 'package:space_idle/view/view_models.dart';

/// Mission Control for one body: in the phone sheet or the wide side
/// panel.
///
/// An owned body shows its slot expansion, its buildings and the Build
/// button; an unowned one its deposits and how to claim it. Every figure
/// comes from the view models and every change goes through the game
/// controller. (Buy max spends across every body, so it is in the top
/// bar.)
class PlanetPanel extends StatelessWidget {
  /// Creates the panel for [bodyId].
  const PlanetPanel({
    super.key,
    required this.bodyId,
    this.scroll,
    this.onClose,
    this.onHeaderTap,
  });

  /// The body shown.
  final String bodyId;

  /// The sheet's scroll controller, so dragging the content drags it.
  final ScrollController? scroll;

  /// Closes the panel; null hides the close button.
  final VoidCallback? onClose;

  /// A tap on the header (the phone sheet opens or shrinks); null for
  /// none.
  final VoidCallback? onHeaderTap;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final view = bodyView(c, bodyId);
    final text = Theme.of(context).textTheme;
    // A lazy list: only the rows on screen (and its cache extent) are
    // built, so only their payback lines ask for previews; keyed rows keep
    // their state as rows above them come and go.
    final items = <Widget>[
      _Header(view: view, bodyId: bodyId, onClose: onClose, onTap: onHeaderTap),
      if (view == null)
        Text('Nothing is known about this body yet.', style: text.bodyMedium)
      else if (view.owned) ...[
        if (expandSlotsView(c, view.id) case final slots?)
          _ExpandSlots(view: slots, bodyId: view.id, bodyName: view.name),
        const Divider(color: Palette.border),
        // Keyed by building, so a pending confirm stays with its own.
        for (final b in view.buildings)
          BuildingRow(key: ValueKey(b.id), view: b),
        const SizedBox(height: 8),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: BuildPicker(),
        ),
        const SizedBox(height: 16),
        const Divider(color: Palette.border),
        StorageSection(view: view),
        const Divider(color: Palette.border),
        RoutesSection(view: view),
      ] else
        ClaimSection(view: view),
    ];
    return Material(
      color: Palette.panel,
      shape: const Border(top: BorderSide(color: Palette.border)),
      child: LazyList(
        controller: scroll,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 24),
        items: items,
      ),
    );
  }
}

/// The body's name, type and slots, and the close button.
class _Header extends StatelessWidget {
  const _Header({
    required this.view,
    required this.bodyId,
    this.onClose,
    this.onTap,
  });

  final BodyView? view;
  final String bodyId;
  final VoidCallback? onClose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Semantics(
                  onTapHint: onTap == null ? null : 'show more or less',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(v?.name ?? bodyId, style: text.titleLarge),
                    ),
                  ),
                ),
              ),
            ),
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
  const _ExpandSlots({
    required this.view,
    required this.bodyId,
    required this.bodyName,
  });

  final ExpandSlotsView view;
  final String bodyId;
  final String bodyName;

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
          SpendConfirm(
            id: 'expand-slots',
            builder: (context, ask) => OutlinedButton(
              key: const ValueKey('expand-slots'),
              onPressed: view.affordable
                  ? () => ask(
                      Spend(
                        price: view.price,
                        what: 'on a build slot on $bodyName',
                        run: () => runAndReport(
                          context,
                          c,
                          ExpandSlotsCommand(c.playerId, bodyId),
                          announce: true,
                        ),
                      ),
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
          ),
          if (view.blockedReason case final why?) BlockedReason(why),
        ],
      ),
    );
  }
}
