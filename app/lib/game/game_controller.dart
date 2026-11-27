import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/save_store.dart';

/// How [GameController.start] found the save slot.
sealed class StartResult {
  const StartResult();
}

/// The slot was empty, so a new game started and was saved.
final class StartedNew extends StartResult {
  /// Creates the result.
  const StartedNew();
}

/// The save loaded and was caught up to now.
final class Loaded extends StartResult {
  /// Creates the result.
  const Loaded();
}

/// The slot held something that is not a save this build can run.
///
/// A new game runs in memory, but nothing is written over [brokenText]
/// until the player confirms with [GameController.newGame] or a successful
/// [GameController.importSave], so it can still be exported first.
final class LoadFailed extends StartResult {
  /// Creates the result.
  const LoadFailed(this.brokenText, this.reason);

  /// The slot's text, exactly as stored.
  final String brokenText;

  /// Why it could not be loaded, for a details line.
  final String reason;
}

/// How [GameController.importSave] went.
sealed class ImportResult {
  const ImportResult();
}

/// The imported game replaced the current one and was saved.
final class Imported extends ImportResult {
  /// Creates the result.
  const Imported();
}

/// The text was not a save this build can run; nothing changed.
final class ImportFailed extends ImportResult {
  /// Creates the result.
  const ImportFailed(this.reason);

  /// Why, for a details line.
  final String reason;
}

/// Owns the running game: the one place the app changes [state].
///
/// Widgets read [state] and [flow] and change the game only through [run].
/// Game time moves by [tickSeconds] (the 1 s timer, or tests) and by
/// offline catch-up from the wall-clock gap since the state was last
/// current ([start], [resume], or a long gap between timer fires). Saves go
/// to [SaveStore] as `{"savedAt": <epoch ms>, "save": <SaveCodec text>}`,
/// stamped from the injected [Clock].
class GameController extends ChangeNotifier {
  /// Creates a controller holding a new game until [start] loads the save.
  ///
  /// [newGameSeed] seeds every new game; without it each new game is
  /// seeded from the clock.
  GameController({
    required Content content,
    required SaveStore store,
    required Clock clock,
    int? newGameSeed,
  }) : this._(GameEngine(content), store, clock, newGameSeed);

  GameController._(this.engine, this._store, this._clock, this._seed)
    : content = engine.content,
      _syncedAt = _clock.now(),
      _state = engine.newGame(_seedFrom(_seed, _clock));

  /// Seconds of ticks between autosaves.
  static const double autosaveSeconds = 30;

  /// Shortest time away that earns a "while you were away" summary.
  static const double awaySummarySeconds = 60;

  /// How often the live timer fires.
  static const Duration tickInterval = Duration(seconds: 1);

  /// The validated content the game runs on.
  final Content content;

  /// The engine every change goes through.
  final GameEngine engine;

  final SaveStore _store;
  final Clock _clock;
  final int? _seed;

  GameState _state;

  /// Wall-clock time up to which [_state] has been simulated.
  DateTime _syncedAt;

  /// Whether [save] may write: false until [start] has read the slot and
  /// found it empty or loadable, and after a failed load until the player
  /// replaces the broken save, so a save is never written over unread.
  bool _canWrite = false;

  /// The one [start] run, shared by every caller.
  Future<StartResult>? _starting;

  /// Whether [start] has finished; [resume] and the timer wait for it.
  bool _started = false;

  double _sinceAutosave = 0;
  FlowReport? _flow;
  String? _lastError;
  final List<OfflineSummary> _pendingAwaySummaries = [];
  Timer? _timer;
  bool _disposed = false;

  /// The game state; read-only for widgets.
  GameState get state => _state;

  /// The player's flow report for the current state, rebuilt lazily after
  /// every tick, command or load.
  FlowReport get flow => _flow ??= buildFlowReport(_state, content, playerId);

  /// Id of the player's faction.
  String get playerId => _state.factions.firstWhere((f) => f.isPlayer).id;

  /// Message of the last failed [run], cleared by the next success.
  String? get lastError => _lastError;

