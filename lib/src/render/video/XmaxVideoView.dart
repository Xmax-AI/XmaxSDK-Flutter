//
//  XmaxVideoView.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../foundation/media/video/VideoContentMode.dart';
import '../../media/interaction/InteractionFrame.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../trajectory/DefaultTrajectoryEffectRenderer.dart';
import '../trajectory/TrajectoryEffectRendering.dart';
import '../trajectory/TrajectoryRegistry.dart';
import 'VideoRenderBinding.dart';
import 'VideoRenderRegistry.dart';
import 'VideoRenderSurface.dart';

/// 显示 Xmax 本地或远端实时视频轨道的 Flutter 视图。
final class XmaxVideoView extends StatefulWidget {

  /// 创建单轨道视频视图。
  const XmaxVideoView({
    super.key,
    this.track,
    this.videoContentMode = VideoContentMode.fill,
    this.isInteractionEnabled = true,
    this.trajectoryRenderer,
  });

  /// 要显示的视频轨道；未指定时显示黑色背景，不创建视频纹理。
  final RealtimeVideoTrack? track;

  /// 视频缩放方式，默认等比填满并裁剪超出部分。
  final VideoContentMode videoContentMode;

  /// 是否启用触点采样和轨迹渲染，默认启用。
  final bool isInteractionEnabled;

  /// 自定义轨迹渲染器；为空时使用 SDK 默认效果。
  ///
  /// 由接入方提供时，接入方负责渲染器生命周期；默认渲染器由视图释放。
  final TrajectoryEffectRendering? trajectoryRenderer;

  /// 创建管理单轨道视频与交互资源的组件状态。
  @override
  State<XmaxVideoView> createState() => _XmaxVideoViewState();
}

