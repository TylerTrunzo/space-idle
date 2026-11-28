import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/routes_section.dart';
import 'package:space_idle/view/tabs_view.dart';

/// The market and the player's trade (b8, b10): every resource at the
/// price the player's own sales earn (the core's `salePrice`, bonuses
/// included), how saturated the market is, and what net production of it
/// is worth an hour; the auto-sell rules, each removable; and every route,
/// as a body's panel shows it.
///
/// Selling is on a body's panel, where the stock is.
class TradeTab extends StatelessWidget {
  /// Creates the tab.
  const TradeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final view = tradeView(c);
    final text = Theme.of(context).textTheme;
    final mono = monoText(text.bodyMedium);
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final items = <Widget>[
      Text('Market', style: text.titleLarge),
      for (final m in view.market)
        Padding(
          key: ValueKey('market-${m.id}'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(m.name, style: text.titleSmall),
                  Text('${m.price} credits each', style: mono),
                  if (m.worthPerHour case final w?)
                    Text(
                      w,
                      style: mono.copyWith(
                        color: w.startsWith('-') ? Palette.red : Palette.green,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: m.saturation,
                color: m.saturation < 0.5 ? Palette.amber : Palette.cyan,
                backgroundColor: Palette.border,
              ),
              Text(m.saturationText, style: muted),
            ],
          ),
        ),
      const Divider(color: Palette.border),
      Text('Auto-sell', style: text.titleMedium),
      if (view.rules.isEmpty)
        Text(
          'No auto-sell rules: turn one on in a body\'s storage.',
          style: muted,
        ),
      for (final r in view.rules)
        Padding(
          key: ValueKey('rule-${r.bodyId}-${r.resourceId}'),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${r.resourceName} on ${r.bodyName}, keeps ',
                      ),
                      TextSpan(text: r.keep, style: mono),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('rule-remove-${r.bodyId}-${r.resourceId}'),
                icon: const Icon(Icons.close),
                tooltip: 'Stop auto-selling ${r.resourceName} on ${r.bodyName}',
                onPressed: () => runAndReport(
                  context,
                  c,
                  SetAutoSellCommand(c.playerId, r.bodyId, r.resourceId, null),
                  announce: true,
                ),
              ),
            ],
          ),
        ),
      const Divider(color: Palette.border),
      Text('Routes', style: text.titleMedium),
      if (view.routes.isEmpty)
        Text('No routes yet: open one from a body\'s panel.', style: muted),
      for (final r in view.routes)
        RouteCard(key: ValueKey('route-${r.id}'), view: r),
    ];
    return ColoredBox(
      color: Palette.panel,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, i) => items[i],
      ),
    );
  }
}
