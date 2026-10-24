//
//  VideoEncodingConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';

/// The dimensions, frame rate, bitrate, and degradation preference submitted to RTC encoding.
final class VideoEncodingConfiguration {

  /// Creates a video encoder configuration.
  const VideoEncodingConfiguration({
    required this.width,
    required this.height,
    required this.frameRate,
    this.minimumBitrate = 0,
    this.maximumBitrate = -1,
    this.encoderPreference = RealtimeVideoEncoderPreference.maintainFramerate,
  });

  /// The encoded width, in pixels.
  final int width;

  /// The encoded height, in pixels.
  final int height;

  /// The video frame rate, in fps.
  final int frameRate;

  /// The minimum encoding bitrate, in kbps; 0 uses RTC's minimum bitrate policy.
  final int minimumBitrate;

  /// The encoding target bitrate, in kbps; -1 uses RTC's compatibility bitrate mode.
  final int maximumBitrate;

  /// The bandwidth degradation preference; defaults to frame-rate priority.
  final RealtimeVideoEncoderPreference encoderPreference;
}
