import 'package:flutter/scheduler.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/star_map_painter.dart';
import 'package:space_idle/ui/map/map_transform.dart';
import 'package:space_idle/ui/map/star_map_scene.dart';

/// The home screen: the player's home system, drawn from the game state.
///
/// Bodies sit on their orbits around the star; owned ones carry a cyan ring
/// and their name, unowned ones are dimmed and say "Unclaimed". Routes are
/// curves and shipments glide along them between the 1 s game ticks. Tap a
/// body to [onSelect] it, or the "?" signal marker to [onSignalTap] its
/// system. Pinch to zoom from 0.5× to 3×.
///
/// Read-only: it changes nothing in the game.
class StarMap extends StatefulWidget {
  /// Creates the map.
  const StarMap({
    super.key,
    required this.controller,
    required this.onSelect,
    required this.onSignalTap,
    this.selectedId,
  });

  /// The game whose state is drawn; the map repaints when it notifies.
  final GameController controller;

  /// Called with a body's id when it is tapped.
  final void Function(String bodyId) onSelect;

  /// Called with a system's id when its signal marker is tapped.
  final void Function(String systemId) onSignalTap;

  /// The body drawn as selected.
  final String? selectedId;

  @override
  State<StarMap> createState() => _StarMapState();
}

class _StarMapState extends State<StarMap> with SingleTickerProviderStateMixin {
  static const double _minScale = 0.5;
  static const double _maxScale = 3;
  static const Duration _pulsePeriod = Duration(seconds: 2);

  final MapMotion _motion = MapMotion();
  final TransformationController _zoom = TransformationController();
  late final Ticker _ticker;

  /// Ticker time of the latest frame, and of the latest game tick.
  Duration _frameAt = Duration.zero;
  Duration _tickAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    widget.controller.addListener(_onGameChanged);
  }

  @override
  void didUpdateWidget(StarMap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onGameChanged);
      widget.controller.addListener(_onGameChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onGameChanged);
    _ticker.dispose();
    _motion.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    // A new tick: shipments restart their in-between motion from here.
    setState(() => _tickAt = _frameAt);
  }

  void _onFrame(Duration elapsed) {
    _frameAt = elapsed;
    final since =
        (elapsed - _tickAt).inMicroseconds / Duration.microsecondsPerSecond;
    _motion.update(
      sinceTick: since.clamp(0.0, 1.0),
      pulse:
          (elapsed.inMicroseconds % _pulsePeriod.inMicroseconds) /
          _pulsePeriod.inMicroseconds,
    );
  }

  /// Runs the ticker only while something moves and motion is allowed.
  void _syncTicker({required bool animate}) {
    if (animate && !_ticker.isActive) {
      _frameAt = Duration.zero;
      _tickAt = Duration.zero;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
      _motion.update(sinceTick: 0, pulse: 0);
    }
  }

  void _onTap(Offset canvasPx, StarMapScene scene, MapTransform t) {
    final hit = hitTestMap(
      scene,
      t,
      canvasPx,
      zoom: _zoom.value.getMaxScaleOnAxis(),
    );
    switch (hit) {
      case BodyHit(:final bodyId):
        widget.onSelect(bodyId);
      case SignalHit(:final systemId):
        widget.onSignalTap(systemId);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scene = buildStarMapScene(c.state, c.content, c.playerId, c.flow);
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        (scene.shipments.isNotEmpty || scene.signals.isNotEmpty);
    // Starting or stopping a ticker schedules at most a frame; it changes no
    // widget state, so it is safe here.
    _syncTicker(animate: animate);

    return ColoredBox(
      color: Palette.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final t = MapTransform.fit(size, scene.extent);
          return InteractiveViewer(
            transformationController: _zoom,
            minScale: _minScale,
            maxScale: _maxScale,
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onTap(d.localPosition, scene, t),
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: StarMapPainter(
                              scene: scene,
                              transform: t,
                              motion: _motion,
                              selectedId: widget.selectedId,
                            ),
                            isComplex: true,
                            willChange: animate,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final b in scene.bodies) ...[
                    _BodyLabel(body: b, transform: t),
                    _BodyNode(
                      body: b,
                      transform: t,
                      selected: b.id == widget.selectedId,
                      onTap: () => widget.onSelect(b.id),
                    ),
                  ],
                  for (final s in scene.signals)
                    _SignalNode(
                      signal: s,
                      systemName: _systemName(c.content, s.systemId),
                      transform: t,
                      onTap: () => widget.onSignalTap(s.systemId),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _systemName(Content content, String systemId) =>
    content.galaxy.systems.firstWhere((s) => s.id == systemId).name;

/// A square of the body's tap size centred on it, carrying its semantics.
///
/// It takes no pointer events itself: a pointer tap falls through to the
/// map's gesture, which hit-tests the same geometry. Screen readers use the
/// node's tap action, which selects the same body.
class _BodyNode extends StatelessWidget {
  const _BodyNode({
    required this.body,
    required this.transform,
    required this.selected,
    required this.onTap,
  });

  final MapBody body;
  final MapTransform transform;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = transform.toCanvas(body.position);
    final r = tapRadiusPx(body.radius * transform.scale);
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      width: 2 * r,
      height: 2 * r,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${body.name}, ${body.owned ? 'owned' : 'unclaimed'}',
        value: _value(body),
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }

  static String? _value(MapBody b) {
    final parts = [
      if (b.bottleneck) 'held back',
      if (b.projectProgress case final p?)
        '${_projectName(b.projectKind)} ${(p * 100).floor()}%',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String _projectName(ProjectKind? kind) => switch (kind) {
    ProjectKind.claim => 'claim',
    ProjectKind.expandSlots => 'new slot',
    ProjectKind.survey || ProjectKind.megaprojectStage || null => 'project',
  };
}

/// A body's visible name, and "Unclaimed" when the player does not own it,
/// centred under it. Decorative: [_BodyNode] carries the semantics.
class _BodyLabel extends StatelessWidget {
  const _BodyLabel({required this.body, required this.transform});

  static const double _width = 120;
  static const double _gap = 6;

  final MapBody body;
  final MapTransform transform;

  @override
  Widget build(BuildContext context) {
    final c = transform.toCanvas(body.position);
    final style = Theme.of(context).textTheme.labelSmall;
    return Positioned(
      left: c.dx - _width / 2,
      top: c.dy + body.radius * transform.scale + _gap,
      width: _width,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                body.name,
                textAlign: TextAlign.center,
                style: style?.copyWith(
                  color: body.owned ? Palette.text : Palette.muted,
                ),
              ),
              if (!body.owned)
                Text(
                  'Unclaimed',
                  textAlign: TextAlign.center,
                  style: style?.copyWith(color: Palette.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "?" over a signal marker, with its semantics; like [_BodyNode] it
/// lets pointer taps fall through to the map's gesture.
class _SignalNode extends StatelessWidget {
  const _SignalNode({
    required this.signal,
    required this.systemName,
    required this.transform,
    required this.onTap,
  });

  final MapSignal signal;
  final String systemName;
  final MapTransform transform;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = transform.toCanvas(signal.position);
    final r = tapRadiusPx(0);
    final n = signal.count;
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      width: 2 * r,
      height: 2 * r,
      child: Semantics(
        button: true,
        label: 'Unsurveyed signal in $systemName',
        value: '$n ${n == 1 ? 'signal' : 'signals'}',
        onTap: onTap,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Center(
              child: Text(
                '?',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Palette.cyan.withValues(alpha: 0.8)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
