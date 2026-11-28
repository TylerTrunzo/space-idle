import 'package:flutter/scheduler.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/map/label_layout.dart';
import 'package:space_idle/ui/map/map_transform.dart';
import 'package:space_idle/ui/map/star_map_painter.dart';
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

  /// Below this height (a phone sheet pulled high) the system is drawn
  /// too small for every name to fit clear of the others: only the
  /// selected body keeps its label.
  static const double compactHeight = 200;

  @override
  State<StarMap> createState() => _StarMapState();
}

class _StarMapState extends State<StarMap> with SingleTickerProviderStateMixin {
  static const double _minScale = 0.5;
  static const double _maxScale = 3;

  final MapMotion _motion = MapMotion();
  final TransformationController _zoom = TransformationController();
  late final Ticker _ticker;

  /// The scene drawn, rebuilt when the game notifies, and the game time
  /// it was built at.
  late StarMapScene _scene;
  late double _sceneTime;

  /// Whether the platform allows animation (`disableAnimations` is off).
  bool _animationsAllowed = true;

  /// Ticker time of the latest frame, and of the latest game tick.
  Duration _frameAt = Duration.zero;
  Duration _tickAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    _scene = _buildScene();
    _sceneTime = widget.controller.state.time;
    widget.controller.addListener(_onGameChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsAllowed = !MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(StarMap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onGameChanged);
      widget.controller.addListener(_onGameChanged);
      _refresh();
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

  StarMapScene _buildScene() {
    final c = widget.controller;
    return buildStarMapScene(c.state, c.content, c.playerId, c.flow);
  }

  void _onGameChanged() => setState(_refresh);

  /// Rebuilds the scene. Only a tick (game time moved) restarts the
  /// in-between motion: a command or a cleared summary also notifies, and
  /// restarting then would pull every shipment back to where it was at the
  /// last tick.
  void _refresh() {
    _scene = _buildScene();
    final time = widget.controller.state.time;
    if (time != _sceneTime) {
      _sceneTime = time;
      _tickAt = _frameAt;
    }
    _syncTicker();
  }

  void _onFrame(Duration elapsed) {
    _frameAt = elapsed;
    final since =
        (elapsed - _tickAt).inMicroseconds / Duration.microsecondsPerSecond;
    _motion.update(sinceTick: since.clamp(0.0, 1.0));
  }

  /// Runs the ticker only while shipments are in flight and motion is
  /// allowed: nothing else on the map moves.
  void _syncTicker() {
    final animate = _animationsAllowed && _scene.shipments.isNotEmpty;
    if (animate && !_ticker.isActive) {
      _frameAt = Duration.zero;
      _tickAt = Duration.zero;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
      _motion.update(sinceTick: 0);
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
    final scene = _scene;
    final animate = _ticker.isActive;

    return ColoredBox(
      color: Palette.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final t = MapTransform.fitRect(size, scene.bounds);
          final labels = _labelRects(context, scene, t, size);
          return InteractiveViewer(
            transformationController: _zoom,
            minScale: _minScale,
            maxScale: _maxScale,
            // The viewer never zooms out past the point where the margin-
            // inflated child fills the viewport. Half a viewport each side
            // doubles the boundary, so that floor is exactly minScale, 0.5x;
            // being finite, it also keeps the map from being panned out of
            // reach.
            boundaryMargin: EdgeInsets.symmetric(
              horizontal: size.width / 2,
              vertical: size.height / 2,
            ),
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onTap(d.localPosition, scene, t),
                      child: ExcludeSemantics(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Two layers: the static one repaints at most
                            // once a tick, the moving one every frame.
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: StarMapPainter(
                                  scene: scene,
                                  transform: t,
                                  selectedId: widget.selectedId,
                                ),
                                isComplex: true,
                              ),
                            ),
                            RepaintBoundary(
                              child: CustomPaint(
                                painter: MapMotionPainter(
                                  scene: scene,
                                  transform: t,
                                  motion: _motion,
                                ),
                                willChange: animate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  for (final (i, b) in scene.bodies.indexed) ...[
                    if (size.height >= StarMap.compactHeight ||
                        b.id == widget.selectedId)
                      _BodyLabel(body: b, rect: labels[i]),
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

/// Where each body's label goes on the canvas: measured at the current
/// text scale, then placed clear of the star, the discs and each other.
List<Rect> _labelRects(
  BuildContext context,
  StarMapScene scene,
  MapTransform t,
  Size size,
) {
  final style = _BodyLabel.styleOf(context);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  Size measure(List<String> lines) {
    var width = 0.0;
    var height = 0.0;
    for (final line in lines) {
      final tp = TextPainter(
        text: TextSpan(text: line, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width = width < tp.width ? tp.width : width;
      height += tp.height;
      tp.dispose();
    }
    return Size(width.ceilToDouble() + 2, height.ceilToDouble());
  }

  return placeLabels(
    bodies: [
      for (final b in scene.bodies)
        LabelTarget(
          t.toCanvas(b.position),
          b.radius * t.scale,
          measure(_BodyLabel.linesOf(b)),
        ),
    ],
    star: Rect.fromCircle(center: t.origin, radius: scene.starRadius * t.scale),
    canvas: Offset.zero & size,
  );
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
        container: true,
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
/// in the rect [_labelRects] chose. Decorative: [_BodyNode] carries the
/// semantics.
class _BodyLabel extends StatelessWidget {
  const _BodyLabel({required this.body, required this.rect});

  final MapBody body;
  final Rect rect;

  static TextStyle? styleOf(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall;

  /// The label's lines, as measured and as shown.
  static List<String> linesOf(MapBody b) => [b.name, if (!b.owned) 'Unclaimed'];

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context);
    final lines = linesOf(body);
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        key: ValueKey('label-${body.id}'),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, line) in lines.indexed)
                Text(
                  line,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  textAlign: TextAlign.center,
                  style: style?.copyWith(
                    color: i == 0 && body.owned ? Palette.text : Palette.muted,
                  ),
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
        container: true,
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
