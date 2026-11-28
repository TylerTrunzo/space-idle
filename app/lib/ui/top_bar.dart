import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/view/body_actions_view.dart';
import 'package:space_idle/view/view_models.dart';

/// The always-visible bar: credits and what they earn a second, crew free
/// of supported, and the three resources held most, ticking live; and
/// Buy max beside the settings.
///
/// Each figure is an icon plus text (never color alone), its numbers in
/// the monospace face. The figures wrap onto more lines rather than
/// overflow, at any text size or number length.
class TopBar extends StatefulWidget {
  /// Creates the bar; [onSettings] opens the settings sheet.
  const TopBar({super.key, required this.onSettings});

  /// Opens the settings sheet.
  final VoidCallback onSettings;

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  /// What Buy max would buy, worked out when it was tapped; null while
  /// it is not asking.
  BuyMaxView? _buyMax;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final view = topBar(c);
    return Material(
      color: Palette.panel,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          _Figure(
                            icon: Icons.paid_outlined,
                            value: view.credits,
                            detail: view.creditsRate,
                            semantics:
                                'Credits ${view.credits}, ${view.creditsRate}',
                          ),
                          _Figure(
                            icon: Icons.groups_outlined,
                            value: '${view.crewFree}/${view.crewTotal}',
                            detail: 'crew',
                            semantics:
                                'Crew: ${view.crewFree} free of '
                                '${view.crewTotal}',
                          ),
                          for (final p in view.pinned)
                            _Figure(
                              icon: Icons.inventory_2_outlined,
                              label: p.name,
                              value: p.value,
                              semantics: '${p.name}: ${p.value}',
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('buy-max'),
                    icon: const Icon(Icons.trending_up),
                    tooltip: 'Buy max',
                    // The preview copies the state: only on a tap.
                    onPressed: () => setState(() => _buyMax = buyMaxView(c)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: widget.onSettings,
                  ),
                ],
              ),
              if (_buyMax case final v?) _buyMaxRow(context, v),
            ],
          ),
        ),
      ),
    );
  }

  /// Buy max's second step: what it buys and costs, or why it buys
  /// nothing. It always asks, since the button shows no price.
  Widget _buyMaxRow(BuildContext context, BuyMaxView v) {
    final c = ControllerScope.of(context);
    void close() => setState(() => _buyMax = null);
    final cancel = TextButton(
      key: const ValueKey('buy-max-cancel'),
      onPressed: close,
      child: Text(v.levels == 0 ? 'OK' : 'Cancel'),
    );
    if (v.blockedReason case final why?) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 12, bottom: 4),
        child: Row(
          children: [
            Expanded(child: BlockedReason('Buy max: $why')),
            cancel,
          ],
        ),
      );
    }
    final held = c.state.faction(c.playerId).credits;
    final levels = v.levels == 1 ? 'upgrade level' : 'upgrade levels';
    final buildings = v.buildings == 1 ? 'building' : 'buildings';
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12, bottom: 4),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              'Buy ${v.levels} $levels on ${v.buildings} $buildings for '
              '${v.cost} of '
              '${formatNumber(held, rounding: NumberRounding.down)} credits?',
            ),
          ),
          FilledButton(
            key: const ValueKey('buy-max-confirm'),
            onPressed: () {
              close();
              // The previewed total is the budget: never more than shown.
              runAndReport(
                context,
                c,
                BuyUpgradesCommand(c.playerId, v.price),
                announce: true,
              );
            },
            child: const Text('Buy'),
          ),
          cancel,
        ],
      ),
    );
  }
}

/// One figure: an icon, an optional label, a monospace value and an
/// optional muted detail, as one wrapping line of text.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.value,
    required this.semantics,
    this.label,
    this.detail,
  });

  final IconData icon;
  final String? label;
  final String value;
  final String? detail;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 18, color: Palette.cyan),
            ),
            if (label case final l?) TextSpan(text: ' $l'),
            TextSpan(text: ' $value', style: monoText(style)),
            if (detail case final d?)
              TextSpan(
                text: ' $d',
                style: monoText(style).copyWith(color: Palette.muted),
              ),
          ],
        ),
      ),
    );
  }
}
