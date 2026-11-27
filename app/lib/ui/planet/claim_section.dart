import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/spend_confirm.dart';
import 'package:space_idle/view/view_models.dart';

/// An unowned body's panel: its deposits and how to claim it, or the claim
/// under way with its countdown.
class ClaimSection extends StatefulWidget {
  /// Creates the section for [view], an unowned body.
  const ClaimSection({super.key, required this.view});

  /// The body.
  final BodyView view;

  @override
  State<ClaimSection> createState() => _ClaimSectionState();
}

class _ClaimSectionState extends State<ClaimSection> {
  /// The body chosen to pay the outpost kits from.
  String? _source;

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final claim = v.claim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Deposits', style: text.titleSmall),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [for (final d in v.depositNames) Chip(label: Text(d))],
        ),
        const SizedBox(height: 12),
        if (claim?.running case final p?) ...[
          Text('Claiming… ${p.remaining} left', style: text.bodyLarge),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: p.progress),
        ] else if (claim != null)
          ..._claim(context, c, claim),
      ],
    );
  }

  List<Widget> _claim(BuildContext context, GameController c, ClaimView claim) {
    final text = Theme.of(context).textTheme;
    final sources = claim.sourceBodyIds;
    final source = sources.contains(_source)
        ? _source
        : (sources.isEmpty ? null : sources.first);
    String name(String id) =>
        c.state.bodies.where((b) => b.id == id).firstOrNull?.name ?? id;
    final kits = claim.kitsNeeded;
    return [
      Text.rich(
        TextSpan(
          style: text.bodyMedium,
          children: [
            const TextSpan(text: 'Claim for '),
            TextSpan(
              text:
                  '${claim.creditsCost} credits'
                  '${kits > 0 ? ' and $kits Outpost Kit' : ''}',
              style: monoText(text.bodyMedium),
            ),
            const TextSpan(text: ', done in '),
            TextSpan(text: claim.time, style: monoText(text.bodyMedium)),
          ],
        ),
      ),
      if (kits > 0 && sources.isNotEmpty)
        // The menu takes the panel's width on a line of its own, and a
        // long body name wraps inside it, at any text size.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kits from'),
              DropdownButton<String>(
                value: source,
                isExpanded: true,
                itemHeight: null,
                items: [
                  for (final id in sources)
                    DropdownMenuItem(value: id, child: Text(name(id))),
                ],
                onChanged: (id) => setState(() => _source = id),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      SpendConfirm(
        id: 'claim',
        builder: (context, ask) => FilledButton.icon(
          key: const ValueKey('claim'),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Claim'),
          onPressed: claim.affordable && source != null
              ? () => ask(
                  Spend(
                    price: claim.price,
                    what: 'to claim ${widget.view.name}',
                    run: () => runAndReport(
                      context,
                      c,
                      ClaimBodyCommand(c.playerId, widget.view.id, source),
                      announce: true,
                    ),
                  ),
                )
              : null,
        ),
      ),
      if (claim.blockedReason case final why?)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 16, color: Palette.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(why, style: const TextStyle(color: Palette.amber)),
              ),
            ],
          ),
        ),
    ];
  }
}
