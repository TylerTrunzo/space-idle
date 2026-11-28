import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/blocked_reason.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/command_feedback.dart';
import 'package:space_idle/view/storage_routes_view.dart';

/// Runs [cmd] for a form: on success its sentence shows and [onDone]
/// closes the form; on a refusal [onError] gets the core's reason to
/// show in the form, which stays open (b10).
void runInForm(
  BuildContext context,
  GameController c,
  Command cmd, {
  required ValueChanged<String?> onError,
  required VoidCallback onDone,
}) {
  final r = runAndReport(context, c, cmd, announce: true);
  if (r is CommandFailed) {
    onError(c.lastError);
  } else {
    onDone();
  }
}

/// A finite number typed in [s], or null.
double? typedNumber(String s) {
  final v = double.tryParse(s.trim());
  return v != null && v.isFinite ? v : null;
}

/// [want] when [all] still offers it, else the first offered.
String? pickOffered(String? want, List<({String id, String name})> all) =>
    all.any((x) => x.id == want) ? want : all.firstOrNull?.id;

/// A count of cargo ships: − count of most +; with [most] at zero it
/// says there are none here instead.
class ShipStepper extends StatelessWidget {
  /// Creates the stepper; its buttons are keyed `<prefix>-remove` and
  /// `<prefix>-add`.
  const ShipStepper({
    super.key,
    required this.prefix,
    required this.count,
    required this.most,
    required this.onChanged,
    this.least = 1,
  });

  /// Names the buttons' keys.
  final String prefix;

  /// The count chosen.
  final int count;

  /// The most it can be.
  final int most;

  /// The least it can be.
  final int least;

  /// Called with the new count.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (most <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Palette.amber),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'No cargo ships here',
                style: TextStyle(color: Palette.amber),
              ),
            ),
          ],
        ),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Cargo ships'),
        IconButton(
          key: ValueKey('$prefix-remove'),
          icon: const Icon(Icons.remove),
          tooltip: 'One ship fewer',
          onPressed: count > least ? () => onChanged(count - 1) : null,
        ),
        Text(
          '$count of $most',
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
}

/// A picker on a line of its own, so long names wrap.
class ChoicePicker extends StatelessWidget {
  /// Creates the picker.
  const ChoicePicker({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  /// What it picks, above it.
  final String label;

  /// The id chosen.
  final String? value;

  /// What it offers.
  final List<({String id, String name})> choices;

  /// Called with the new id.
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
class NewRouteForm extends StatefulWidget {
  /// Creates the form for routes from [bodyId].
  const NewRouteForm({
    super.key,
    required this.bodyId,
    required this.form,
    required this.onDone,
  });

  /// The source body.
  final String bodyId;

  /// What the form can offer.
  final RouteFormView form;

  /// Closes the form.
  final VoidCallback onDone;

  @override
  State<NewRouteForm> createState() => _NewRouteFormState();
}

class _NewRouteFormState extends State<NewRouteForm> {
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

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final to = pickOffered(_to, f.destinations);
    final resource = pickOffered(_resource, f.resources);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New route', style: text.titleSmall),
          ChoicePicker(
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
            ChoicePicker(
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
          ShipStepper(
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
                onPressed: to == null || f.ships <= 0
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
    void error(String? why) => setState(() => _error = why);
    final rate = typedNumber(_rate.text);
    if (rate == null) {
      return error('Enter the rate as a number of units a second, such as 0.5');
    }
    final stopText = _stop.text.trim();
    final stop = stopText.isEmpty ? null : typedNumber(stopText);
    if (stopText.isNotEmpty && stop == null) {
      return error(
        'Enter the stop level as a number of units, or leave it empty',
      );
    }
    if (resource == null) return error('Nothing is stored here to send yet');
    runInForm(
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
      onError: error,
      onDone: widget.onDone,
    );
  }
}

/// Move ships: cargo ships from this body's stock to another body.
class MoveShipsForm extends StatefulWidget {
  /// Creates the form for ships leaving [bodyId].
  const MoveShipsForm({
    super.key,
    required this.bodyId,
    required this.form,
    required this.onDone,
  });

  /// The body the ships leave.
  final String bodyId;

  /// What the form can offer.
  final RouteFormView form;

  /// Closes the form.
  final VoidCallback onDone;

  @override
  State<MoveShipsForm> createState() => _MoveShipsFormState();
}

class _MoveShipsFormState extends State<MoveShipsForm> {
  String? _to;
  int _count = 1;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final to = pickOffered(_to, f.destinations);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Move ships', style: text.titleSmall),
          ChoicePicker(
            key: const ValueKey('move-to'),
            label: 'To',
            value: to,
            choices: f.destinations,
            onChanged: (id) => setState(() => _to = id),
          ),
          ShipStepper(
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
                onPressed: to == null || f.ships <= 0
                    ? null
                    : () => runInForm(
                        context,
                        c,
                        MoveShipsCommand(c.playerId, widget.bodyId, to, _count),
                        onError: (why) => setState(() => _error = why),
                        onDone: widget.onDone,
                      ),
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
