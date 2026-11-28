import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/ui/planet/route_forms.dart';
import 'package:space_idle/view/storage_routes_view.dart';
import 'package:space_idle/view/view_models.dart';

/// Which form the routes section has open.
enum _Form { none, route, ships }

/// An owned body's routes, out and in: each with its rate, ships and
/// trip, what it can carry and what holds it, whether it is moving, and
/// its stop level, all three editable on the card; and the New route and
/// Move ships forms ([NewRouteForm], [MoveShipsForm]).
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
        for (final r in [...v.routesOut, ...v.routesIn])
          RouteCard(key: ValueKey('route-${r.id}'), view: r),
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
            _Form.route => NewRouteForm(
              key: const ValueKey('route-form'),
              bodyId: v.id,
              form: form,
              onDone: close,
            ),
            _Form.ships => MoveShipsForm(
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
/// level; Edit (rate, ships and stop level) and Remove.
class RouteCard extends StatefulWidget {
  /// Creates the card for [view]; the Trade tab lists every route with it.
  const RouteCard({super.key, required this.view});

  /// The route.
  final RouteView view;

  @override
  State<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<RouteCard> {
  bool _editing = false;
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _stop = TextEditingController();
  int _ships = 1;
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    _stop.dispose();
    super.dispose();
  }

  /// Opens the editor at the route's own figures, or closes it.
  void _toggle() => setState(() {
    final r = widget.view;
    _editing = !_editing;
    _error = null;
    _rate.text = editableNumber(r.rateValue);
    _ships = r.ships;
    _stop.text = r.stopValue == null ? '' : editableNumber(r.stopValue!);
  });

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
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Carries up to '),
                TextSpan(text: r.throughput, style: mono),
                TextSpan(text: ', held by ${r.limit}'),
              ],
            ),
          ),
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
              TextButton.icon(
                key: ValueKey('route-edit-${r.id}'),
                icon: const Icon(Icons.tune),
                label: const Text('Edit'),
                onPressed: _toggle,
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
          if (_editing) ..._editor(context),
        ],
      ),
    );
  }

  /// The rate, the ships (up to those on the route and those spare at
  /// its source) and the stop level, saved as one update.
  List<Widget> _editor(BuildContext context) {
    final r = widget.view;
    final c = ControllerScope.of(context);
    void error(String? why) => setState(() => _error = why);
    void save() {
      final rate = typedNumber(_rate.text);
      if (rate == null) {
        return error('Enter the rate as a number of units a second');
      }
      final stopText = _stop.text.trim();
      final stop = stopText.isEmpty ? null : typedNumber(stopText);
      if (stopText.isNotEmpty && stop == null) {
        return error('Enter the stop level as a number, or leave it empty');
      }
      final newRate = BigNum.from(rate);
      final newStop = stop == null ? null : BigNum.from(stop);
      final cmd = UpdateRouteCommand(
        c.playerId,
        r.id,
        ratePerSecond: newRate == r.rateValue ? null : newRate,
        cargoShips: _ships == r.ships ? null : _ships,
        stopAtDestination: newStop == r.stopValue ? null : newStop,
        removeStopAtDestination: newStop == null && r.stopValue != null,
      );
      final changed =
          cmd.ratePerSecond != null ||
          cmd.cargoShips != null ||
          cmd.stopAtDestination != null ||
          cmd.removeStopAtDestination;
      if (!changed) return setState(() => _editing = false);
      runInForm(
        context,
        c,
        cmd,
        onError: error,
        onDone: () => setState(() => _editing = false),
      );
    }

    return [
      TextField(
        key: ValueKey('rate-field-${r.id}'),
        controller: _rate,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Units a second'),
      ),
      ShipStepper(
        prefix: 'ships-${r.id}',
        count: _ships,
        most: r.ships + r.spareShips,
        onChanged: (n) => setState(() => _ships = n),
      ),
      TextField(
        key: ValueKey('stop-field-${r.id}'),
        controller: _stop,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Stop when ${r.toName} holds (empty: never)',
        ),
      ),
      if (_error case final why?) BlockedReason(why),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            key: ValueKey('route-save-${r.id}'),
            onPressed: save,
            child: const Text('Save'),
          ),
          TextButton(
            key: ValueKey('route-cancel-${r.id}'),
            onPressed: () => setState(() => _editing = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ];
  }
}
