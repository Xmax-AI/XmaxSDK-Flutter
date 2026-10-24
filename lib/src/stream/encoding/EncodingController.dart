//
//  EncodingController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;

import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/VideoEncodingConfiguration.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'EncodingBitratePolicy.dart';
import 'EncodingControlling.dart';

/// Applies RTC encoding settings for a realtime video format.
final class EncodingController implements EncodingControlling {

  /// Creates a video encoding controller.
  const EncodingController({
    required RtcManaging rtcManager,
  }) : _rtcManager = rtcManager;

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// Resolves the format's bitrate budget and applies RTC encoding settings.
  /// An unspecified minimum defaults to 500 kbps, capped at the format's maximum bitrate.
  ///
  /// Parameters:
  /// - [format]: The target video dimensions, frame rate, and encoding settings.
  @override
  Future<void> configure(
    RealtimeVideoFormat format,
  ) async {
    final budget = EncodingBitratePolicy.resolve(format);

    await _rtcManager.configureVideoEncoding(
      VideoEncodingConfiguration(
        width: format.width,
        height: format.height,
        frameRate: format.fps,
        minimumBitrate: format.minimumBitrate ?? math.min(500, budget.$2),
        maximumBitrate: budget.$2,
        encoderPreference: format.encoderPreference,
      ),
    );
  }
}
