import 'package:material_ui/material_ui.dart';

/// Opens the settings sheet. A stub until Task 9 adds export, import and
/// new game.
Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const SettingsSheet(),
    );

/// The settings sheet (stub).
class SettingsSheet extends StatelessWidget {
  /// Creates the sheet.
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
