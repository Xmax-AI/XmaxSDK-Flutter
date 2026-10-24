//
//  DefaultTrajectoryEffectRenderer.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'TrajectoryEffectRendering.dart';

/// The default interaction trail renderer, with a white core and green glow.
final class DefaultTrajectoryEffectRenderer extends ChangeNotifier
    implements TrajectoryEffectRendering {

  /// The fraction of trail opacity retained per rendering time step.
  static const _fadeFactor = 0.93;

  /// The number of rendering frames for which a trail remains after input ends.
  static const _idleFadeFrameLimit = 48;

  /// The maximum number of historical frames retained for an active trail.
  static const _activeTrailFrameLimit = 66;

  /// Current trail states indexed by trail identifier.
  final Map<TrajectoryID, _Trajectory> _trajectories =
      <TrajectoryID, _Trajectory>{};

  /// The animation clock driving trail effects and fading.
  late final Ticker _animationTicker = Ticker(_tick);

  /// The rendering frame index based on a 60 fps time base.
  int _frameIndex = 0;

  /// The overlay view displaying the current trail effects.
  @override
  Widget get view => CustomPaint(
    painter: _TrajectoryPainter(renderer: this),
    size: Size.infinite,
  );

  /// Creates or replaces a pointer's trail and begins rendering its effects.
  ///
  /// Parameters:
  /// - [points]: The sampled interaction points, preserving their order.
  @override
  void renderBegan(
    List<TrajectoryPoint> points,
  ) {
    for (final point in points) {
      _trajectories[point.id] = _Trajectory(
        location: point.location,
        startTime: point.timestamp,
        frameIndex: _frameIndex,
      );
    }

    _startAnimating();
    notifyListeners();
  }

  /// Updates a pointer's trail position, creating the trail if it does not exist.
  ///
  /// Parameters:
  /// - [points]: The sampled interaction points, preserving their order.
  @override
  void renderMoved(
    List<TrajectoryPoint> points,
  ) {
    for (final point in points) {
      final trajectory = _trajectories[point.id];

      if (trajectory == null) {
        _trajectories[point.id] = _Trajectory(
          location: point.location,
          startTime: point.timestamp,
          frameIndex: _frameIndex,
        );
        continue;
      }

      trajectory.add(
        point.location,
        frameIndex: _frameIndex,
      );
    }

    _startAnimating();
    notifyListeners();
  }

  /// Ends input for the specified trails, allowing them to fade according to the renderer policy.
  ///
  /// Parameters:
  /// - [identifiers]: The identifiers of trails whose input should end.
  @override
  void renderEnded(
    List<TrajectoryID> identifiers,
  ) {
    for (final id in identifiers) {
      final trajectory = _trajectories[id];

      if (trajectory == null) {
        continue;
      }

      if (trajectory.nodes.length < 2) {
        _trajectories.remove(id);
      } else {
        trajectory.finish(frameIndex: _frameIndex);
      }
    }

    notifyListeners();
  }

  /// Clears trail nodes and stops rendering updates.
  @override
  void reset() {
    _trajectories.clear();
    _frameIndex = 0;
    _animationTicker.stop();
    notifyListeners();
  }

  /// Releases listeners, animation resources, and drawing resources owned by the component.
  @override
  void dispose() {
    _animationTicker.dispose();
    super.dispose();
  }

  /// Starts trail updates only if the animation is not running.
  void _startAnimating() {
    if (!_animationTicker.isActive) {
      _animationTicker.start();
    }
  }

  /// Advances trail fading by elapsed time and removes invisible nodes.
  ///
  /// Parameters:
  /// - [elapsed]: The time elapsed in the current animation or sampling cycle.
  void _tick(
    Duration elapsed,
  ) {
    // Convert elapsed time to a 60 fps frame index for consistent fading across display refresh rates.
    _frameIndex = elapsed.inMicroseconds * 60 ~/ Duration.microsecondsPerSecond;

    _trajectories.removeWhere((
      _,
      trajectory,
    ) {
      if (!trajectory.isActive) {
        return _frameIndex - trajectory.endFrame! > _idleFadeFrameLimit;
      }

      // Retain one preceding node so the earliest visible segment remains continuous.
      while (trajectory.nodes.length > 2 &&
          _frameIndex - trajectory.nodes[1].frameIndex >
              _activeTrailFrameLimit) {
        trajectory.nodes.removeAt(0);
      }

      return false;
    });

    notifyListeners();
    if (_trajectories.isEmpty) {
      _animationTicker.stop();
      _frameIndex = 0;
    }
  }
}

