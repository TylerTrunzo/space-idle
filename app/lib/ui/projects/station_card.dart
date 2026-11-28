import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/spend_confirm.dart';
import 'package:space_idle/view/messages.dart';
import 'package:space_idle/view/project_views.dart';

/// A megaproject's card: its level and bonuses, the stage under way with
/// its countdown, a line per cost entry with its Deliver button, "Deliver
/// all goods", how it is fed on its own, and what holds it back.
///
/// A Deliver button sends from the body holding the most; a long press
/// (or the button beside it) picks the body. Credits over half of those
/// held take a second tap.
class MegaprojectCard extends StatelessWidget {
  /// Creates the card for [view].
  const MegaprojectCard({
    super.key,
    required this.view,
    required this.onGoToContract,
  });

  /// The megaproject.
  final MegaprojectView view;

  /// Shows contract [id]'s card, for a contract holding its goods.
  final void Function(String id) onGoToContract;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final v = view;
    final running = v.running;
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
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.account_balance_outlined, color: Palette.cyan),
                Text(v.name, style: text.titleMedium),
                Text('level ${v.level}', style: monoText(text.bodyMedium)),
              ],
            ),
            Text(
              key: ValueKey('mp-now-${v.id}'),
              'Now: ${v.currentBonus ?? 'no bonus yet'}',
              style: text.bodyMedium,
            ),
            Text(
              'Level ${v.deliveryLevel + 1}: ${v.nextBonus}',
              style: text.bodyMedium,
            ),
            if (v.locked case final why?) BlockedReason(why),
            if (running != null)
              Padding(
                key: ValueKey('mp-running-${v.id}'),
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${v.level + 1} under way: ${running.remaining} '
                      'left',
                      style: monoText(text.bodyMedium),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: running.progress,
                      color: Palette.cyan,
                      backgroundColor: Palette.border,
                      semanticsLabel:
                          '${running.title}, ${running.remaining} left',
                      semanticsValue: '${(running.progress * 100).floor()}%',
                    ),
                    if (v.runningBonus case final b?)
                      Text('When done: $b', style: muted),
                  ],
                ),
              ),
            if (v.queued)
              _Note(
                key: ValueKey('mp-queued-${v.id}'),
                icon: Icons.queue,
                color: Palette.green,
                text:
                    'Level ${v.deliveryLevel + 1} is paid for and '
                    'queued: starts when this stage finishes',
              )
            else if (running != null && v.takesDeliveries)
              Text(
                'Deliveries now count toward level ${v.deliveryLevel + 1}',
                style: muted,
              ),
            if (v.unfunded)
              _Note(
                key: ValueKey('mp-unfunded-${v.id}'),
                icon: Icons.money_off,
                color: Palette.amber,
                text:
                    'Not funded: you set it to take goods on its own with '
                    'credit auto-pay off, and no credits have gone into this '
                    'stage. Turn credits on below, or deliver credits by '
                    'hand, to fund it.',
              ),
            for (final b in v.blocks)
              Padding(
                key: ValueKey('mp-block-${v.id}-${b.contractId}'),
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Note(
                      icon: Icons.assignment_late_outlined,
                      color: Palette.amber,
                      text: b.text,
                    ),
                    TextButton(
                      key: ValueKey('mp-block-go-${v.id}-${b.contractId}'),
                      onPressed: () => onGoToContract(b.contractId),
                      child: const Text('Go to the contract'),
                    ),
                  ],
                ),
              ),
            if (v.takesDeliveries) ...[
              const SizedBox(height: 8),
              for (final l in v.lines) _LineRow(view: v, line: l),
              if (v.deliverAll case final all?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FilledButton.icon(
                        key: ValueKey('mp-all-${v.id}'),
                        icon: const Icon(Icons.move_to_inbox),
                        label: const Text('Deliver all goods'),
                        onPressed: () => _deliverAll(context, c),
                      ),
                      Text('Hands over $all from your bodies', style: muted),
                    ],
                  ),
                ),
            ],
            const Divider(color: Palette.border),
            _AutoSettings(view: v),
          ],
        ),
      ),
    );
  }

  /// Sends the goods the stage still owes from every owned body, one body
  /// at a time, and reports them in one message.
  ///
  /// The debt is taken once, for the stage the card shows, and each
  /// delivery comes off it: once the stage is paid (it starts, or queues
  /// behind the one under way) the next stage's cost is never paid into.
  void _deliverAll(BuildContext context, GameController c) {
    final m = c.content.megaprojects[view.id];
    if (m == null) return;
    final one = BigNum.from(1);
    final level = megaprojectDeliveryLevel(c.state, c.playerId, m);
    final owed = {
      for (final MapEntry(key: id, value: v) in megaprojectRemaining(
        c.state,
        c.content,
        c.playerId,
        m,
      ).entries)
        if (id != creditsKey) id: v,
    };
    final said = <String>[];
    for (final b in [...c.state.bodies]) {
      if (b.ownerId != c.playerId) continue;
      if (megaprojectDeliveryLevel(c.state, c.playerId, m) != level) break;
      final amounts = {
        for (final MapEntry(key: id, value: v) in owed.entries)
          if ((b.stock[id] ?? const BigNum.zero()).floor().min(v) case final n
              when n >= one)
            id: n,
      };
      if (amounts.isEmpty) continue;
      final cmd = DeliverToMegaprojectCommand(c.playerId, m.id, b.id, amounts);
      final result = c.run(cmd);
      switch (result) {
        case CommandFailed():
          said.add('From ${b.name}: ${c.lastError ?? 'nothing delivered'}');
        case CommandOk(:final outcome):
          if (outcome != null) {
            said.add(
              'From ${b.name}: '
              '${outcomeMessage(c.state, c.content, cmd, outcome)}',
            );
          }
          if (outcome case final MegaprojectDelivered d) {
            for (final MapEntry(key: id, value: v) in d.delivered.entries) {
              if (owed[id] case final left?) owed[id] = left - v;
            }
            if (d.stageStarted || d.queued) break;
          }
      }
      if (owed.values.every((v) => v < one)) break;
    }
    if (said.isNotEmpty) showCommandMessage(context, said.join('\n'));
  }
}