  /// Every catch-up of at least [awaySummarySeconds] not yet seen, oldest
  /// first. Several build up when the app is backgrounded again before the
  /// away dialog is dismissed; the dialog shows them combined, then calls
  /// [clearAwaySummary]. Unmodifiable.
  List<OfflineSummary> get pendingAwaySummaries =>
      List.unmodifiable(_pendingAwaySummaries);

  /// The most recent of [pendingAwaySummaries], or null when there is none.
  OfflineSummary? get pendingAwaySummary =>
      _pendingAwaySummaries.isEmpty ? null : _pendingAwaySummaries.last;

  /// Loads the save slot and catches it up, or starts a new game.
  ///
  /// Runs once: later calls get the first call's result. Until it has
  /// finished nothing is written, and [resume] and the timer do nothing.
  Future<StartResult> start() => _starting ??= _start();

  Future<StartResult> _start() async {
    final result = await _load();
    _started = true;
    _notify();
    return result;
  }

  Future<StartResult> _load() async {
    final String? text;
    try {
      text = await _store.read();
    } catch (e, st) {
      // Storage itself failed: the save may still be there, so keep
      // writes off and let the player decide, as for a broken save.
      _reportError(e, st, 'while reading the save');
      return LoadFailed('', 'the save could not be read: $e');
    }
    if (text == null) {
      _syncedAt = _clock.now();
      _canWrite = true;
      await save();
      return const StartedNew();
    }
    switch (_decode(text, envelopeOnly: true)) {
      case _Bad(:final reason):
        return LoadFailed(text, reason);
      case _Good(:final state, :final savedAt):
        _state = state;
        _flow = null;
        _syncedAt = savedAt ?? _clock.now();
        _canWrite = true;
        _catchUp();
        await save();
        return const Loaded();
    }
  }

  /// Applies [cmd] through the engine and notifies listeners either way.
  ///
  /// A failure leaves the state untouched and sets [lastError].
  CommandResult run(Command cmd) {
    final result = engine.apply(_state, cmd);
    switch (result) {
      case CommandOk():
        _lastError = null;
        _flow = null;
      case CommandFailed(:final message):
        _lastError = message;
    }
    _notify();
    return result;
  }