/// 维护视频渲染、触点采样和轨迹效果资源。
final class _XmaxVideoViewState extends State<XmaxVideoView>
    with SingleTickerProviderStateMixin {

  /// 触点采样间隔，对应每秒最多 30 次周期采样。
  static const _samplingInterval = Duration(
    microseconds: Duration.microsecondsPerSecond ~/ 30,
  );

  /// 提供当前轨迹状态和重绘通知的渲染器。
  late TrajectoryEffectRendering _renderer;

  /// 当前视图是否负责释放轨迹渲染器。
  late bool _ownsRenderer;

  /// 按显示时钟驱动触点采样的计时器。
  late final Ticker _samplingTicker;

  /// 按指针标识保存的所有活动触点。
  final Map<int, _ActivePointer> _activePointers = <int, _ActivePointer>{};

  /// 当前触点采样周期经过的时间。
  Duration _currentSamplingTime = Duration.zero;

  /// 当前周期最近一次提交触点采样的时间。
  Duration? _lastSampleTime;

  /// 最近一次触点采样的视图尺寸，单位为逻辑像素。
  Size? _samplingViewportSize;

  /// 当前视图触点采样的提交入口。
  void Function(
    InteractionFrame frame,
  )?
  _samplingListener;

  /// 初始化视图监听、触点采样和本地绘制资源。
  @override
  void initState() {
    super.initState();
    _ownsRenderer = widget.trajectoryRenderer == null;
    _renderer = widget.trajectoryRenderer ?? DefaultTrajectoryEffectRenderer();
    _samplingTicker = createTicker(_sampleActivePointers);
  }

  /// 根据新的组件配置更新轨道绑定、交互和渲染器所有权。
  ///
  /// - [oldWidget]：更新前的组件配置。
  @override
  void didUpdateWidget(
    covariant XmaxVideoView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    final rendererChanged =
        oldWidget.trajectoryRenderer != widget.trajectoryRenderer;

    if (rendererChanged ||
        oldWidget.track != widget.track ||
        oldWidget.isInteractionEnabled != widget.isInteractionEnabled) {
      _resetPointers();
    }

    if (rendererChanged) {
      _disposeOwnedRenderer();
      _ownsRenderer = widget.trajectoryRenderer == null;
      _renderer =
          widget.trajectoryRenderer ?? DefaultTrajectoryEffectRenderer();
    }
  }

  /// 释放组件拥有的监听、动画和绘制资源。
  @override
  void dispose() {
    _resetPointers();
    _disposeOwnedRenderer();
    _samplingTicker.dispose();
    super.dispose();
  }

  /// 根据当前绑定和显示配置构建视频或轨迹视图。
  ///
  /// - [context]：组件构建上下文。
  ///
  /// 返回当前视频或轨迹效果的组件树。
  @override
  Widget build(
    BuildContext context,
  ) {
    final track = widget.track;

    if (track == null) {
      return const ColoredBox(color: Colors.black);
    }

    final handle = VideoRenderRegistry.handleFor(track);
    final video = handle == null
        ? const ColoredBox(color: Colors.black)
        : ValueListenableBuilder<VideoRenderBinding?>(
            valueListenable: handle,
            builder: (context, binding, _) => _buildVideo(binding),
          );

    final interaction = TrajectoryRegistry.bindingFor(track);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          video,
          if (widget.isInteractionEnabled && interaction != null)
            LayoutBuilder(
              builder: (context, constraints) => Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _pointerDown(
                  event,
                  constraints.biggest,
                  interaction.interactionListener,
                ),
                onPointerMove: (event) => _pointerMove(
                  event,
                  constraints.biggest,
                  interaction.interactionListener,
                ),
                onPointerUp: _pointerUp,
                onPointerCancel: _pointerUp,
                child: IgnorePointer(child: _renderer.view),
              ),
            ),
        ],
      ),
    );
  }

  /// 根据当前轨道绑定构建原生视频纹理。
  ///
  /// - [binding]：当前轨道的渲染或交互配置。
  ///
  /// 返回当前视频或轨迹效果的组件树。
  Widget _buildVideo(
    VideoRenderBinding? binding,
  ) {
    if (binding == null) return const ColoredBox(color: Colors.black);

    return VideoRenderSurface(
      binding: binding,
      track: widget.track,
      contentMode: widget.videoContentMode,
    );
  }

  /// 开始触点轨迹并立即提交首个交互采样。
  ///
  /// - [event]：本次按下、移动或释放的指针事件。
  /// - [size]：当前视频视图的逻辑像素尺寸。
  /// - [listener]：接收本次通知的回调。
  void _pointerDown(
    PointerDownEvent event,
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    final pointer = _ActivePointer(
      id: createTrajectoryID(event.pointer),
      location: event.localPosition,
    );

    _activePointers[event.pointer] = pointer;
    _updateSamplingContext(size, listener);
    _renderer.renderBegan(<TrajectoryPoint>[_point(pointer, size)]);

    // 首个触点立即提交，随后由屏幕刷新计时器以 30 Hz 采样所有活动触点。
    _submit(size, listener);
    if (!_samplingTicker.isActive) {
      _currentSamplingTime = Duration.zero;
      _lastSampleTime = Duration.zero;
      _samplingTicker.start();
    } else {
      _lastSampleTime = _currentSamplingTime;
    }
  }

  /// 更新按下触点的位置并同步轨迹显示。
  ///
  /// - [event]：本次按下、移动或释放的指针事件。
  /// - [size]：当前视频视图的逻辑像素尺寸。
  /// - [listener]：接收本次通知的回调。
  void _pointerMove(
    PointerMoveEvent event,
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    final pointer = _activePointers[event.pointer];

    if (pointer == null) {
      return;
    }

    pointer.location = event.localPosition;
    _updateSamplingContext(size, listener);
    _renderer.renderMoved(<TrajectoryPoint>[_point(pointer, size)]);
  }

  /// 结束触点轨迹；没有活动触点时停止采样。
  ///
  /// - [event]：本次按下、移动或释放的指针事件。
  void _pointerUp(
    PointerEvent event,
  ) {
    final pointer = _activePointers.remove(event.pointer);

    if (pointer != null) {
      _renderer.renderEnded(<TrajectoryID>[pointer.id]);
    }

    if (_activePointers.isEmpty) {
      _stopSampling();
    }
  }

  /// 按固定采样间隔提交所有活动触点。
  ///
  /// - [elapsed]：当前动画或采样周期内已过去的时间。
  void _sampleActivePointers(
    Duration elapsed,
  ) {
    _currentSamplingTime = elapsed;

    if (_activePointers.isEmpty) {
      _stopSampling();

      return;
    }

    final lastSampleTime = _lastSampleTime;

    if (lastSampleTime != null &&
        elapsed - lastSampleTime < _samplingInterval) {
      return;
    }

    final size = _samplingViewportSize;
    final listener = _samplingListener;

    if (size == null || listener == null) {
      return;
    }

    _submit(size, listener);
    _lastSampleTime = elapsed;
  }

  /// 保存本次触点采样所需的视图尺寸和提交函数。
  ///
  /// - [size]：当前视频视图的逻辑像素尺寸。
  /// - [listener]：接收本次通知的回调。
  void _updateSamplingContext(
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    _samplingViewportSize = size;
    _samplingListener = listener;
  }

  /// 停止采样时钟并清除采样上下文。
  void _stopSampling() {
    if (_samplingTicker.isActive) {
      _samplingTicker.stop();
    }

    _currentSamplingTime = Duration.zero;
    _lastSampleTime = null;
    _samplingViewportSize = null;
    _samplingListener = null;
  }

  /// 将当前触点转换为包含位置和时间的轨迹渲染输入。
  ///
  /// - [pointer]：当前按下的触点状态。
  /// - [size]：当前视频视图的逻辑像素尺寸。
  ///
  /// 返回用于本地轨迹渲染的位置和时间样本。
  TrajectoryPoint _point(
    _ActivePointer pointer,
    Size size,
  ) => TrajectoryPoint(
    id: pointer.id,
    location: pointer.location,
    normalizedLocation: Offset(
      size.width == 0 ? 0 : pointer.location.dx / size.width,
      size.height == 0 ? 0 : pointer.location.dy / size.height,
    ),
    timestamp: Duration(microseconds: DateTime.now().microsecondsSinceEpoch),
  );

  /// 将所有活动触点按当前视图配置提交给交互处理组件。
  ///
  /// - [size]：当前视频视图的逻辑像素尺寸。
  /// - [listener]：接收本次通知的回调。
  void _submit(
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    listener(
      InteractionFrame(
        points: _activePointers.values
            .map((pointer) => pointer.location)
            .toList(growable: false),
        viewportSize: size,
        contentMode: widget.videoContentMode,
      ),
    );
  }

  /// 清除活动触点、采样时钟和轨迹显示。
  void _resetPointers() {
    _activePointers.clear();
    _stopSampling();
    _renderer.reset();
  }

  /// 仅释放由当前视图创建的默认轨迹渲染器。
  void _disposeOwnedRenderer() {
    if (_ownsRenderer && _renderer is DefaultTrajectoryEffectRenderer) {
      (_renderer as DefaultTrajectoryEffectRenderer).dispose();
    }
  }
}

/// 当前按下触点的轨迹标识和最新视图位置。
final class _ActivePointer {

  /// 记录活动触点的轨迹标识与当前位置。
  _ActivePointer({
    required this.id,
    required this.location,
  });

  /// 当前按下触点对应的轨迹标识。
  final TrajectoryID id;

  /// 触点在视图内的逻辑像素坐标。
  Offset location;
}