/// One cost line: delivered of needed, its bar, and its Deliver button.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.view, required this.line});

  final MegaprojectView view;
  final MegaprojectLine line;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final l = line;
    final paid = l.owed < BigNum.from(1);
    return Padding(
      key: ValueKey('mp-line-${view.id}-${l.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: text.bodyMedium,
              children: [
                TextSpan(text: '${l.name}: '),
                TextSpan(
                  text: '${l.delivered} of ${l.needed}',
                  style: monoText(text.bodyMedium),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: l.fill,
            color: paid ? Palette.green : Palette.cyan,
            backgroundColor: Palette.border,
            semanticsLabel:
                '${view.name} ${l.name}, ${l.delivered} of ${l.needed}',
            semanticsValue: '${(l.fill * 100).floor()}%',
          ),
          if (paid)
            const _Note(
              icon: Icons.check_circle_outline,
              color: Palette.green,
              text: 'Paid',
            )
          else if (l.id == creditsKey)
            _credits(context, c)
          else if (l.holders.isEmpty)
            Text('None on your bodies', style: muted)
          else
            _goods(context, c),
        ],
      ),
    );
  }

  Widget _credits(BuildContext context, GameController c) {
    final held = c.state.faction(c.playerId).credits.floor();
    final amount = held.min(line.owed);
    final from = _firstOwned(c);
    final can = amount >= BigNum.from(1) && from != null;
    return SpendConfirm(
      id: 'mp-${view.id}-credits',
      builder: (context, ask) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _creditsButton(context, c, ask, amount, from, can: can),
          if (!can)
            BlockedReason(
              from == null
                  ? 'No body of yours to deliver from'
                  : 'No credits to deliver',
            ),
        ],
      ),
    );
  }

  Widget _creditsButton(
    BuildContext context,
    GameController c,
    void Function(Spend) ask,
    BigNum amount,
    String? from, {
    required bool can,
  }) {
    return OutlinedButton(
      key: ValueKey('mp-deliver-${view.id}-credits'),
      onPressed: can && from != null
          ? () => ask(
              Spend(
                price: amount,
                what: 'on ${view.name} level ${view.deliveryLevel + 1}',
                run: () => runAndReport(
                  context,
                  c,
                  DeliverToMegaprojectCommand(c.playerId, view.id, from, {
                    creditsKey: amount,
                  }),
                  announce: true,
                ),
              ),
            )
          : null,
      child: Text('Deliver ${formatNumber(amount)} credits'),
    );
  }

  Widget _goods(BuildContext context, GameController c) {
    final best = line.holders.first;
    void send(String bodyId, BigNum units) => runAndReport(
      context,
      c,
      DeliverToMegaprojectCommand(c.playerId, view.id, bodyId, {
        line.id: units,
      }),
      announce: true,
    );
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MergeSemantics(
          child: Semantics(
            onLongPressHint: 'choose the body',
            child: OutlinedButton(
              key: ValueKey('mp-deliver-${view.id}-${line.id}'),
              onPressed: () => send(best.bodyId, best.units),
              onLongPress: () => _pick(context, send),
              child: Text('Deliver ${best.amount} from ${best.bodyName}'),
            ),
          ),
        ),
        if (line.holders.length > 1)
          IconButton(
            key: ValueKey('mp-choose-${view.id}-${line.id}'),
            icon: const Icon(Icons.more_horiz),
            tooltip: 'Deliver ${line.name} from another body',
            onPressed: () => _pick(context, send),
          ),
      ],
    );
  }

  /// The body picker: every owned body holding the good, with what it
  /// would give.
  Future<void> _pick(
    BuildContext context,
    void Function(String bodyId, BigNum units) send,
  ) async {
    final picked = await showModalBottomSheet<HolderLine>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                'Deliver ${line.name} from',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final h in line.holders)
              ListTile(
                key: ValueKey('mp-pick-${view.id}-${line.id}-${h.bodyId}'),
                leading: const Icon(Icons.public),
                title: Text(h.bodyName),
                trailing: Text(h.amount, style: monoText(null)),
                onTap: () => Navigator.of(context).pop(h),
              ),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) send(picked.bodyId, picked.units);
  }
}

