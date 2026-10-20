//
//  XmaxRealtimeVideoView.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../foundation/media/video/VideoContentMode.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../trajectory/TrajectoryEffectRendering.dart';
import 'VideoRenderBinding.dart';
import 'VideoRenderRegistry.dart';
import 'XmaxVideoView.dart';

/// 推荐用于实时生成的视频视图，自动切换本地预览和远端画面。
///
/// 本地预览始终保留在底层。[remoteTrack] 对应的远端流完成首帧渲染后，
/// 在本地预览上方显示生成画面。远端流停止或解除绑定后，自动恢复本地预览。
/// 停止生成时，先隐藏远端画面，再释放视频资源，避免切换时闪黑。
///
/// 需要画中画或其他自定义布局时，可组合多个 [XmaxVideoView]。
final class XmaxRealtimeVideoView extends StatefulWidget {

  /// 创建自动切换本地预览与生成画面的视频视图。
  const XmaxRealtimeVideoView({
    super.key,
    this.localTrack,
    this.remoteTrack,
    this.videoContentMode = VideoContentMode.fill,
    this.isInteractionEnabled = true,
    this.trajectoryRenderer,
    this.onRemoteVideoReady,
  });

  /// 本地摄像头轨道，作为远端生成画面出现前和停止后的默认预览。
  final RealtimeVideoTrack? localTrack;

  /// 远端生成轨道。SDK 在匹配远端流并确认首帧已渲染后自动显示。
  final RealtimeVideoTrack? remoteTrack;

  /// 本地和远端视频共同使用的缩放模式，默认等比填满并裁剪超出部分。
  final VideoContentMode videoContentMode;

  /// 是否允许在可见的远端生成画面上提交交互轨迹，默认启用。
  final bool isInteractionEnabled;

  /// 远端交互轨迹渲染器；未指定时使用 SDK 默认效果。
  ///
  /// 由接入方提供时，接入方负责渲染器生命周期；默认渲染器由视图释放。
  final TrajectoryEffectRendering? trajectoryRenderer;

  /// 远端首帧渲染完成、视图开始显示生成画面时的回调，可用于收起加载遮罩。
  ///
  /// 每次绑定远端流时只触发一次；更新生成条件不会再次触发。
  /// 回调在当前帧绘制结束后执行，可以安全更新界面，但此时淡入动画不一定已结束。
  /// 停止生成、解除绑定或替换轨道后，不再触发尚未执行的旧回调。
  final VoidCallback? onRemoteVideoReady;

  /// 创建管理预览切换与远端就绪通知的组件状态。
  @override
  State<XmaxRealtimeVideoView> createState() => _XmaxRealtimeVideoViewState();
}

/// 维护本地预览与远端结果的显示切换和就绪通知。
final class _XmaxRealtimeVideoViewState extends State<XmaxRealtimeVideoView> {

  // Flutter 会将透明度量化为 8 位数值。
  // 0.001 等过小的值会被舍入为零，导致 RTC 视图不参与绘制。

  /// 首帧尚未就绪时远端层的透明度。
  static const _pendingRemoteOpacity = 1 / 255;

  /// 当前远端轨道的可监听渲染句柄。
  VideoRenderHandle? _remoteHandle;

  /// 当前是否可以显示远端画面。
  bool _isRemoteVisible = false;

  /// 远端资源移除期间是否强制隐藏结果画面。
  bool _isRemoteSuppressed = false;

  /// 等待远端画面隐藏完成的任务。
  Future<void>? _concealment;

  /// 当前结果流的唯一标识，用于区分不同流的绑定。
  (String, String, String)? _remoteIdentity;

  /// 本次远端流绑定的版本号，用于取消旧的就绪回调。
  int _readyVersion = 0;

  /// 本次远端流绑定后是否已触发画面就绪回调。
  bool _didNotifyReady = false;

  /// 初始化视图监听、触点采样和本地绘制资源。
  @override
  void initState() {
    super.initState();
    _attachRemoteTrack();
  }

