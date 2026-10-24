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
import 'VideoTextureFrameObserver.dart';

/// Retains the native texture mount point while the parent view manages binding and visibility
/// separately.
final class VideoRenderSurface extends StatelessWidget {

  /// Creates a native video rendering component.
  const VideoRenderSurface({
    super.key,
    required this.binding,
    required this.track,
    required this.contentMode,
  });

  /// The local preview or remote stream rendering configuration.
  final VideoRenderBinding binding;

  /// The target video track.
  final RealtimeVideoTrack? track;

  /// The video scaling and cropping mode.
  final VideoContentMode contentMode;

  /// Builds the native video surface for the current track binding and display configuration.
  ///
  /// Parameters:
  /// - [context]: The widget build context.
  ///
  /// Returns the video texture, or a black background when the binding cannot be rendered.
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

    if (engine == null ||
        (remote != null && (remote.uid == null || remote.localUid == null))) {
      return const ColoredBox(color: Colors.black);
    }

    // Use Flutter textures to preserve opacity and stacked video compositing.
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
          connection: RtcConnection(
            channelId: remote.roomID,
            localUid: remote.localUid,
          ),
          useFlutterTexture: true,
        );

    final view = AgoraVideoView(
      controller: controller,
      onAgoraVideoViewCreated: (
        _,
      ) => local?.onPreviewAttached?.call(),
    );

    if (binding case RemoteVideoRenderBinding remoteBinding) {
      // Agora's texture renderer inserts a Texture only after receiving a nonempty frame.
      // Native renderer callbacks do not cover this custom-rendering path.
      return VideoTextureFrameObserver(
        binding: remoteBinding.stream,
        onFirstFrameRendered: remoteBinding.onFirstFrameRendered,
        child: view,
      );
    }

    return view;
  }
}
