import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/view/storage_routes_view.dart';
import 'package:space_idle/view/view_models.dart';

/// An owned body's storage: one row per resource it holds, moves or
/// auto-sells, each with its stock against the cap, its net rate, its
/// sale price, Sell, and its auto-sell rule.
class StorageSection extends StatelessWidget {
  /// Creates the section for [view], an owned body.
  const StorageSection({super.key, required this.view});

  /// The body.
  final BodyView view;

  /// The "keep at least" choices an auto-sell rule offers.
  static final List<BigNum> keepChoices = [
    const BigNum.zero(),
    BigNum.from(100),
    BigNum.from(1000),
  ];

  /// What a rule turned on keeps.
  static final BigNum defaultKeep = BigNum.from(100);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Storage', style: text.titleMedium),
        if (view.storage.isEmpty)
          Text(
            'Nothing is stored here yet.',
            style: text.bodyMedium?.copyWith(color: Palette.muted),
          ),
        for (final r in view.storage)
          _StorageRow(
            key: ValueKey('storage-${r.id}'),
            bodyId: view.id,
            row: r,
          ),
      ],
    );
  }
}

class _StorageRow extends StatefulWidget {
  const _StorageRow({super.key, required this.bodyId, required this.row});

  final String bodyId;
  final ResourceRowView row;

  @override
  State<_StorageRow> createState() => _StorageRowState();
}

class _StorageRowState extends State<_StorageRow> {
  /// The open Sell chooser's options, worked out when it opened; null
  /// while it is closed.
  List<SellOption>? _options;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final mono = monoText(text.bodyMedium);
    final muted = text.bodySmall?.copyWith(color: Palette.muted);
    void setRule(BigNum? keep) => runAndReport(
      context,
      c,
      SetAutoSellCommand(c.playerId, widget.bodyId, r.id, keep),
      announce: true,
    );
    final options = _options;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(r.name, style: text.titleSmall)),
              _Net(net: r.net),
            ],
          ),
          Text('${r.amount} / ${r.cap}', style: mono),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: r.fill,
            color: r.alert == StockAlert.full ? Palette.amber : Palette.cyan,
            backgroundColor: Palette.border,
          ),
          if (_alert(r.alert) case (final icon, final color, final line))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(line, style: TextStyle(color: color)),
                  ),
                ],
              ),
            ),
          Text('Sells for ${r.price} credits each', style: muted),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: ValueKey('sell-${r.id}'),
                // The chooser's revenues are dry runs: only on a tap.
                onPressed: r.hasStock
                    ? () => setState(
                        () => _options = sellOptions(c, widget.bodyId, r.id),
                      )
                    : null,
                child: const Text('Sell'),
              ),
              MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      key: ValueKey('autosell-${r.id}'),
                      value: r.autoSell,
                      onChanged: (on) =>
                          setRule(on ? StorageSection.defaultKeep : null),
                    ),
                    const Text('Auto-sell'),
                  ],
                ),
              ),
            ],
          ),
          if (r.autoSell)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Keep at least'),
                for (final k in StorageSection.keepChoices)
                  ChoiceChip(
                    key: ValueKey('keep-${r.id}-${k.toDouble().round()}'),
                    label: Text(formatNumber(k)),
                    selected: r.keepAtLeast == k,
                    onSelected: (_) => setRule(k),
                  ),
              ],
            ),
          if (r.held case final held?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.inventory_outlined,
                    size: 16,
                    color: Palette.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(held, style: muted)),
                ],
              ),
            ),
          if (options != null) _chooser(context, options),
        ],
      ),
    );
  }

  /// The Sell chooser: each part with what it earns, so the revenue
  /// shows before the sale.
  Widget _chooser(BuildContext context, List<SellOption> options) {
    final r = widget.row;
    final c = ControllerScope.of(context);
    void close() => setState(() => _options = null);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final o in options)
            OutlinedButton(
              key: ValueKey(
                'sell-${r.id}-${o.label == 'All' ? 'all' : o.label.replaceAll('%', '')}',
              ),
              onPressed: () {
                close();
                runAndReport(
                  context,
                  c,
                  SellCommand(c.playerId, widget.bodyId, r.id, o.amount),
                  announce: true,
                );
              },
              child: Text(
                '${o.label}: ${o.amountText} for ${o.revenue} credits',
              ),
            ),
          TextButton(onPressed: close, child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// What a store's warning looks like: icon, colour and words.
  (IconData, Color, String)? _alert(StockAlert a) => switch (a) {
    StockAlert.none => null,
    StockAlert.full => (
      Icons.warning_amber_outlined,
      Palette.amber,
      'Full: more is made than it can hold',
    ),
    StockAlert.runningOut => (
      Icons.error_outline,
      Palette.red,
      'Running out within 10 minutes',
    ),
  };
}

/// The net rate with an arrow, so its direction is not told by colour
/// alone.
class _Net extends StatelessWidget {
  const _Net({required this.net});

  final String net;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = net.startsWith('+')
        ? (Icons.arrow_upward, Palette.green)
        : net.startsWith('-')
        ? (Icons.arrow_downward, Palette.red)
        : (Icons.remove, Palette.muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        Text(net, style: monoText(Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
