//
//  VideoRenderSurface.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../foundation/media/camera/CameraPosition.dart';
import '../../foundation/media/video/VideoContentMode.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import 'VideoRenderBinding.dart';

/// 保存原生纹理挂载位置，绑定和画面可见性由上层视图独立管理。
final class VideoRenderSurface extends StatelessWidget {

  /// 创建原生视频渲染组件。
  const VideoRenderSurface({
    super.key,
    required this.binding,
    required this.track,
    required this.contentMode,
  });

  /// 当前轨道的渲染或交互配置。
  final VideoRenderBinding binding;

  /// 目标视频轨道。
  final RealtimeVideoTrack? track;

  /// 视频的缩放和裁剪方式。
  final VideoContentMode contentMode;

  /// 根据当前绑定和显示配置构建视频或轨迹视图。
  ///
  /// - [context]：组件构建上下文。
  ///
  /// 返回当前视频或轨迹效果的组件树。
  @override
  Widget build(
    BuildContext context,
  ) {
    final local = binding is LocalVideoRenderBinding
        ? binding as LocalVideoRenderBinding
        : null;
    final remote = binding is RemoteVideoRenderBinding
        ? (binding as RemoteVideoRenderBinding).stream
        : null;
    final engine = local?.engine ?? remote?.engine;

    if (engine == null || (remote != null && remote.uid == null)) {
      return const ColoredBox(color: Colors.black);
    }
    // 使用 Flutter 纹理，保留透明度和多层视频的叠加效果。
    final canvas = VideoCanvas(
      uid: remote?.uid ?? 0,
      renderMode: contentMode == VideoContentMode.fit
          ? RenderModeType.renderModeFit
          : RenderModeType.renderModeHidden,
      mirrorMode: local != null && track?.position == CameraPosition.front
          ? VideoMirrorModeType.videoMirrorModeEnabled
          : VideoMirrorModeType.videoMirrorModeDisabled,
    );
    final controller = remote == null
        ? VideoViewController(
            rtcEngine: engine,
            canvas: canvas,
            useFlutterTexture: true,
          )
        : VideoViewController.remote(
            rtcEngine: engine,
            canvas: canvas,
            connection: RtcConnection(channelId: remote.roomID),
            useFlutterTexture: true,
          );

    return AgoraVideoView(
      controller: controller,
      onAgoraVideoViewCreated: (_) => local?.onPreviewAttached?.call(),
    );
  }
}
