import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';

/// Shown at launch when the stored save could not be loaded (an older
/// build's save, a corrupt one, or storage that could not be read).
///
/// The broken save stays in storage until the player chooses: Export
/// copies its text so it is not lost, and Start new game replaces it.
class BrokenSaveScreen extends StatelessWidget {
  /// Creates the screen.
  const BrokenSaveScreen({
    super.key,
    required this.brokenText,
    required this.reason,
    required this.onNewGame,
    this.onRetry,
  });

  /// The stored text, for Export; null when storage could not be read at
  /// all, which leaves nothing to export.
  final String? brokenText;

  /// Why it failed, shown small, for a bug report.
  final String reason;

  /// Starts a new game over the broken save.
  final VoidCallback onNewGame;

  /// Reads the store again; offered when it could not be read at all,
  /// which may pass (the save may still be there). Null hides it.
  final VoidCallback? onRetry;

  Future<void> _export(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      // A browser can refuse the clipboard: say so; the save stays stored.
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't copy the save text")),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Copied the save text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final broken = brokenText;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.error_outline, color: Palette.amber, size: 40),
                const SizedBox(height: 12),
                Text("Your save couldn't be loaded", style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  broken == null
                      ? 'The game could not read its save from this device. '
                            'It may still be there: try again first.'
                      : 'It may come from another version of the game. '
                            'Export it to keep a copy before you start over.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: monoText(text.bodySmall)
                      .copyWith(color: Palette.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start new game replaces whatever is stored on this device.',
                  style: text.bodyMedium?.copyWith(color: Palette.amber),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (onRetry case final retry?)
                      FilledButton.icon(
                        icon: const Icon(Icons.replay),
                        label: const Text('Retry'),
                        onPressed: retry,
                      ),
                    if (broken != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Export'),
                        onPressed: () => _export(context, broken),
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Start new game'),
                      onPressed: onNewGame,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