  /// Moves the game forward [seconds], autosaving every [autosaveSeconds]
  /// of ticks. Zero, negative and non-finite values do nothing.
  void tickSeconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return;
    engine.advance(_state, seconds);
    _flow = null;
    _sinceAutosave += seconds;
    if (_sinceAutosave >= autosaveSeconds) _autosave();
    _notify();
  }

  /// Writes the save envelope, unless [start] has not read the slot yet or
  /// a failed load is still unresolved.
  Future<void> save() async {
    _sinceAutosave = 0;
    if (!_canWrite) return;
    final envelope = jsonEncode({
      'savedAt': _syncedAt.millisecondsSinceEpoch,
      'save': SaveCodec.encode(_state),
    });
    await _store.write(envelope);
  }

  /// Catches up the time since the state was last current (the app was in
  /// the background), saves, and returns the away summary if there is one.
  /// Does nothing before [start] has finished.
  Future<OfflineSummary?> resume() async {
    if (!_started) return null;
    final summary = _catchUp();
    await save();
    _notify();
    return summary;
  }

  /// The current game as [SaveCodec] text, for the player to keep.
  String exportSave() => SaveCodec.encode(_state);

  /// Replaces the game with [text]: [SaveCodec] text or a stored envelope.
  ///
  /// The imported game is not caught up: it carries no wall-clock time.
  Future<ImportResult> importSave(String text) async {
    switch (_decode(text, envelopeOnly: false)) {
      case _Bad(:final reason):
        return ImportFailed(reason);
      case _Good(:final state):
        _replace(state);
        await save();
        return const Imported();
    }
  }

  /// Replaces the game with a new one and saves it, also over a broken save.
  Future<void> newGame() async {
    _replace(engine.newGame(_nextSeed()));
    await save();
  }

  /// Starts the live 1 s timer; each fire ticks the wall time since the
  /// last one. Does nothing if it is already running.
  void startTimer() {
    _timer ??= Timer.periodic(tickInterval, (_) => _onTimer());
  }

  /// Stops the live timer.
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drops every pending away summary once the player has seen them.
  void clearAwaySummary() {
    _pendingAwaySummaries.clear();
    _notify();
  }

  @override
  void dispose() {
    stopTimer();
    _disposed = true;
    super.dispose();
  }

  void _onTimer() {
    // Before start() the state is a placeholder about to be replaced.
    if (!_started) return;
    final now = _clock.now();
    final gap = _secondsBetween(_syncedAt, now);
    if (gap >= awaySummarySeconds) {
      // Timers are throttled or frozen in the background without always a
      // lifecycle event (a hidden browser tab), so a long gap is an away
      // catch-up, offline cap and summary included.
      _catchUp();
      _autosave();
      _notify();
      return;
    }
    _syncedAt = now;
    tickSeconds(gap);
  }

  /// Simulates the wall time since [_syncedAt], capped by the engine; a
  /// clock set back simulates nothing. Returns the summary when the gap
  /// earns one, which is also added to [pendingAwaySummaries].
  OfflineSummary? _catchUp() {
    final now = _clock.now();
    final away = _secondsBetween(_syncedAt, now);
    _syncedAt = now;
    if (away <= 0) return null;
    final summary = engine.catchUpOffline(_state, away);
    _flow = null;
    if (away < awaySummarySeconds) return null;
    _pendingAwaySummaries.add(summary);
    return summary;
  }

  void _replace(GameState state) {
    _state = state;
    _flow = null;
    _syncedAt = _clock.now();
    _canWrite = true;
    _lastError = null;
    _pendingAwaySummaries.clear();
    _sinceAutosave = 0;
    _notify();
  }

  void _autosave() {
    unawaited(
      save().catchError((Object e, StackTrace st) {
        _reportError(e, st, 'while autosaving');
      }),
    );
  }

  static void _reportError(Object e, StackTrace st, String doing) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'space_idle',
        context: ErrorDescription(doing),
      ),
    );
  }

  int _nextSeed() => _seedFrom(_seed, _clock);

  static int _seedFrom(int? seed, Clock clock) =>
      seed ?? clock.now().microsecondsSinceEpoch & 0x7fffffff;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Decodes a stored envelope, or with [envelopeOnly] false also bare
  /// [SaveCodec] text, into a runnable state.
  _Decoded _decode(String text, {required bool envelopeOnly}) {
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    var saveText = text;
    DateTime? savedAt;
    if (json is Map && json['save'] is String) {
      saveText = json['save'] as String;
      final ms = json['savedAt'];
      if (ms is int) {
        // DateTime throws outside ±8.64e15 ms; a foreign or hand-edited
        // envelope must fail to load, not crash.
        if (ms.abs() > _maxEpochMs) {
          return const _Bad('the save\'s savedAt time is out of range');
        }
        savedAt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      } else if (envelopeOnly) {
        return const _Bad('the save has no savedAt time');
      }
    } else if (envelopeOnly) {
      return const _Bad('not a Space Idle save');
    }
    return switch (SaveCodec.decode(saveText, content)) {
      SaveOk(:final state) => _Good(state, savedAt),
      SaveError(:final kind, :final message) => _Bad('${kind.name}: $message'),
    };
  }

  /// Largest epoch milliseconds a [DateTime] can hold, either side of 1970.
  static const int _maxEpochMs = 8640000000000000;

  static double _secondsBetween(DateTime from, DateTime to) =>
      to.difference(from).inMicroseconds / Duration.microsecondsPerSecond;
}

sealed class _Decoded {
  const _Decoded();
}

final class _Good extends _Decoded {
  const _Good(this.state, this.savedAt);
  final GameState state;
  final DateTime? savedAt;
}

final class _Bad extends _Decoded {
  const _Bad(this.reason);
  final String reason;
}