String? _firstOwned(GameController c) =>
    c.state.bodies.where((b) => b.ownerId == c.playerId).firstOrNull?.id;

/// How the megaproject is fed on its own: the goods mode, credits from
/// auto-pay and their weight, and whether goods go in now and why.
class _AutoSettings extends StatelessWidget {
  const _AutoSettings({required this.view});

  final MegaprojectView view;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final v = view;
    final a = v.auto;
    void set({GoodsFeedMode? goods, bool? credits, int? weight}) =>
        runAndReport(
          context,
          c,
          SetMegaprojectAutoCommand(
            c.playerId,
            v.id,
            goods: goods ?? a.goods,
            credits: credits ?? a.credits,
            creditWeight: weight ?? a.creditWeight,
          ),
          announce: true,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('On its own', style: text.titleSmall),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (mode, label) in const [
              (GoodsFeedMode.off, 'Goods off'),
              (GoodsFeedMode.nearReady, 'Near ready'),
              (GoodsFeedMode.always, 'Always'),
            ])
              ChoiceChip(
                key: ValueKey('mp-goods-${v.id}-${mode.name}'),
                label: Text(label),
                selected: a.goods == mode,
                onSelected: a.goods == mode ? null : (_) => set(goods: mode),
              ),
          ],
        ),
        _Note(
          key: ValueKey('mp-feed-${v.id}'),
          icon: a.goodsFedNow ? Icons.input : Icons.pause_circle_outline,
          color: a.goodsFedNow ? Palette.green : Palette.muted,
          text: v.feed,
        ),
        Row(
          children: [
            Switch(
              key: ValueKey('mp-credits-${v.id}'),
              value: a.credits,
              onChanged: (on) => set(credits: on),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Credits from auto-pay')),
          ],
        ),
        if (a.credits)
          Row(
            children: [
              IconButton(
                key: ValueKey('mp-weight-down-${v.id}'),
                icon: const Icon(Icons.remove),
                tooltip: 'Lower its share of the credits',
                onPressed: a.creditWeight > MegaprojectAuto.minCreditWeight
                    ? () => set(weight: a.creditWeight - 1)
                    : null,
              ),
              Expanded(
                child: Text(
                  'Credit weight ${a.creditWeight} of '
                  '${MegaprojectAuto.maxCreditWeight}',
                  style: monoText(text.bodyMedium),
                ),
              ),
              IconButton(
                key: ValueKey('mp-weight-up-${v.id}'),
                icon: const Icon(Icons.add),
                tooltip: 'Raise its share of the credits',
                onPressed: a.creditWeight < MegaprojectAuto.maxCreditWeight
                    ? () => set(weight: a.creditWeight + 1)
                    : null,
              ),
            ],
          ),
      ],
    );
  }
}

/// An icon and a line of text: state told by both, never colour alone.
class _Note extends StatelessWidget {
  const _Note({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
