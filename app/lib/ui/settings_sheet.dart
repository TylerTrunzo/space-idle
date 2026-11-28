import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/guide.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/goals/guide_scope.dart';
import 'package:space_idle/version.dart';

/// Opens the settings sheet. The app's [ControllerScope] and [GuideScope]
/// sit above its navigator, so the sheet's route finds them as the caller
/// does.
Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      // Tall at large text: it scrolls, up to the whole screen.
      isScrollControlled: true,
      builder: (context) => const SettingsSheet(),
    );

/// The settings sheet: Skip guide while the first-hour guide runs, Copy
/// save, Load save, New game behind a second tap, a placeholder for
/// supporting the developer, and the version.
///
/// Nothing here links out or takes payment.
class SettingsSheet extends StatefulWidget {
  /// Creates the sheet.
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final TextEditingController _paste = TextEditingController();

  /// The save text to select by hand when the clipboard refused it.
  String? _fallback;

  /// Whether Load waits for its second tap, and why the last load failed.
  bool _confirmLoad = false;
  String? _loadError;

  /// Whether New game waits for its second tap.
  bool _confirmNew = false;

  /// While a load or new game runs, so it is not started twice.
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _copy(GameController c) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = c.exportSave();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      // A browser can refuse the clipboard: show the text to select.
      if (mounted) setState(() => _fallback = text);
      return;
    }
    if (!mounted) return;
    setState(() => _fallback = null);
    messenger?.showSnackBar(const SnackBar(content: Text('Copied the save')));
  }

  Future<void> _load(GameController c) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _confirmLoad = false;
    });
    final result = await c.importSave(_paste.text.trim());
    if (!mounted) return;
    switch (result) {
      case Imported():
        navigator.pop();
        messenger?.showSnackBar(const SnackBar(content: Text('Save loaded')));
      case ImportFailed(:final reason):
        setState(() {
          _busy = false;
          _loadError = "Couldn't load that save: $reason";
        });
    }
  }

  Future<void> _newGame(GameController c) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _confirmNew = false;
    });
    await c.newGame();
    if (!mounted) return;
    navigator.pop();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Started a new game')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: Palette.muted);
    final Guide? guide = GuideScope.maybeOf(context);
    final fallback = _fallback;
    Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Semantics(header: true, child: Text(s, style: text.titleMedium)),
    );
    Widget confirm({
      required String question,
      required String confirmKey,
      required String cancelKey,
      required String confirmLabel,
      required VoidCallback onConfirm,
      required VoidCallback onCancel,
    }) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(liveRegion: true, child: Text(question)),
          FilledButton(
            key: ValueKey(confirmKey),
            onPressed: onConfirm,
            child: Text(confirmLabel),
          ),
          TextButton(
            key: ValueKey(cancelKey),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ListView(
          key: const ValueKey('settings-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings', style: text.titleLarge),
            if (guide != null && !guide.ended) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const ValueKey('skip-guide'),
                  icon: const Icon(Icons.school_outlined),
                  label: const Text('Skip guide'),
                  onPressed: () {
                    unawaited(guide.skip());
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            ],
            heading('Your save'),
            Text(
              'Copy it to keep it somewhere safe, or to move it to another '
              'device.',
              style: muted,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('settings-copy'),
                icon: const Icon(Icons.copy),
                label: const Text('Copy save'),
                onPressed: () => unawaited(_copy(c)),
              ),
            ),
            if (fallback != null) ...[
              const SizedBox(height: 4),
              Text(
                "Couldn't reach the clipboard: select the text below and "
                'copy it.',
                style: const TextStyle(color: Palette.amber),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Palette.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    fallback,
                    key: const ValueKey('settings-save-text'),
                    style: monoText(text.bodySmall),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('settings-load-field'),
              controller: _paste,
              minLines: 2,
              maxLines: 4,
              style: monoText(text.bodySmall),
              decoration: const InputDecoration(
                labelText: 'Paste a save to load',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const ValueKey('settings-load'),
                icon: const Icon(Icons.upload_file),
                label: const Text('Load save'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _confirmNew = false;
                        _loadError = null;
                        _confirmLoad = true;
                      }),
              ),
            ),
            if (_confirmLoad)
              confirm(
                question: 'Replace your game with this save?',
                confirmKey: 'settings-load-confirm',
                cancelKey: 'settings-load-cancel',
                confirmLabel: 'Load',
                onConfirm: () => unawaited(_load(c)),
                onCancel: () => setState(() => _confirmLoad = false),
              ),
            if (_loadError case final e?)
              Padding(
                key: const ValueKey('settings-load-error'),
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 18,
                      color: Palette.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e)),
                  ],
                ),
              ),
            heading('New game'),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('settings-new-game'),
                icon: const Icon(Icons.restart_alt),
                label: const Text('New game'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _confirmLoad = false;
                        _confirmNew = true;
                      }),
              ),
            ),
            if (_confirmNew)
              confirm(
                question:
                    'Start a new game? It replaces this one: copy your save '
                    'first to keep it.',
                confirmKey: 'settings-new-game-confirm',
                cancelKey: 'settings-new-game-cancel',
                confirmLabel: 'Start new game',
                onConfirm: () => unawaited(_newGame(c)),
                onCancel: () => setState(() => _confirmNew = false),
              ),
            const Divider(color: Palette.border, height: 32),
            const ListTile(
              key: ValueKey('settings-support'),
              enabled: false,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.favorite_border),
              title: Text('Support the developer'),
              subtitle: Text('Coming with the store release'),
            ),
            Padding(
              key: const ValueKey('settings-about'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Space Idle $appVersion (build $appBuild)',
                style: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
