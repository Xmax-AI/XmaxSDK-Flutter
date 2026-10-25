//
//  VideoRenderBinding.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import '../../foundation/rtc/RemoteStream.dart';
import '../../foundation/rtc/LocalStream.dart';

/// An internal rendering binding for local preview or remote result video.
sealed class VideoRenderBinding {

  /// Creates a video rendering binding.
  const VideoRenderBinding();
}

/// The local media RTC engine, source type, and preview mount callback.
final class LocalVideoRenderBinding extends VideoRenderBinding {

  /// Creates a local preview binding.
  const LocalVideoRenderBinding({
    this.onPreviewAttached,
    this.engine,
    this.sourceType = VideoSourceType.videoSourceCamera,
  });

  /// Creates a custom-source preview binding without camera capture.
  const LocalVideoRenderBinding.external({
    this.onPreviewAttached,
    this.engine,
  }) : sourceType = VideoSourceType.videoSourceCustom;

  /// Creates a view binding for a local RTC input.
  ///
  /// Parameters:
  /// - [stream]: The input metadata resolved by the RTC platform.
  /// - [onPreviewAttached]: The callback after the preview view mounts.
  LocalVideoRenderBinding.fromStream(
    LocalStream stream, {
    this.onPreviewAttached,
  }) : engine = stream.engine,
       sourceType = stream.isExternal
           ? VideoSourceType.videoSourceCustom
           : VideoSourceType.videoSourceCamera;

  /// The RTC engine for local preview; without an engine, rendering displays a black background.
  final RtcEngine? engine;

  /// The native input rendered by this preview, independent of channel publication.
  final VideoSourceType sourceType;

  /// The callback invoked after the native preview view mounts.
  final void Function()? onPreviewAttached;
}

/// A remote stream and its first-frame rendering state.
final class RemoteVideoRenderBinding extends VideoRenderBinding {

  /// Creates a remote result-stream binding.
  const RemoteVideoRenderBinding(
    this.stream, {
    this.firstFrameRendered = false,
    this.onFirstFrameRendered,
  });

  /// The currently bound remote result stream.
  final RemoteStream stream;

  /// Whether the remote stream has rendered its first frame; initially false.
  final bool firstFrameRendered;

  /// Reports the first submitted Flutter texture frame for this exact binding.
  final VoidCallback? onFirstFrameRendered;
}
