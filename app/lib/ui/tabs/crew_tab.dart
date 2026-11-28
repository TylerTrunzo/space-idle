import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/lazy_list.dart';
import 'package:space_idle/ui/planet/building_row.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/tabs_view.dart';

/// The crew (b5): free, assigned and supported; housing against demand
/// from the core's crew forecast, with an amber card before a shortage;
/// every habitat and how it runs; and every crewed building with − and +,
/// the same stepper the planet panel uses.
///
/// The forecast builds several flow reports, so it comes after a frame
/// (the controller's `crewForecastNow`), never in the frame a command
/// lands in.
class CrewTab extends StatelessWidget {
  /// Creates the tab.
  const CrewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final view = crewView(c);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final items = <Widget>[
      Text('Crew', style: text.titleLarge),
      Text(
        '${view.free} free · ${view.assigned} assigned · '
        '${view.supported} supported',
        style: monoText(text.bodyLarge),
      ),
      const SizedBox(height: 8),
      _Forecast(habitatBodyId: view.habitatBodyId),
      const Divider(color: Palette.border),
      Text('Habitats', style: text.titleMedium),
      if (view.habitats.isEmpty)
        Text('No habitats yet: only base crew.', style: muted),
      for (final h in view.habitats)
        Padding(
          key: ValueKey('habitat-${h.row.id}'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Habitat on ${h.bodyName}', style: text.titleSmall),
              Text(
                'Houses ${h.houses} of ${h.housesAtFull} crew',
                style: monoText(text.bodyMedium),
              ),
              if (h.row.problem case final p?)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      size: 16,
                      color: Palette.amber,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p,
                        style: const TextStyle(color: Palette.amber),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      const Divider(color: Palette.border),
      Text('Crewed buildings', style: text.titleMedium),
      for (final w in view.crewed)
        Padding(
          key: ValueKey('crewed-${w.row.id}'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${w.row.name} on ${w.bodyName}', style: text.titleSmall),
              CrewLine(view: w.row),
            ],
          ),
        ),
    ];
    return ColoredBox(
      color: Palette.panel,
      child: LazyList(padding: const EdgeInsets.all(16), items: items),
    );
  }
}

/// Housing against demand, and the warning card before a shortage; a
/// line saying it is being worked out until the forecast lands.
class _Forecast extends StatelessWidget {
  const _Forecast({required this.habitatBodyId});

  final String? habitatBodyId;

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<int>(
      key: const ValueKey('crew-forecast'),
      valueListenable: c.previewsVersion,
      builder: (context, _, _) {
        final (:ready, :forecast) = c.crewForecastNow();
        if (!ready || forecast == null) {
          return Text(
            'Working out the crew forecast…',
            style: text.bodyMedium?.copyWith(color: Palette.muted),
          );
        }
        final warning = crewWarningText(forecast);
        final where = habitatBodyId;
        final whereName = where == null ? null : c.state.body(where).name;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Housing ${forecast.housing} · demand ${forecast.demand}',
              style: monoText(text.bodyMedium),
            ),
            if (warning != null)
              Card(
                key: const ValueKey('crew-warning'),
                color: Palette.background,
                shape: const RoundedRectangleBorder(
                  side: BorderSide(color: Palette.amber),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            color: Palette.amber,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              whereName == null
                                  ? '$warning: free a build slot for a Habitat'
                                  : '$warning: build a Habitat on $whereName',
                              style: const TextStyle(color: Palette.amber),
                            ),
                          ),
                        ],
                      ),
                      if (where != null)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            key: const ValueKey('crew-warning-go'),
                            onPressed: () =>
                                ShellScope.of(context).openOnMap(where),
                            child: const Text('Go'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
