import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';

/// Lays a short banner over [child] when the player reaches a milestone
/// in live play: "Milestone reached: First Claim", for [showFor].
///
/// Milestones that come with a load, an import, a new game or an away
/// catch-up are not announced here: the game had them already, or the
/// away summary lists them. It fades in and out, or just appears and
/// goes with reduce-motion on.
class MilestoneBanner extends StatefulWidget {
  /// Wraps [child].
  const MilestoneBanner({super.key, required this.child});

  /// The screen under the banner.
  final Widget child;

  /// How long a banner stays.
  static const Duration showFor = Duration(seconds: 4);

  @override
  State<MilestoneBanner> createState() => _MilestoneBannerState();
}

class _MilestoneBannerState extends State<MilestoneBanner> {
  GameController? _c;

  /// What the game had reached at the last notification.
  Set<String> _seen = const {};

  /// The game those are for: a different one starts the count over.
  int _games = -1;
  Object? _state;

  String? _text;
  bool _shown = false;

  /// Whether reduce-motion was on at the last build.
  bool _still = false;
  Timer? _hide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = ControllerScope.of(context);
    if (!identical(c, _c)) {
      _c = c;
      _reset(c);
      return;
    }
    _check(c);
  }

  void _reset(GameController c) {
    _seen = {...c.state.faction(c.playerId).reachedMilestones};
    _games = c.gamesStarted;
    _state = c.state;
  }

  void _check(GameController c) {
    // Another game in place (a load, import or new game): what it has
    // reached is not news.
    if (c.gamesStarted != _games || !identical(c.state, _state)) {
      _reset(c);
      return;
    }
    final now = c.state.faction(c.playerId).reachedMilestones;
    if (now.length == _seen.length) return;
    final away = {
      for (final s in c.pendingAwaySummaries) ...s.milestonesReached,
    };
    final fresh = [
      for (final m in c.content.milestones)
        if (now.contains(m.id) && !_seen.contains(m.id) && !away.contains(m.id))
          m.name,
    ];
    _seen = {...now};
    if (fresh.isEmpty) return;
    _text = fresh.length == 1
        ? 'Milestone reached: ${fresh.single}'
        : 'Milestones reached: ${fresh.join(', ')}';
    _shown = true;
    _hide?.cancel();
    _hide = Timer(MilestoneBanner.showFor, () {
      if (!mounted) return;
      setState(() {
        _shown = false;
        // No fade to wait for.
        if (_still) _text = null;
      });
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = _still = MediaQuery.disableAnimationsOf(context);
    final text = _text;
    return Stack(
      children: [
        widget.child,
        if (text != null)
          Positioned(
            left: 16,
            right: 16,
            top: 8,
            child: IgnorePointer(
              ignoring: !_shown,
              child: AnimatedOpacity(
                key: const ValueKey('milestone-banner-fade'),
                opacity: _shown ? 1 : 0,
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                onEnd: () {
                  if (!_shown && mounted) setState(() => _text = null);
                },
                child: _shown || !still
                    ? _Banner(
                        key: const ValueKey('milestone-banner'),
                        text: text,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: Palette.panel,
      elevation: 4,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Palette.cyan),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.emoji_events_outlined, color: Palette.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    ),
  );
}