  /// 根据新的组件配置更新轨道绑定、交互和渲染器所有权。
  ///
  /// - [oldWidget]：更新前的组件配置。
  @override
  void didUpdateWidget(
    covariant XmaxRealtimeVideoView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.remoteTrack != widget.remoteTrack) {
      _detachRemoteTrack();
      _isRemoteVisible = false;
      _isRemoteSuppressed = false;
      _attachRemoteTrack();
    } else if (oldWidget.onRemoteVideoReady != widget.onRemoteVideoReady) {
      _scheduleRemoteVideoReady();
    }
  }

  /// 释放组件拥有的监听、动画和绘制资源。
  @override
  void dispose() {
    _detachRemoteTrack();
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
  ) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      XmaxVideoView(
        track: widget.localTrack,
        videoContentMode: widget.videoContentMode,
        isInteractionEnabled: false,
      ),
      if (widget.remoteTrack != null)
        IgnorePointer(
          ignoring: !_isRemoteVisible,
          child: TweenAnimationBuilder<double>(
            // 等待原生首帧回调时保持极低但非零的透明度，首帧就绪后在本地预览上方淡入。
            tween: Tween<double>(end: _remoteOpacity),
            duration: _isRemoteVisible
                ? const Duration(milliseconds: 300)
                : Duration.zero,
            curve: Curves.easeInOut,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: XmaxVideoView(
              track: widget.remoteTrack,
              videoContentMode: widget.videoContentMode,
              isInteractionEnabled:
                  _isRemoteVisible && widget.isInteractionEnabled,
              trajectoryRenderer: widget.trajectoryRenderer,
            ),
          ),
        ),
    ],
  );

  /// 监听当前远端轨道的渲染绑定和移除通知。
  void _attachRemoteTrack() {
    final track = widget.remoteTrack;

    if (track == null) {
      return;
    }

    final handle = VideoRenderRegistry.handleFor(track);

    _remoteHandle = handle;
    handle?.addListener(_remoteBindingDidChange);
    handle?.addRemovalListener(_prepareForRemoteRemoval);
    _isRemoteVisible = _hasRemoteBinding;
    _updateRemoteReadiness();
  }

  /// 解除远端轨道监听并使已安排的就绪通知失效。
  void _detachRemoteTrack() {
    _remoteHandle?.removeListener(_remoteBindingDidChange);
    _remoteHandle?.removeRemovalListener(_prepareForRemoteRemoval);
    _remoteHandle = null;
    _concealment = null;
    _remoteIdentity = null;
    _invalidateRemoteReadiness();
  }

  /// 依据最新远端流绑定更新画面可见性。
  void _remoteBindingDidChange() {
    if (_remoteHandle?.value == null) _isRemoteSuppressed = false;

    final isVisible = _hasRemoteBinding;

    if (mounted) {
      setState(() => _isRemoteVisible = isVisible);
    }

    _updateRemoteReadiness();
  }

  /// 取消本次绑定中尚未触发的画面就绪回调。
  void _invalidateRemoteReadiness() {
    _readyVersion += 1;
    _didNotifyReady = false;
  }

  /// 按远端绑定及首帧状态更新是否可以显示结果画面。
  void _updateRemoteReadiness() {
    final binding = _remoteHandle?.value;
    final stream = binding is RemoteVideoRenderBinding ? binding.stream : null;
    final identity = stream == null
        ? null
        : (stream.roomID, stream.userID, stream.streamID);

    if (identity != _remoteIdentity || !_hasRemoteBinding) {
      _invalidateRemoteReadiness();
      _remoteIdentity = identity;
    }

    _scheduleRemoteVideoReady();
  }

  /// 在当前帧绘制结束后触发画面就绪回调；绑定已失效时不再触发。
  void _scheduleRemoteVideoReady() {
    if (!_hasRemoteBinding ||
        _didNotifyReady ||
        widget.onRemoteVideoReady == null) {
      return;
    }

    final version = _readyVersion;
    // 构建组件时可能已有缓存首帧，因此等可见性更新完成后再触发就绪回调，
    // 保证接入方可以在回调中安全调用 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          version != _readyVersion ||
          !_hasRemoteBinding ||
          _didNotifyReady) {
        return;
      }

      final callback = widget.onRemoteVideoReady;

      if (callback == null) return;

      _didNotifyReady = true;
      callback();
    });
  }

  /// 当前远端视频层实际使用的不透明度。
  double get _remoteOpacity {
    if (_isRemoteSuppressed || _remoteHandle?.value == null) return 0;

    return _isRemoteVisible ? 1 : _pendingRemoteOpacity;
  }

  /// 先隐藏远端画面并等待帧提交，再允许原生视频资源释放。
  Future<void> _prepareForRemoteRemoval() {
    final active = _concealment;

    if (active != null) return active;

    if (!mounted || _isRemoteSuppressed || _remoteHandle?.value == null) {
      return Future<void>.value();
    }

    // 先保留视频渲染资源，等待隐藏画面的一帧提交后再清理绑定，
    // 避免图层仍可见时露出黑色画布。
    setState(() {
      _isRemoteSuppressed = true;
      _isRemoteVisible = false;
    });
    _invalidateRemoteReadiness();

    final binding = WidgetsBinding.instance;
    final lifecycle = binding.lifecycleState;

    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return Future<void>.value();
    }

    final future = binding.endOfFrame.timeout(
      const Duration(milliseconds: 100),
      onTimeout: () {},
    );

    _concealment = future;

    return future.whenComplete(() {
      if (identical(_concealment, future)) _concealment = null;
    });
  }

  /// 当前远端轨道是否存在可用的结果流绑定。
  bool get _hasRemoteBinding {
    final binding = _remoteHandle?.value;

    return !_isRemoteSuppressed &&
        binding is RemoteVideoRenderBinding &&
        binding.firstFrameRendered;
  }
}
