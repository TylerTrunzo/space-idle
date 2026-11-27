import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/broken_save_screen.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/shell.dart';

/// The app: one [GameController] for the session, its save loaded at
/// launch, kept running while in the foreground and saved when it leaves.
///
/// Shows a loading screen until the save is read, then the [Shell], or the
/// [BrokenSaveScreen] when the save cannot be loaded.
class SpaceIdleApp extends StatefulWidget {
  /// Creates the app; [store] defaults to the device's shared preferences
  /// and [clock] to the system clock.
  const SpaceIdleApp({super.key, this.store, this.clock});

  /// Where the save lives.
  final SaveStore? store;

  /// The wall clock offline catch-up measures with.
  final Clock? clock;

  /// Key of the loading screen, for tests.
  static const Key loadingKey = ValueKey('loading');

  @override
  State<SpaceIdleApp> createState() => _SpaceIdleAppState();
}

class _SpaceIdleAppState extends State<SpaceIdleApp> {
  late final GameController _controller;
  late final AppLifecycleListener _lifecycle;

  /// How start() went; null while it runs.
  StartResult? _started;

  @override
  void initState() {
    super.initState();
    _controller = GameController(
      content: loadEmbeddedContent(),
      store: widget.store ?? PrefsSaveStore(),
      clock: widget.clock ?? const SystemClock(),
    );
    _lifecycle = AppLifecycleListener(
      onHide: _toBackground,
      onPause: _toBackground,
      onDetach: _toBackground,
      onResume: _toForeground,
    );
    unawaited(_start());
  }

  Future<void> _start() async {
    final result = await _controller.start();
    if (!mounted) return;
    setState(() => _started = result);
    if (result is! LoadFailed) _controller.startTimer();
  }

  bool get _playing => switch (_started) {
    null || LoadFailed() => false,
    StartedNew() || Loaded() => true,
  };

  void _toBackground() {
    _controller.stopTimer();
    unawaited(_controller.save().catchError(_report));
  }

  void _toForeground() {
    if (!_playing) return;
    // The catch-up runs at once; only its save is awaited.
    unawaited(_controller.resume().catchError(_reportNull));
    _controller.startTimer();
  }

  Future<void> _newGame() async {
    await _controller.newGame();
    if (!mounted) return;
    setState(() => _started = const StartedNew());
    _controller.startTimer();
  }

  static void _report(Object e, StackTrace st) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: st,
      library: 'space_idle',
      context: ErrorDescription('while saving on leaving the foreground'),
    ),
  );

  static Null _reportNull(Object e, StackTrace st) {
    _report(e, st);
    return null;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ControllerScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Space Idle',
        theme: buildTheme(),
        home: switch (_started) {
          null => const _Loading(),
          LoadFailed(:final reason) => BrokenSaveScreen(
            brokenText: _controller.brokenSaveText,
            reason: reason,
            onNewGame: _newGame,
          ),
          StartedNew() || Loaded() => const Shell(),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Scaffold(
    key: SpaceIdleApp.loadingKey,
    body: Center(
      child: Semantics(
        label: 'Loading your game',
        child: const CircularProgressIndicator(),
      ),
    ),
  );
}
