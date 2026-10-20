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

/// SDK 默认轨迹效果，中心为白色线条，外层为绿色光晕。
final class DefaultTrajectoryEffectRenderer extends ChangeNotifier
    implements TrajectoryEffectRendering {

  /// 每个渲染时间步的拖尾透明度保留系数。
  static const _fadeFactor = 0.93;

  /// 触点结束后允许拖尾继续显示的渲染帧数。
  static const _idleFadeFrameLimit = 48;

  /// 活动轨迹保留的最大历史帧数。
  static const _activeTrailFrameLimit = 66;

  /// 按轨迹标识保存的当前轨迹状态。
  final Map<TrajectoryID, _Trajectory> _trajectories =
      <TrajectoryID, _Trajectory>{};

  /// 驱动轨迹位置效果和拖尾消退的动画时钟。
  late final Ticker _animationTicker = Ticker(_tick);

  /// 按 60 fps 时间基准计算的渲染帧序号。
  int _frameIndex = 0;

  /// 用于叠加显示当前轨迹效果的视图。
  @override
  Widget get view => CustomPaint(
    painter: _TrajectoryPainter(renderer: this),
    size: Size.infinite,
  );

  /// 创建或替换指定触点的轨迹，并开始绘制效果。
  ///
  /// - [points]：本次采样的触点集合，顺序保持不变。
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

  /// 更新指定触点轨迹的位置；没有对应轨迹时创建。
  ///
  /// - [points]：本次采样的触点集合，顺序保持不变。
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

      trajectory.add(point.location, frameIndex: _frameIndex);
    }

    _startAnimating();
    notifyListeners();
  }

  /// 结束指定轨迹的输入，使其按渲染器策略消退。
  ///
  /// - [identifiers]：需要结束渲染的轨迹标识集合。
  @override
  void renderEnded(
    List<TrajectoryID> identifiers,
  ) {
    for (final id in identifiers) {
      final trajectory = _trajectories[id];

      if (trajectory == null) continue;

      if (trajectory.nodes.length < 2) {
        _trajectories.remove(id);
      } else {
        trajectory.finish(frameIndex: _frameIndex);
      }
    }

    notifyListeners();
  }

  /// 清除轨迹节点并停止刷新。
  @override
  void reset() {
    _trajectories.clear();
    _frameIndex = 0;
    _animationTicker.stop();
    notifyListeners();
  }

  /// 释放组件拥有的监听、动画和绘制资源。
  @override
  void dispose() {
    _animationTicker.dispose();
    super.dispose();
  }

  /// 仅在动画未运行时启动轨迹刷新。
  void _startAnimating() {
    if (!_animationTicker.isActive) {
      _animationTicker.start();
    }
  }

  /// 按实际经过时间推进轨迹消退并清理不可见节点。
  ///
  /// - [elapsed]：当前动画或采样周期内已过去的时间。
  void _tick(
    Duration elapsed,
  ) {
    // 以实际经过时间换算 60 fps 基准帧，保持不同刷新率设备的消退速度一致。
    _frameIndex = elapsed.inMicroseconds * 60 ~/ Duration.microsecondsPerSecond;

    _trajectories.removeWhere((_, trajectory) {
      if (!trajectory.isActive) {
        return _frameIndex - trajectory.endFrame! > _idleFadeFrameLimit;
      }

      // 额外保留一个前置节点，确保最早的可见线段仍能连续绘制。
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

/// 单条轨迹的位置节点、起止时间和消退状态。
final class _Trajectory {

  /// 创建轨迹，并以初始位置建立首个拖尾节点。
  ///
  /// - [location]：首个节点的视图逻辑像素坐标。
  /// - [startTime]：轨迹开始时间。
  /// - [frameIndex]：按 60 fps 时间基准计算的帧序号。
  _Trajectory({
    required Offset location,
    required this.startTime,
    required int frameIndex,
  }) : nodes = <_TrailNode>[
         _TrailNode(location: location, frameIndex: frameIndex),
       ];

  /// 轨迹开始采样的时间。
  final Duration startTime;

  /// 按采样顺序保存的轨迹位置节点。
  final List<_TrailNode> nodes;

  /// 当前轨迹是否仍接收触点输入。
  bool isActive = true;

  /// 触点结束时的渲染帧；仍在输入时为空。
  int? endFrame;

  /// 触点在视图内的逻辑像素坐标。
  Offset get location => nodes.last.location;

  /// 追加轨迹位置节点，同一渲染帧内更新最新位置。
  ///
  /// - [location]：触点在视图内的逻辑像素坐标。
  /// - [frameIndex]：按 60 fps 时间基准计算的渲染帧序号。
  void add(
    Offset location, {
    required int frameIndex,
  }) {
    if ((location - this.location).distanceSquared < 0.25) return;

    isActive = true;
    endFrame = null;
    nodes.add(_TrailNode(location: location, frameIndex: frameIndex));
  }

  /// 标记触点结束的渲染帧，后续仅显示逐步消退的拖尾。
  ///
  /// - [frameIndex]：按 60 fps 时间基准计算的渲染帧序号。
  void finish({
    required int frameIndex,
  }) {
    isActive = false;
    endFrame = frameIndex;
  }
}

/// 轨迹上的一个位置样本及其渲染帧序号。
final class _TrailNode {

  /// 创建轨迹位置样本。
  const _TrailNode({
    required this.location,
    required this.frameIndex,
  });

  /// 触点在视图内的逻辑像素坐标。
  final Offset location;

  /// 按 60 fps 时间基准计算的渲染帧序号。
  final int frameIndex;
}

/// 绘制轨迹核心、光晕和触点动画，并复用绘制资源。
final class _TrajectoryPainter extends CustomPainter {

  /// 创建轨迹绘制器，并监听渲染器重绘通知。
  ///
  /// - [renderer]：提供轨迹状态和重绘通知的渲染器。
  _TrajectoryPainter({
    required this.renderer,
  }) : super(repaint: renderer);

  /// 轨迹核心的绘制颜色。
  static const _coreColor = Colors.white;

  /// 轨迹外层光晕的颜色。
  static const _glowColor = Color(0xFF00FF64);

  /// 轨迹核心线宽，单位为逻辑像素。
  static const _coreWidth = 6.0;

  /// 轨迹外层光晕宽度，单位为逻辑像素。
  static const _glowWidth = 18.0;

  /// 每个拖尾透明度分组覆盖的渲染帧数。
  static const _cohortFrameSpan = 6;

  /// 按消退时段分组的轨迹路径缓存数量。
  static const _cohortCount = 12;

  /// 提供当前轨迹状态和重绘通知的渲染器。
  final DefaultTrajectoryEffectRenderer renderer;

  /// 按透明度时段复用的轨迹绘制路径。
  final List<Path> _paths = List<Path>.generate(_cohortCount, (_) => Path());

  /// 缓存路径当前对应的时间分组标识。
  final List<int?> _cohortIDs = List<int?>.filled(_cohortCount, null);

  /// 绘制轨迹外层光晕的画笔，可重复使用。
  final Paint _outerGlowPaint = Paint()
    ..strokeWidth = _glowWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
    ..blendMode = BlendMode.plus;

  /// 绘制轨迹内层光晕的画笔，可重复使用。
  final Paint _innerGlowPaint = Paint()
    ..strokeWidth = 10
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
    ..blendMode = BlendMode.plus;

  /// 绘制轨迹中心线条的画笔，可重复使用。
  final Paint _trailCorePaint = Paint()
    ..strokeWidth = _coreWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  /// 绘制触点动画的画笔，可重复使用。
  final Paint _effectPaint = Paint()..blendMode = BlendMode.plus;

  /// 绘制触点扩散环的画笔，可重复使用。
  final Paint _ringPaint = Paint()
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  /// 绘制触点中心的画笔，可重复使用。
  final Paint _headCorePaint = Paint()
    ..color = _coreColor
    ..blendMode = BlendMode.plus;

  /// 在当前画布中绘制可见轨迹及触点效果。
  ///
  /// - [canvas]：用于绘制轨迹效果的画布。
  /// - [size]：当前轨迹绘制区域的逻辑像素尺寸。
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    // 每条线段在显示期间始终归入同一消退分组。
    // 若不断切换分组，线段叠加处的亮度会变化，拖尾就会出现不自然的流动感。
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
            .pow(DefaultTrajectoryEffectRenderer._fadeFactor, age)
            .toDouble();

        if (opacity < 0.01) continue;

        final cohortID = end.frameIndex ~/ _cohortFrameSpan;
        final cohortSlot = cohortID % _cohortCount;

        if (_cohortIDs[cohortSlot] != cohortID) {
          _paths[cohortSlot].reset();
          _cohortIDs[cohortSlot] = cohortID;
        }

        _paths[cohortSlot]
          ..moveTo(start.location.dx, start.location.dy)
          ..lineTo(end.location.dx, end.location.dy);
      }
    }

    for (var index = 0; index < _paths.length; index += 1) {
      final cohortID = _cohortIDs[index];

      if (cohortID == null) continue;

      final cohortMiddleFrame =
          cohortID * _cohortFrameSpan + (_cohortFrameSpan - 1) / 2;
      final age = math.max(0.0, renderer._frameIndex - cohortMiddleFrame);
      final opacity = math
          .pow(DefaultTrajectoryEffectRenderer._fadeFactor, age)
          .toDouble();

      _drawTrailPath(canvas, _paths[index], opacity: opacity);
    }

    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

    for (final trajectory in renderer._trajectories.values) {
      if (!trajectory.isActive) continue;

      final elapsed = math.max(
        0.0,
        (now - trajectory.startTime).inMicroseconds /
            Duration.microsecondsPerSecond,
      );

      _drawPulsingRings(canvas, trajectory.location, elapsed);
      _drawOrbitParticles(canvas, trajectory.location, elapsed);
      _drawHeadGlow(canvas, trajectory.location);
    }
  }

  /// 按指定透明度绘制路径核心和外层光晕。
  ///
  /// - [canvas]：用于绘制轨迹效果的画布。
  /// - [path]：需要绘制的拖尾路径。
  /// - [opacity]：0～1 范围内的不透明度。
  void _drawTrailPath(
    Canvas canvas,
    Path path, {
    required double opacity,
  }) {
    _outerGlowPaint.color = _glowColor.withValues(alpha: 0.18 * opacity);
    canvas.drawPath(path, _outerGlowPaint);

    _innerGlowPaint.color = _glowColor.withValues(alpha: 0.44 * opacity);
    canvas.drawPath(path, _innerGlowPaint);

    _trailCorePaint.color = _coreColor.withValues(alpha: 0.72 * opacity);
    canvas.drawPath(path, _trailCorePaint);
  }

  /// 绘制当前触点的核心和光晕。
  ///
  /// - [canvas]：用于绘制轨迹效果的画布。
  /// - [point]：视图内的单个触点位置。
  void _drawHeadGlow(
    Canvas canvas,
    Offset point,
  ) {
    const glowRadius = 16.0;
    final bounds = Rect.fromCircle(center: point, radius: glowRadius);

    _effectPaint.shader = const RadialGradient(
      colors: <Color>[Color(0xC200FF64), Color(0x7400FF64), Color(0x0000FF64)],
      stops: <double>[0, 0.4, 1],
    ).createShader(bounds);
    canvas.drawCircle(point, glowRadius, _effectPaint);
    _headCorePaint.color = _coreColor.withValues(alpha: 0.88);
    canvas.drawCircle(point, 5, _headCorePaint);
  }

  /// 依据轨迹经过时间绘制扩散环。
  ///
  /// - [canvas]：用于绘制轨迹效果的画布。
  /// - [point]：视图内的单个触点位置。
  /// - [elapsed]：当前动画或采样周期内已过去的时间。
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
      canvas.drawCircle(point, radius, _ringPaint);
    }
  }

  /// 依据轨迹经过时间绘制环绕触点的粒子。
  ///
  /// - [canvas]：用于绘制轨迹效果的画布。
  /// - [point]：视图内的单个触点位置。
  /// - [elapsed]：当前动画或采样周期内已过去的时间。
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
      final bounds = Rect.fromCircle(center: center, radius: 6);

      _effectPaint.shader = RadialGradient(
        colors: <Color>[
          _glowColor.withValues(alpha: alpha),
          _glowColor.withValues(alpha: alpha * 0.6),
          _glowColor.withValues(alpha: 0),
        ],
        stops: const <double>[0, 0.4, 1],
      ).createShader(bounds);
      canvas.drawCircle(center, 6, _effectPaint);
    }
  }

  /// 判断新旧绘制代理是否需要重绘。
  ///
  /// - [oldDelegate]：上一次绘制使用的代理。
  ///
  /// 返回绘制代理是否需要更新当前画面。
  @override
  bool shouldRepaint(
    covariant _TrajectoryPainter oldDelegate,
  ) => false;
}
