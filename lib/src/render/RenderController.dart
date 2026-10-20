//
//  RenderController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../foundation/errors/XmaxError.dart';
import '../foundation/rtc/RtcModels.dart';
import '../media/interaction/InteractionFrame.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import 'RenderControlling.dart';
import 'trajectory/TrajectoryBinding.dart';
import 'trajectory/TrajectoryRegistry.dart';
import 'video/VideoRenderBinding.dart';
import 'video/VideoRenderRegistry.dart';

/// 管理远端轨道绑定、首帧就绪等待和移除前的视频隐藏。
final class RenderController implements RenderControlling {

  /// 创建远端视频渲染控制器。
  RenderController({
    this.remoteFrameReadyTimeout = const Duration(seconds: 10),
  });

  /// 等待远端首帧解码就绪的最长时限，默认 10 秒。
  final Duration remoteFrameReadyTimeout;

  /// 当前远端生成结果的视频轨道。
  RealtimeVideoTrack? _remoteTrack;

  /// 当前生成结果的远端媒体流。
  RemoteStream? _remoteStream;

  /// 当前结果流是否已解码有效首帧。
  bool _remoteFrameReady = false;

  /// 等待当前结果流完成首帧解码的完成器集合。
  final Set<Completer<void>> _frameWaiters = {};

  /// 等待已挂载视图隐藏远端视频，再释放对应渲染资源。
  @override
  Future<void> prepareForRemoteRemoval() async {
    final track = _remoteTrack;

    if (track != null) {
      await VideoRenderRegistry.handleFor(track)?.prepareForRemoval();
    }
  }

  /// 为远端轨道注册渲染句柄和交互采样入口。
  ///
  /// 详细说明见 [RenderControlling.registerRemoteTrack]。
  @override
  void registerRemoteTrack(
    RealtimeVideoTrack track, {
    required void Function(
      InteractionFrame frame,
    )
    interactionListener,
  }) {
    _resetFrameReadiness();
    _remoteTrack = track;
    VideoRenderRegistry.register(track, null);
    TrajectoryRegistry.register(
      track,
      TrajectoryBinding(interactionListener: interactionListener),
    );
  }

  /// 更新当前轨道的结果流绑定。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  @override
  void setRemoteStream(
    RemoteStream? stream,
  ) {
    _resetFrameReadiness();
    _remoteStream = stream;

    final track = _remoteTrack;

    if (track != null) {
      VideoRenderRegistry.register(
        track,
        stream == null ? null : RemoteVideoRenderBinding(stream),
      );
    }
  }

  /// 记录结果流已完成首帧解码，不要求视图已经挂载。
  ///
  /// - [stream]：完成首帧解码的远端流。
  void markRemoteFrameReady(
    RemoteStream stream,
  ) {
    final active = _remoteStream;

    if (_remoteTrack == null ||
        active == null ||
        active.roomID != stream.roomID ||
        active.userID != stream.userID ||
        active.streamID != stream.streamID) {
      return;
    }

    _remoteFrameReady = true;
    for (final waiter in _frameWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }

    _frameWaiters.clear();
  }

  /// 等待当前结果流首帧解码就绪，不要求预先挂载远端视图。
  @override
  Future<void> waitUntilRemoteFrameReady() async {
    if (_remoteTrack == null || _remoteStream == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Remote video stream is unavailable',
      );
    }

    if (_remoteFrameReady) return;

    final waiter = Completer<void>();

    _frameWaiters.add(waiter);

    try {
      await waiter.future.timeout(
        remoteFrameReadyTimeout,
        onTimeout: () {
          throw const XmaxError(
            code: XmaxErrorCode.timeout,
            message: 'Remote video first frame timed out',
          );
        },
      );
    } finally {
      _frameWaiters.remove(waiter);
    }
  }

  /// 结束旧结果流的就绪等待并清除首帧标记。
  void _resetFrameReadiness() {
    _remoteStream = null;
    _remoteFrameReady = false;
    for (final waiter in _frameWaiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(
          const XmaxError(
            code: XmaxErrorCode.cancelled,
            message: 'Remote frame wait cancelled',
          ),
        );
      }
    }

    _frameWaiters.clear();
  }

  /// 记录当前结果流已渲染首帧，以便视图开始显示远端画面。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  void markRemoteFrameRendered(
    RemoteStream stream,
  ) {
    final track = _remoteTrack;

    if (track == null) return;

    final handle = VideoRenderRegistry.handleFor(track);
    final binding = handle?.value;

    if (binding is! RemoteVideoRenderBinding ||
        binding.firstFrameRendered ||
        binding.stream.roomID != stream.roomID ||
        binding.stream.userID != stream.userID ||
        binding.stream.streamID != stream.streamID) {
      return;
    }

    VideoRenderRegistry.register(
      track,
      RemoteVideoRenderBinding(stream, firstFrameRendered: true),
    );
  }

  /// 解除远端轨道的渲染、交互和首帧等待。
  ///
  /// - [track]：目标视频轨道。
  @override
  void resetRemoteTrack(
    RealtimeVideoTrack? track,
  ) {
    _resetFrameReadiness();

    final target = track ?? _remoteTrack;

    if (target != null) {
      VideoRenderRegistry.unregister(target);
      TrajectoryRegistry.unregister(target);
    }

    _remoteTrack = null;
  }
}