/// The position nodes, timing, and fading state for a single trail.
final class _Trajectory {

  /// Creates a trail with its first node at the initial position.
  ///
  /// Parameters:
  /// - [location]: The first node's view coordinates, in logical pixels.
  /// - [startTime]: The trail start time.
  /// - [frameIndex]: The frame index based on a 60 fps time base.
  _Trajectory({
    required Offset location,
    required this.startTime,
    required int frameIndex,
  }) : nodes = <_TrailNode>[
         _TrailNode(
           location: location,
           frameIndex: frameIndex,
         ),
       ];

  /// The time at which trail sampling began.
  final Duration startTime;

  /// Trail position nodes in sampling order.
  final List<_TrailNode> nodes;

  /// Whether the trail still accepts pointer input.
  bool isActive = true;

  /// The rendering frame at which input ended; null while input remains active.
  int? endFrame;

  /// The pointer position within the view, in logical pixels.
  Offset get location => nodes.last.location;

  /// Appends a trail node, updating the latest position for samples within the same rendering
  /// frame.
  ///
  /// Parameters:
  /// - [location]: The pointer position within the view, in logical pixels.
  /// - [frameIndex]: The rendering frame index based on a 60 fps time base.
  void add(
    Offset location, {
    required int frameIndex,
  }) {
    if ((location - this.location).distanceSquared < 0.25) {
      return;
    }

    isActive = true;
    endFrame = null;
    nodes.add(_TrailNode(
      location: location,
      frameIndex: frameIndex,
    ));
  }

  /// Records the input end frame, leaving only the fading trail visible afterward.
  ///
  /// Parameters:
  /// - [frameIndex]: The rendering frame index based on a 60 fps time base.
  void finish({
    required int frameIndex,
  }) {
    isActive = false;
    endFrame = frameIndex;
  }
}

/// A trail position sample and its rendering frame index.
final class _TrailNode {

  /// Creates a trail position sample.
  const _TrailNode({
    required this.location,
    required this.frameIndex,
  });

  /// The pointer position within the view, in logical pixels.
  final Offset location;

  /// The rendering frame index based on a 60 fps time base.
  final int frameIndex;
}

/// Draws trail cores, glows, and pointer animations using reusable drawing resources.
final class _TrajectoryPainter extends CustomPainter {

  /// Creates a trail painter that listens for renderer repaint notifications.
  ///
  /// Parameters:
  /// - [renderer]: The renderer providing trail state and repaint notifications.
  _TrajectoryPainter({
    required this.renderer,
  }) : super(repaint: renderer);

  /// The trail core color.
  static const _coreColor = Colors.white;

  /// The outer trail glow color.
  static const _glowColor = Color(0xFF00FF64);

  /// The trail core width, in logical pixels.
  static const _coreWidth = 6.0;

  /// The outer glow width, in logical pixels.
  static const _glowWidth = 18.0;

  /// The number of rendering frames in each trail opacity group.
  static const _cohortFrameSpan = 6;

  /// The number of cached trail paths grouped by fading interval.
  static const _cohortCount = 12;

  /// The renderer providing current trail state and repaint notifications.
  final DefaultTrajectoryEffectRenderer renderer;

  /// Reusable trail paths grouped by opacity interval.
  final List<Path> _paths = List<Path>.generate(
    _cohortCount,
    (
      _,
    ) => Path(),
  );

  /// The time-group identifiers associated with cached paths.
  final List<int?> _cohortIDs = List<int?>.filled(
    _cohortCount,
    null,
  );

