import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/guide.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/game/settings_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/broken_save_screen.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/goals/guide_scope.dart';
import 'package:space_idle/ui/shell.dart';

/// The app: one [GameController] for the session, its save loaded at
/// launch, kept running while in the foreground and saved when it leaves.
///
/// Shows a loading screen until the save is read, then the [Shell], or the
/// [BrokenSaveScreen] when the save cannot be loaded.
class SpaceIdleApp extends StatefulWidget {
  /// Creates the app; [store] defaults to the device's shared preferences
  /// and [clock] to the system clock.
  const SpaceIdleApp({super.key, this.store, this.clock, this.settings});

  /// Where the save lives.
  final SaveStore? store;

  /// Where the app's own settings live (the guide's place, the goal
  /// strip's fold): the device's shared preferences by default, or memory
  /// when a [store] is given and no settings are, as tests do.
  final SettingsStore? settings;

  /// The wall clock offline catch-up measures with.
  final Clock? clock;

  /// Key of the loading screen, for tests.
  static const Key loadingKey = ValueKey('loading');

  @override
  State<SpaceIdleApp> createState() => _SpaceIdleAppState();
}

class _SpaceIdleAppState extends State<SpaceIdleApp> {
  late GameController _controller;
  late Guide _guide;
  late final SettingsStore _settings =
      widget.settings ??
      (widget.store == null ? PrefsSettingsStore() : MemorySettingsStore());
  late final AppLifecycleListener _lifecycle;
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey();

  /// How start() went; null while it runs.
  StartResult? _started;

  @override
  void initState() {
    super.initState();
    _controller = _newController();
    _guide = Guide(controller: _controller, store: _settings);
    _lifecycle = AppLifecycleListener(
      onHide: _toBackground,
      onPause: _toBackground,
      onDetach: _toBackground,
      onResume: _toForeground,
    );
    unawaited(_start());
  }

  GameController _newController() => GameController(
    content: loadEmbeddedContent(),
    store: widget.store ?? PrefsSaveStore(),
    clock: widget.clock ?? const SystemClock(),
  );

  Future<void> _start() async {
    final c = _controller;
    final guide = _guide;
    final result = await c.start();
    await guide.load();
    // Retry may have replaced the controller while this one was reading.
    if (!mounted || c != _controller) return;
    setState(() => _started = result);
    if (result is! LoadFailed) _startTimerIfInFront();
  }

  /// Starts the game timer only while the app is in front: a load that
  /// finishes in the background leaves it to [_toForeground], so the game
  /// does not tick (and autosave) unseen.
  void _startTimerIfInFront() {
    switch (WidgetsBinding.instance.lifecycleState) {
      case null || AppLifecycleState.resumed:
        _controller.startTimer();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        break;
    }
  }

  bool get _playing => switch (_started) {
    null || LoadFailed() => false,
    StartedNew() || Loaded() => true,
  };

  void _toBackground() {
    _controller.stopTimer();
    unawaited(
      _controller.save().catchError(
        (Object e, StackTrace st) =>
            _report(e, st, 'while saving on leaving the foreground'),
      ),
    );
  }

  void _toForeground() {
    if (!_playing) return;
    // The catch-up runs at once; only its save is awaited.
    unawaited(
      _controller.resume().then<void>(
        (_) {},
        onError: (Object e, StackTrace st) =>
            _report(e, st, 'while saving on resume'),
      ),
    );
    _controller.startTimer();
  }

  /// Starts over in a new game. A failed write is reported and said, and
  /// the new game plays on in memory: the next save tries again.
  Future<void> _newGame() async {
    final c = _controller;
    var saved = true;
    try {
      await c.newGame();
    } catch (e, st) {
      _report(e, st, 'while saving a new game');
      saved = false;
    }
    // Retry may have replaced the controller while the write was pending:
    // this new game is no longer the one on screen.
    if (!mounted || c != _controller) return;
    if (!saved) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            "The new game couldn't be saved yet. It's playing, and saving "
            'will try again.',
          ),
        ),
      );
    }
    setState(() => _started = const StartedNew());
    _startTimerIfInFront();
  }

  /// Reads the store again with a fresh controller, after a read failed.
  void _retry() {
    final old = _controller;
    final oldGuide = _guide;
    setState(() {
      _controller = _newController();
      _guide = Guide(controller: _controller, store: _settings);
      _started = null;
    });
    oldGuide.dispose();
    old.dispose();
    unawaited(_start());
  }

  static void _report(Object e, StackTrace st, String doing) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'space_idle',
          context: ErrorDescription(doing),
        ),
      );

  @override
  void dispose() {
    _lifecycle.dispose();
    _guide.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ControllerScope(
      controller: _controller,
      child: GuideScope(
        guide: _guide,
        child: MaterialApp(
          title: 'Space Idle',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          scaffoldMessengerKey: _messenger,
          home: switch (_started) {
            null => const _Loading(),
            LoadFailed(:final reason) => BrokenSaveScreen(
              brokenText: _controller.brokenSaveText,
              reason: reason,
              onNewGame: _newGame,
              // Only a store that could not be read is worth reading again.
              onRetry: _controller.brokenSaveText == null ? _retry : null,
            ),
            StartedNew() || Loaded() => const Shell(),
          },
        ),
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
