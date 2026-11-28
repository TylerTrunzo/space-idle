import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/view/storage_routes_view.dart';
import 'package:space_idle/view/view_models.dart';

/// Which form the routes section has open.
enum _Form { none, route, ships }

/// An owned body's routes, out and in: each with its rate, ships and
/// trip, what it can carry and what holds it, whether it is moving, and
/// its stop level; and the New route and Move ships forms.
///
/// The forms check nothing themselves but that a number is a number: they
/// run the command and show the core's reason when it refuses (b10).
class RoutesSection extends StatefulWidget {
  /// Creates the section for [view], an owned body.
  const RoutesSection({super.key, required this.view});

  /// The body.
  final BodyView view;

  @override
  State<RoutesSection> createState() => _RoutesSectionState();
}

class _RoutesSectionState extends State<RoutesSection> {
  _Form _form = _Form.none;

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final form = routeForm(c, v.id);
    void close() => setState(() => _form = _Form.none);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Routes', style: text.titleMedium),
        if (v.routesOut.isEmpty && v.routesIn.isEmpty)
          Text('No routes yet.', style: muted),
        for (final r in v.routesOut)
          _RouteCard(key: ValueKey('route-${r.id}'), view: r),
        for (final r in v.routesIn)
          _RouteCard(key: ValueKey('route-${r.id}'), view: r),
        const SizedBox(height: 8),
        if (form.destinations.isEmpty)
          Text(
            'Claim another body in this system to open a route or move '
            'ships to it.',
            style: muted,
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('new-route'),
                icon: const Icon(Icons.alt_route),
                label: const Text('New route'),
                onPressed: () => setState(() => _form = _Form.route),
              ),
              OutlinedButton.icon(
                key: const ValueKey('move-ships'),
                icon: const Icon(Icons.rocket_launch_outlined),
                label: const Text('Move ships'),
                onPressed: () => setState(() => _form = _Form.ships),
              ),
            ],
          ),
          switch (_form) {
            _Form.none => const SizedBox.shrink(),
            _Form.route => _NewRouteForm(
              key: const ValueKey('route-form'),
              bodyId: v.id,
              form: form,
              onDone: close,
            ),
            _Form.ships => _MoveShipsForm(
              key: const ValueKey('ships-form'),
              bodyId: v.id,
              form: form,
              onDone: close,
            ),
          },
        ],
      ],
    );
  }
}

/// One route: what it carries where, its figures, its status and stop
/// level, and Remove.
class _RouteCard extends StatefulWidget {
  const _RouteCard({super.key, required this.view});

