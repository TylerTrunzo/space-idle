import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/settings_store.dart';
import 'package:space_idle/view/onboarding.dart';

/// The first-hour guide's place and the goal strip's fold, kept in the
/// app's settings ([SettingsStore]), not in the game save.
///
/// It follows the game: each time the controller notifies, steps the
/// state shows done are passed, each passing reported once through
/// [lastDone] ("Done: Build a second Smelter"). Steps already done when
/// the guide loads are skipped quietly. The guide ends after the last
/// step, or with [skip].
class Guide extends ChangeNotifier {
  /// Creates the guide for [controller], kept in [store].
  Guide({required this.controller, required this.store}) {
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

  /// The title of the step passed last, for a short "Done" message; the
  /// listener clears it once shown.
  final ValueNotifier<String?> lastDone = ValueNotifier(null);

  /// Whether the goal strip is folded to its first row.
  bool get collapsed => _collapsed;

  /// Whether the guide has ended: skipped, or every step passed.
  bool get ended => _skipped || _reached >= onboardingSteps.length;

  /// The step to show in the strip's Now slot, or null once the guide has
  /// ended ([onboardingStepAt]).
  int? get step => !_loaded || ended
      ? null
      : onboardingStepAt(
          controller.state,
          controller.content,
          controller.playerId,
          _reached,
        );

  /// Reads the stored place, then passes what the state already shows
  /// done, quietly.
  Future<void> load() async {
    final text = await store.read(key);
    if (text != null) {
      try {
        final j = jsonDecode(text) as Map<String, Object?>;
        _reached = (j['reached'] as num?)?.toInt() ?? 0;
        _skipped = j['skipped'] == true;
        _collapsed = j['collapsed'] == true;
      } on FormatException {
        // A broken entry starts the guide over; the game is unharmed.
      } on TypeError {
        // Likewise for an entry of the wrong shape.
      }
    }
    _loaded = true;
    _pass(quietly: true);
    notifyListeners();
  }

  /// Ends the guide (settings: "Skip guide").
  Future<void> skip() async {
    _skipped = true;
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
    if (_loaded && !ended) _pass(quietly: false);
  }

  void _pass({required bool quietly}) {
    final now = onboardingReached(
      controller.state,
      controller.content,
      controller.playerId,
      _reached,
    );
    if (now == _reached) return;
    final last = onboardingSteps[now - 1];
    _reached = now;
    if (!quietly) lastDone.value = last.title;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() => store.write(
    key,
    jsonEncode({
      'reached': _reached,
      'skipped': _skipped,
      'collapsed': _collapsed,
    }),
  );

  @override
  void dispose() {
    controller.removeListener(_follow);
    lastDone.dispose();
    super.dispose();
  }
}
