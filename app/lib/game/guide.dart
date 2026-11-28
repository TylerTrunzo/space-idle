import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/settings_store.dart';
import 'package:space_idle/view/onboarding.dart';

/// The first-hour guide's place and the goal strip's fold, kept in the
/// app's settings ([SettingsStore]), not in the game save.
///
/// It follows the game: when the step it is showing becomes done, it says
/// so once through [lastDone] ("Done: Build a second Smelter"), and moves
/// past every step the state shows done. Steps already done when the
/// guide loads are passed quietly. A new game starts it over. It ends
/// after the last step, or with [skip].
///
/// Nothing here can stop the game: a settings read or write that fails is
/// reported and the guide carries on, fresh if it could not read.
class Guide extends ChangeNotifier {
  /// Creates the guide for [controller], kept in [store].
  Guide({required this.controller, required this.store})
    : _games = controller.gamesStarted {
    controller.addListener(_follow);
  }

  /// Settings key of the guide's place.
  static const String key = 'guide_v1';

  /// The game it follows.
  final GameController controller;

  /// Where its place is kept.
  final SettingsStore store;

  int _reached = 0;
  bool _skipped = false;
  bool _collapsed = false;
  bool _loaded = false;

  /// The step last shown, whose being done is what [lastDone] announces.
  int? _shown;

  /// The controller's new-game count the guide's place is for.
  int _games;

  /// The title of the step shown when it became done, for a short "Done"
  /// message; the listener clears it once shown.
  final ValueNotifier<String?> lastDone = ValueNotifier(null);

  /// Whether the goal strip is folded to its first row.
  bool get collapsed => _collapsed;

  /// Whether the guide has ended: skipped, or every step passed.
  bool get ended => _skipped || _reached >= onboardingSteps.length;

  /// The step to show in the strip's Now slot, or null once the guide has
  /// ended ([onboardingStepAt]), and until it has loaded.
  int? get step => !_loaded || ended
      ? null
      : onboardingStepAt(
          controller.state,
          controller.content,
          controller.playerId,
          _reached,
        );

  /// Reads the stored place, then passes what the state already shows
  /// done, quietly. It never throws: a failed read is reported and the
  /// guide starts fresh, and a stored place out of range is clamped.
  Future<void> load() async {
    String? text;
    try {
      text = await store.read(key);
    } catch (e, st) {
      _report(e, st, 'while reading the guide');
    }
    if (text != null) {
      try {
        final j = jsonDecode(text) as Map<String, Object?>;
        _reached = ((j['reached'] as num?)?.toInt() ?? 0).clamp(
          0,
          onboardingSteps.length,
        );
        _skipped = j['skipped'] == true;
        _collapsed = j['collapsed'] == true;
      } on FormatException {
        // A broken entry starts the guide over; the game is unharmed.
      } on TypeError {
        // Likewise for an entry of the wrong shape.
      }
    }
    _loaded = true;
    _pass();
    _shown = step;
    notifyListeners();
  }

  /// Ends the guide (settings: "Skip guide").
  Future<void> skip() async {
    _skipped = true;
    _shown = null;
    notifyListeners();
    await _save();
  }

  /// Folds or unfolds the goal strip.
  Future<void> setCollapsed(bool value) async {
    _collapsed = value;
    notifyListeners();
    await _save();
  }

  void _follow() {
    if (!_loaded) return;
    if (controller.gamesStarted != _games) {
      // A new game: the guide starts over.
      _games = controller.gamesStarted;
      _reached = 0;
      _skipped = false;
      _pass();
      _shown = step;
      notifyListeners();
      unawaited(_save());
      return;
    }
    if (ended) return;
    final s = controller.state;
    final shown = _shown;
    if (shown != null &&
        onboardingSteps[shown].done(
          s,
          controller.content,
          controller.playerId,
        )) {
      lastDone.value = onboardingSteps[shown].title;
    }
    final moved = _pass();
    final now = step;
    if (moved || now != _shown) {
      _shown = now;
      notifyListeners();
    }
  }

  /// Moves past the steps the state shows done; true when it moved, and
  /// then the place is saved.
  bool _pass() {
    final now = onboardingReached(
      controller.state,
      controller.content,
      controller.playerId,
      _reached,
    );
    if (now == _reached) return false;
    _reached = now;
    unawaited(_save());
    return true;
  }

  /// Writes the guide's place; a failure is reported, never thrown.
  Future<void> _save() async {
    try {
      await store.write(
        key,
        jsonEncode({
          'reached': _reached,
          'skipped': _skipped,
          'collapsed': _collapsed,
        }),
      );
    } catch (e, st) {
      _report(e, st, 'while saving the guide');
    }
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
    controller.removeListener(_follow);
    lastDone.dispose();
    super.dispose();
  }
}
