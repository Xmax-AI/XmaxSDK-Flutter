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

import '../../service/realtime/RealtimeVideoFormat.dart';
import 'RealtimeQualityLevel.dart';

/// Resolves transport levels from a fixed baseline without changing capture or generation formats.
abstract final class QualityVideoFormat {

  /// Video dimension scale factors indexed by quality level.
  static const scales = [1.0, 0.9, 0.75, 0.6, 0.5];

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
  /// - [minimumInputPixels]: The minimum uplink area, capped at the baseline area;
  ///   ignored for downlink.
  ///
  /// Returns a validated video format with dimensions, frame rate, and encoding settings.
  static RealtimeVideoFormat resolve(
    RealtimeVideoFormat baseline,
    RealtimeQualityLevel level, {
    required bool downlink,
    int minimumInputPixels = 0,
  }) {
    final s = scale(
      baseline,
      level,
    ),
        divisor = baseline.width.gcd(baseline.height);
    final alignment = downlink ? 2 : 4;
    final pixels = baseline.width * baseline.height;
    final minimumScale = math.sqrt(
      math.min(math.max(0, downlink ? 0 : minimumInputPixels), pixels) / pixels,
    );
    final minimumUnits = (divisor * minimumScale / alignment).ceil() * alignment;
    final units = ((divisor * s + 0.0000001).floor() ~/ alignment) * alignment;
    final resolvedUnits = math.max(units, minimumUnits);
    final exact = units >= alignment && resolvedUnits <= divisor;
    final width = exact
        ? baseline.width ~/ divisor * resolvedUnits
        : math.max(
            alignment,
            math.max(
              (baseline.width * s / alignment).floor() * alignment,
              (baseline.width * minimumScale / alignment).ceil() * alignment,
            ),
          );
    final height = exact
        ? baseline.height ~/ divisor * resolvedUnits
        : math.max(
            alignment,
            math.max(
              (baseline.height * s / alignment).floor() * alignment,
              (baseline.height * minimumScale / alignment).ceil() * alignment,
            ),
          );

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