  /// The reusable paint for outer trail glows.
  final Paint _outerGlowPaint = Paint()
    ..strokeWidth = _glowWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      12,
    )
    ..blendMode = BlendMode.plus;

  /// The reusable paint for inner trail glows.
  final Paint _innerGlowPaint = Paint()
    ..strokeWidth = 10
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      6,
    )
    ..blendMode = BlendMode.plus;

  /// The reusable paint for trail cores.
  final Paint _trailCorePaint = Paint()
    ..strokeWidth = _coreWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  /// The reusable paint for pointer animations.
  final Paint _effectPaint = Paint()..blendMode = BlendMode.plus;

  /// The reusable paint for pointer ripple rings.
  final Paint _ringPaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  /// The reusable paint for pointer centers.
  final Paint _headCorePaint = Paint()
    ..color = _coreColor
    ..blendMode = BlendMode.plus;

  /// Draws visible trails and pointer effects on the current canvas.
  ///
  /// Parameters:
  /// - [canvas]: The canvas on which to draw trail effects.
  /// - [size]: The trail drawing area's dimensions, in logical pixels.
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    // Keep each segment in the same fading group throughout its visible lifetime.
    // Changing groups alters brightness at overlaps and creates an artificial flowing effect.
    for (var index = 0; index < _cohortCount; index += 1) {
      _paths[index].reset();
      _cohortIDs[index] = null;
    }

    for (final trajectory in renderer._trajectories.values) {
      for (var index = 1; index < trajectory.nodes.length; index += 1) {
        final start = trajectory.nodes[index - 1];
        final end = trajectory.nodes[index];
        final age = renderer._frameIndex - end.frameIndex;
        final opacity = math
            .pow(
              DefaultTrajectoryEffectRenderer._fadeFactor,
              age,
            )
            .toDouble();

        if (opacity < 0.01) {
          continue;
        }

        final cohortID = end.frameIndex ~/ _cohortFrameSpan;
        final cohortSlot = cohortID % _cohortCount;

        if (_cohortIDs[cohortSlot] != cohortID) {
          _paths[cohortSlot].reset();
          _cohortIDs[cohortSlot] = cohortID;
        }

        _paths[cohortSlot]
          ..moveTo(
            start.location.dx,
            start.location.dy,
          )
          ..lineTo(
            end.location.dx,
            end.location.dy,
          );
      }
    }

    for (var index = 0; index < _paths.length; index += 1) {
      final cohortID = _cohortIDs[index];

      if (cohortID == null) {
        continue;
      }

      final cohortMiddleFrame =
          cohortID * _cohortFrameSpan + (_cohortFrameSpan - 1) / 2;
      final age = math.max(0.0, renderer._frameIndex - cohortMiddleFrame);
      final opacity = math
          .pow(
            DefaultTrajectoryEffectRenderer._fadeFactor,
            age,
          )
          .toDouble();

      _drawTrailPath(
        canvas,
        _paths[index],
        opacity: opacity,
      );
    }

    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

    for (final trajectory in renderer._trajectories.values) {
      if (!trajectory.isActive) {
        continue;
      }

      final elapsed = math.max(
        0.0,
        (now - trajectory.startTime).inMicroseconds /
            Duration.microsecondsPerSecond,
      );

      _drawPulsingRings(
        canvas,
        trajectory.location,
        elapsed,
      );
      _drawOrbitParticles(
        canvas,
        trajectory.location,
        elapsed,
      );
      _drawHeadGlow(
        canvas,
        trajectory.location,
      );
    }
  }

  /// Draws a path's core and outer glow at the specified opacity.
  ///
  /// Parameters:
  /// - [canvas]: The canvas on which to draw trail effects.
  /// - [path]: The trail path to draw.
  /// - [opacity]: The opacity, from 0 to 1.
  void _drawTrailPath(
    Canvas canvas,
    Path path, {
    required double opacity,
  }) {
    _outerGlowPaint.color = _glowColor.withValues(alpha: 0.18 * opacity);
    canvas.drawPath(
      path,
      _outerGlowPaint,
    );

    _innerGlowPaint.color = _glowColor.withValues(alpha: 0.44 * opacity);
    canvas.drawPath(
      path,
      _innerGlowPaint,
    );

    _trailCorePaint.color = _coreColor.withValues(alpha: 0.72 * opacity);
    canvas.drawPath(
      path,
      _trailCorePaint,
    );
  }

  /// Draws the current pointer's core and glow.
  ///
  /// Parameters:
  /// - [canvas]: The canvas on which to draw trail effects.
  /// - [point]: A single interaction point within the view.
  void _drawHeadGlow(
    Canvas canvas,
    Offset point,
  ) {
    const glowRadius = 16.0;
    final bounds = Rect.fromCircle(
      center: point,
      radius: glowRadius,
    );

    _effectPaint.shader = const RadialGradient(
      colors: <Color>[Color(0xC200FF64), Color(0x7400FF64), Color(0x0000FF64)],
      stops: <double>[0, 0.4, 1],
    ).createShader(bounds);
    canvas.drawCircle(
      point,
      glowRadius,
      _effectPaint,
    );
    _headCorePaint.color = _coreColor.withValues(alpha: 0.88);
    canvas.drawCircle(
      point,
      5,
      _headCorePaint,
    );
  }

  /// Draws ripple rings using the trail's elapsed time.
  ///
  /// Parameters:
  /// - [canvas]: The canvas on which to draw trail effects.
  /// - [point]: A single interaction point within the view.
  /// - [elapsed]: The time elapsed in the current animation or sampling cycle.
  void _drawPulsingRings(
    Canvas canvas,
    Offset point,
    double elapsed,
  ) {
    for (var index = 0; index < 2; index += 1) {
      final indexValue = index.toDouble();
      final baseRadius = 14 + indexValue * 18;
      final pulseOffset = elapsed * 1.2 + indexValue * 0.5;
      final pulse = (math.sin(pulseOffset * math.pi * 2) + 1) / 2;
      final radius = baseRadius + pulse * 8;
      final alpha = 0.42 * (1 - indexValue * 0.2) * (0.5 + pulse * 0.5);

      _ringPaint.color = _glowColor.withValues(alpha: alpha);
      canvas.drawCircle(
        point,
        radius,
        _ringPaint,
      );
    }
  }

  /// Draws particles around the pointer using the trail's elapsed time.
  ///
  /// Parameters:
  /// - [canvas]: The canvas on which to draw trail effects.
  /// - [point]: A single interaction point within the view.
  /// - [elapsed]: The time elapsed in the current animation or sampling cycle.
  void _drawOrbitParticles(
    Canvas canvas,
    Offset point,
    double elapsed,
  ) {
    for (var index = 0; index < 4; index += 1) {
      final indexValue = index.toDouble();
      final direction = index.isEven ? 1.0 : -1.0;
      final baseAngle = indexValue / 4 * math.pi * 2;
      final angle = baseAngle + elapsed * 0.06 * direction;
      final center = Offset(
        point.dx + math.cos(angle) * 22,
        point.dy + math.sin(angle) * 22,
      );
      final alpha = 0.5 * (0.6 + math.sin(elapsed * 3 + indexValue) * 0.4);
      final bounds = Rect.fromCircle(
        center: center,
        radius: 6,
      );

      _effectPaint.shader = RadialGradient(
        colors: <Color>[
          _glowColor.withValues(alpha: alpha),
          _glowColor.withValues(alpha: alpha * 0.6),
          _glowColor.withValues(alpha: 0),
        ],
        stops: const <double>[0, 0.4, 1],
      ).createShader(bounds);
      canvas.drawCircle(
        center,
        6,
        _effectPaint,
      );
    }
  }

  /// Determines whether a change of painter requires repainting.
  ///
  /// Parameters:
  /// - [oldDelegate]: The painter used for the previous paint operation.
  ///
  /// Returns whether the painter needs to update the current image.
  @override
  bool shouldRepaint(
    covariant _TrajectoryPainter oldDelegate,
  ) => false;
}
