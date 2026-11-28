import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/view/project_views.dart';

/// A contract on the board: what it asks for, how far along it is, the
/// reward, a Deliver button per owned body holding the good, "Deliver
/// all" behind a preview of what each body gives, and Discard behind an
/// inline confirm. Contracts never expire, so there is no timer.
class ContractCard extends StatefulWidget {
  /// Creates the card for [view].
  const ContractCard({super.key, required this.view});

  /// The contract.
  final ContractView view;

  @override
  State<ContractCard> createState() => _ContractCardState();
}

class _ContractCardState extends State<ContractCard> {
  /// What "Deliver all" would do, while it waits for a Confirm.
  ContractPreview? _preview;

  /// Whether Discard waits for its second tap.
  bool _discarding = false;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final mono = monoText(text.bodyMedium);
    final v = widget.view;
    return Card(
      color: Palette.background,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined, color: Palette.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${v.title}: ${v.quantity} ${v.resourceName}',
                    style: text.titleSmall,
                  ),
                ),
              ],
            ),
            Text.rich(
              TextSpan(
                style: text.bodyMedium,
                children: [
                  const TextSpan(text: 'Pays '),
                  TextSpan(text: '${v.reward} credits', style: mono),
                  const TextSpan(text: ' on completion'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text('${v.delivered} of ${v.quantity} delivered', style: mono),
            LinearProgressIndicator(
              value: v.fill,
              color: Palette.cyan,
              backgroundColor: Palette.border,
              semanticsLabel:
                  '${v.title} ${v.resourceName}, ${v.delivered} of '
                  '${v.quantity} delivered',
              semanticsValue: '${(v.fill * 100).floor()}%',
            ),
            const SizedBox(height: 8),
            if (v.sources.isEmpty)
              Text('None of your bodies holds ${v.resourceName}', style: muted)
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in v.sources)
                    OutlinedButton(
                      key: ValueKey('contract-deliver-${v.id}-${s.bodyId}'),
                      onPressed: () => runAndReport(
                        context,
                        c,
                        DeliverContractCommand(
                          c.playerId,
                          v.id,
                          s.bodyId,
                          s.units,
                        ),
                        announce: true,
                      ),
                      child: Text('Deliver ${s.amount} from ${s.bodyName}'),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  key: ValueKey('contract-all-${v.id}'),
                  icon: const Icon(Icons.move_to_inbox),
                  label: const Text('Deliver all'),
                  // A copy of the state, once, on the tap.
                  onPressed: () => setState(() {
                    _discarding = false;
                    _preview = contractDeliverAllPreview(c, v.id);
                  }),
                ),
                TextButton.icon(
                  key: ValueKey('contract-discard-${v.id}'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard'),
                  onPressed: () => setState(() {
                    _preview = null;
                    _discarding = true;
                  }),
                ),
              ],
            ),
            if (_preview case final p?) _previewBox(context, p),
            if (_discarding)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'Discard this contract? What it has been delivered '
                        'is lost.',
                      ),
                    ),
                    FilledButton(
                      key: ValueKey('contract-discard-confirm-${v.id}'),
                      onPressed: () {
                        setState(() => _discarding = false);
                        runAndReport(
                          context,
                          c,
                          DiscardContractCommand(c.playerId, v.id),
                          announce: true,
                        );
                      },
                      child: const Text('Discard'),
                    ),
                    TextButton(
                      key: ValueKey('contract-discard-cancel-${v.id}'),
                      onPressed: () => setState(() => _discarding = false),
                      child: const Text('Keep it'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewBox(BuildContext context, ContractPreview p) {
    final c = ControllerScope.of(context);
    final v = widget.view;
    final cancel = TextButton(
      key: ValueKey('contract-all-cancel-${v.id}'),
      onPressed: () => setState(() => _preview = null),
      child: const Text('Cancel'),
    );
    return Padding(
      key: ValueKey('contract-preview-${v.id}'),
      padding: const EdgeInsets.only(top: 4),
      child: Semantics(
        liveRegion: true,
        child: switch (p) {
          ContractPreviewFailed(:final message) => Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [Text(message), cancel],
          ),
          ContractPreviewReady(:final gives, :final total, :final warnings) =>
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deliver $total: '
                  '${[for (final g in gives) '${g.value} from ${g.name}'].join(', ')}',
                ),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_outlined,
                          size: 18,
                          color: Palette.amber,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(w)),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      key: ValueKey('contract-all-confirm-${v.id}'),
                      onPressed: () {
                        setState(() => _preview = null);
                        runAndReport(
                          context,
                          c,
                          DeliverContractCommand(
                            c.playerId,
                            v.id,
                            null,
                            v.remaining,
                          ),
                          announce: true,
                        );
                      },
                      child: const Text('Confirm'),
                    ),
                    cancel,
                  ],
                ),
              ],
            ),
        },
      ),
    );
  }
}