  final RouteView view;

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  bool _editing = false;
  final TextEditingController _stop = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _stop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.view;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final mono = monoText(text.bodyMedium);
    final (icon, color) = switch (r.status) {
      RouteStatus.moving => (Icons.local_shipping_outlined, Palette.green),
      RouteStatus.waiting => (Icons.hourglass_empty, Palette.amber),
      RouteStatus.stopped => (Icons.pause_circle_outline, Palette.muted),
    };
    final ships = r.ships == 1 ? '1 ship' : '${r.ships} ships';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.border),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.resourceName}: ${r.fromName} → ${r.toName}',
            style: text.titleSmall,
          ),
          Text('${r.rate} set · $ships · ${r.travel} a trip', style: mono),
          Text('Carries up to ${r.throughput}, held by ${r.limit}'),
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(r.statusText)),
            ],
          ),
          Text(
            r.stop == null
                ? 'Never stops'
                : 'Stops when ${r.toName} holds ${r.stop}',
            style: text.bodySmall?.copyWith(color: Palette.muted),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: ValueKey('stop-edit-${r.id}'),
                onPressed: () => setState(() {
                  _editing = !_editing;
                  _error = null;
                  _stop.text = r.stopValue == null
                      ? ''
                      : formatNumber(r.stopValue!);
                }),
                child: const Text('Stop level'),
              ),
              TextButton.icon(
                key: ValueKey('remove-route-${r.id}'),
                icon: const Icon(Icons.close),
                label: const Text('Remove'),
                onPressed: () => runAndReport(
                  context,
                  c,
                  RemoveRouteCommand(c.playerId, r.id),
                  announce: true,
                ),
              ),
            ],
          ),
          if (_editing) ..._stopEditor(context, c),
        ],
      ),
    );
  }

  List<Widget> _stopEditor(BuildContext context, GameController c) {
    final r = widget.view;
    void run(UpdateRouteCommand cmd) {
      final result = runAndReport(context, c, cmd, announce: true);
      setState(() {
        if (result is CommandFailed) {
          _error = c.lastError;
        } else {
          _editing = false;
          _error = null;
        }
      });
    }

    return [
      TextField(
        key: ValueKey('stop-field-${r.id}'),
        controller: _stop,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: 'Stop when ${r.toName} holds'),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            key: ValueKey('stop-set-${r.id}'),
            onPressed: () {
              final v = _number(_stop.text);
              if (v == null) {
                setState(
                  () => _error =
                      'Enter the stop level as a number of units, '
                      'such as 500',
                );
                return;
              }
              run(
                UpdateRouteCommand(
                  c.playerId,
                  r.id,
                  stopAtDestination: BigNum.from(v),
                ),
              );
            },
            child: const Text('Set'),
          ),
          if (r.stopValue != null)
            TextButton(
              key: ValueKey('stop-clear-${r.id}'),
              onPressed: () => run(
                UpdateRouteCommand(
                  c.playerId,
                  r.id,
                  removeStopAtDestination: true,
                ),
              ),
              child: const Text('Never stop'),
            ),
          TextButton(
            onPressed: () => setState(() => _editing = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
      if (_error case final why?) BlockedReason(why),
    ];
  }
}

/// A finite number typed in [s], or null.
double? _number(String s) {
  final v = double.tryParse(s.trim());
  return v != null && v.isFinite ? v : null;
}

/// A stepper for a count of ships: − count of most +.
class _ShipStepper extends StatelessWidget {
  const _ShipStepper({
    required this.prefix,
    required this.count,
    required this.most,
    required this.onChanged,
  });

  final String prefix;
  final int count;
  final int most;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text('Cargo ships'),
      IconButton(
        key: ValueKey('$prefix-remove'),
        icon: const Icon(Icons.remove),
        tooltip: 'One ship fewer',
        onPressed: count > 1 ? () => onChanged(count - 1) : null,
      ),
      Text(
        '$count of $most here',
        style: monoText(Theme.of(context).textTheme.bodyMedium),
      ),
      IconButton(
        key: ValueKey('$prefix-add'),
        icon: const Icon(Icons.add),
        tooltip: 'One ship more',
        onPressed: count < most ? () => onChanged(count + 1) : null,
      ),
    ],
  );
}

