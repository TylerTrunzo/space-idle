import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/guide.dart';
import 'package:space_idle/ui/goals/guide_scope.dart';

/// Opens the settings sheet. It is handed the caller's guide, wherever its
/// route is mounted. Export, import and new game come in a later task.
Future<void> showSettingsSheet(BuildContext context) {
  final guide = GuideScope.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => guide == null
        ? const SettingsSheet()
        : GuideScope(guide: guide, child: const SettingsSheet()),
  );
}

/// The settings sheet: for now, "Skip guide" while the first-hour guide
/// runs.
class SettingsSheet extends StatelessWidget {
  /// Creates the sheet.
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final Guide? guide = GuideScope.maybeOf(context);
    return SafeArea(
      child: Padding(
        key: const ValueKey('settings-sheet'),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: text.titleLarge),
            const SizedBox(height: 8),
            if (guide != null && !guide.ended)
              OutlinedButton.icon(
                key: const ValueKey('skip-guide'),
                icon: const Icon(Icons.school_outlined),
                label: const Text('Skip guide'),
                onPressed: () {
                  guide.skip();
                  Navigator.of(context).maybePop();
                },
              ),
            const SizedBox(height: 8),
            Text(
              'Save export, import and new game are on their way.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
