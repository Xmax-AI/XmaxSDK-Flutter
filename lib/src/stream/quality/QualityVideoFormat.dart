//
//  QualityVideoFormat.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;
import 'dart:ui';
import '../../core/realtime/RealtimeQualityLevel.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// Resolves transport levels from a fixed baseline without changing capture or generation formats.
abstract final class QualityVideoFormat {

  /// Video dimension scale factors indexed by quality level.
  static const scales = [1.0, 0.8, 0.65, 0.5, 0.5];

  /// Target uplink frame rates indexed by quality level, in fps.
  static const frameRates = [30, 24, 24, 20, 16];

  /// Resolves the target level's scale factor while enforcing the minimum short-edge constraint.
  ///
  /// Parameters:
  /// - [baseline]: The media dimensions, frame rate, and encoding settings unaffected by quality
  ///   updates.
  /// - [level]: The quality level to resolve, constrained to 1 through 5.
  static double scale(
    RealtimeVideoFormat baseline,
    RealtimeQualityLevel level,
  ) => math.max(
    scales[level.index],
    math.min(math.min(baseline.width, baseline.height), 240) /
        math.min(baseline.width, baseline.height),
  );

  /// Computes maximum result dimensions from the baseline and quality level.
  ///
  /// Parameters:
  /// - [baseline]: The media dimensions, frame rate, and encoding settings unaffected by quality
  ///   updates.
  /// - [level]: The quality level to resolve, constrained to 1 through 5.
  ///
  /// Returns maximum result dimensions for the level, before pixel alignment.
  static Size downlinkMaximumSize(
    RealtimeVideoFormat baseline,
    RealtimeQualityLevel level,
  ) => Size(
    baseline.width * scale(
      baseline,
      level,
    ),
    baseline.height * scale(
      baseline,
      level,
    ),
  );

  /// Resolves a transport format for the direction and level without changing the capture baseline.
  ///
  /// Parameters:
  /// - [baseline]: The media dimensions, frame rate, and encoding settings unaffected by quality
  ///   updates.
  /// - [level]: The quality level to resolve, constrained to 1 through 5.
  /// - [downlink]: Whether to resolve downlink settings; the downlink budget uses a fixed 24 fps.
  ///
  /// Returns a validated video format with dimensions, frame rate, and encoding settings.
  static RealtimeVideoFormat resolve(
    RealtimeVideoFormat baseline,
    RealtimeQualityLevel level, {
    required bool downlink,
  }) {
    final s = scale(
      baseline,
      level,
    ),
        divisor = baseline.width.gcd(baseline.height);
    final units = ((divisor * s + 0.0000001).floor() ~/ 2) * 2;
    final width = units >= 2
        ? baseline.width ~/ divisor * units
        : math.max(2, (baseline.width * s / 2).floor() * 2);
    final height = units >= 2
        ? baseline.height ~/ divisor * units
        : math.max(2, (baseline.height * s / 2).floor() * 2);

    return RealtimeVideoFormat(
      width: width,
      height: height,
      fps: downlink
          ? 24
          : math.min(baseline.fps, frameRates[level.index]),
      minimumBitrate: downlink ? null : baseline.minimumBitrate,
      maximumBitrate: downlink ? null : baseline.maximumBitrate,
      encoderPreference: baseline.encoderPreference,
    );
  }
}