/// A body picker on a line of its own, so long names wrap.
class _BodyPicker extends StatelessWidget {
  const _BodyPicker({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<({String id, String name})> choices;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        itemHeight: null,
        items: [
          for (final b in choices)
            DropdownMenuItem(value: b.id, child: Text(b.name)),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}

/// New route: destination, resource, rate, ships and an optional stop
/// level, created by the core's command.
class _NewRouteForm extends StatefulWidget {
  const _NewRouteForm({
    super.key,
    required this.bodyId,
    required this.form,
    required this.onDone,
  });

  final String bodyId;
  final RouteFormView form;
  final VoidCallback onDone;

  @override
  State<_NewRouteForm> createState() => _NewRouteFormState();
}

class _NewRouteFormState extends State<_NewRouteForm> {
  String? _to;
  String? _resource;
  int _ships = 1;
  final TextEditingController _rate = TextEditingController(text: '1');
  final TextEditingController _stop = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    _stop.dispose();
    super.dispose();
  }

  /// [want] when still offered, else the first offered.
  static String? _pick(String? want, List<({String id, String name})> all) =>
      all.any((x) => x.id == want) ? want : all.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final to = _pick(_to, f.destinations);
    final resource = _pick(_resource, f.resources);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New route', style: text.titleSmall),
          _BodyPicker(
            key: const ValueKey('route-to'),
            label: 'To',
            value: to,
            choices: f.destinations,
            onChanged: (id) => setState(() => _to = id),
          ),
          if (f.resources.isEmpty)
            Text(
              'Nothing is stored here to send yet.',
              style: text.bodyMedium?.copyWith(color: Palette.muted),
            )
          else
            _BodyPicker(
              key: const ValueKey('route-resource'),
              label: 'Carrying',
              value: resource,
              choices: f.resources,
              onChanged: (id) => setState(() => _resource = id),
            ),
          TextField(
            key: const ValueKey('route-rate'),
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Units a second'),
          ),
          _ShipStepper(
            prefix: 'route-ships',
            count: _ships,
            most: f.ships,
            onChanged: (n) => setState(() => _ships = n),
          ),
          TextField(
            key: const ValueKey('route-stop'),
            controller: _stop,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Stop when the destination holds (optional)',
            ),
          ),
          if (_error case final why?) BlockedReason(why),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('route-create'),
                onPressed: to == null
                    ? null
                    : () => _create(context, c, to, resource),
                child: const Text('Create route'),
              ),
              TextButton(onPressed: widget.onDone, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }

  void _create(
    BuildContext context,
    GameController c,
    String to,
    String? resource,
  ) {
    final rate = _number(_rate.text);
    if (rate == null) {
      setState(
        () => _error =
            'Enter the rate as a number of units a second, '
            'such as 0.5',
      );
      return;
    }
    final stopText = _stop.text.trim();
    final stop = stopText.isEmpty ? null : _number(stopText);
    if (stopText.isNotEmpty && stop == null) {
      setState(
        () => _error =
            'Enter the stop level as a number of units, or '
            'leave it empty',
      );
      return;
    }
    if (resource == null) {
      setState(() => _error = 'Nothing is stored here to send yet');
      return;
    }
    final result = runAndReport(
      context,
      c,
      CreateRouteCommand(
        c.playerId,
        widget.bodyId,
        to,
        resource,
        BigNum.from(rate),
        _ships,
        stopAtDestination: stop == null ? null : BigNum.from(stop),
      ),
      announce: true,
    );
    if (result is CommandFailed) {
      setState(() => _error = c.lastError);
    } else {
      widget.onDone();
    }
  }
}

/// Move ships: cargo ships from this body's stock to another body.
class _MoveShipsForm extends StatefulWidget {
  const _MoveShipsForm({
    super.key,
    required this.bodyId,
    required this.form,
    required this.onDone,
  });

  final String bodyId;
  final RouteFormView form;
  final VoidCallback onDone;

  @override
  State<_MoveShipsForm> createState() => _MoveShipsFormState();
}

class _MoveShipsFormState extends State<_MoveShipsForm> {
  String? _to;
  int _count = 1;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final to = _NewRouteFormState._pick(_to, f.destinations);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Move ships', style: text.titleSmall),
          _BodyPicker(
            key: const ValueKey('move-to'),
            label: 'To',
            value: to,
            choices: f.destinations,
            onChanged: (id) => setState(() => _to = id),
          ),
          _ShipStepper(
            prefix: 'move-count',
            count: _count,
            most: f.ships,
            onChanged: (n) => setState(() => _count = n),
          ),
          if (_error case final why?) BlockedReason(why),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('move-send'),
                onPressed: to == null
                    ? null
                    : () {
                        final r = runAndReport(
                          context,
                          c,
                          MoveShipsCommand(
                            c.playerId,
                            widget.bodyId,
                            to,
                            _count,
                          ),
                          announce: true,
                        );
                        if (r is CommandFailed) {
                          setState(() => _error = c.lastError);
                        } else {
                          widget.onDone();
                        }
                      },
                child: const Text('Send'),
              ),
              TextButton(onPressed: widget.onDone, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}
