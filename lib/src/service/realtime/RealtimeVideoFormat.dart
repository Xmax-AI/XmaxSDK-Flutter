//
//  RealtimeVideoFormat.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';

/// The encoding preference for realtime video.
enum RealtimeVideoEncoderPreference {

  /// Balances frame rate and resolution.
  auto,

  /// Prioritizes frame rate.
  maintainFramerate,

  /// Prioritizes resolution.
  maintainQuality,
}

/// The dimensions, frame rate, and uplink encoding settings for realtime video.
///
/// Construction stores the settings; use [validate] to check them before use.
final class RealtimeVideoFormat {

  /// Creates a realtime video format.
  const RealtimeVideoFormat({
    required this.width,
    required this.height,
    required this.fps,
    this.minimumBitrate,
    this.maximumBitrate,
    this.encoderPreference = RealtimeVideoEncoderPreference.maintainFramerate,
  });

  /// The video width, in pixels; must be a positive even number.
  final int width;

  /// The video height, in pixels; must be a positive even number.
  final int height;

  /// The target frame rate, in fps; must be greater than zero.
  final int fps;

  /// The minimum uplink bitrate, in kbps; defaults to 500, capped at the maximum bitrate.
  /// Zero disables the minimum bitrate floor.
  final int? minimumBitrate;

  /// The maximum uplink bitrate, in kbps; null uses SDK defaults and explicit values must be
  /// positive.
  final int? maximumBitrate;

  /// The uplink encoding preference; defaults to frame-rate priority.
  final RealtimeVideoEncoderPreference encoderPreference;

  /// Validates dimensions, frame rate, and bitrates, throwing invalidConfiguration for invalid
  /// values.
  ///
  /// Dimensions must be positive and even, frame rate positive, and minimum bitrate no greater than
  /// maximum.
  void validate() {
    if (width <= 0 || height <= 0 || fps <= 0 || width.isOdd || height.isOdd) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Realtime video width and height must be positive even '
            'numbers, and fps must be greater than zero',
      );
    }

    final minimum = minimumBitrate;
    final maximum = maximumBitrate;

    if (minimum != null && minimum < 0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Minimum bitrate must not be negative',
      );
    }

    if (maximum != null && maximum <= 0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Maximum bitrate must be greater than zero',
      );
    }

    if (minimum != null && maximum != null && minimum > maximum) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Minimum bitrate must not exceed maximum bitrate',
      );
    }
  }

  /// Creates a resized format retaining frame rate, bitrates, and encoding preference.
  ///
  /// Parameters:
  /// - [width]: The video width, in pixels.
  /// - [height]: The video height, in pixels.
  ///
  /// Returns a separate format with updated dimensions without mutating or validating the original.
  RealtimeVideoFormat resized({
    required int width,
    required int height,
  }) => RealtimeVideoFormat(
    width: width,
    height: height,
    fps: fps,
    minimumBitrate: minimumBitrate,
    maximumBitrate: maximumBitrate,
    encoderPreference: encoderPreference,
  );

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeVideoFormat &&
          width == other.width &&
          height == other.height &&
          fps == other.fps &&
          minimumBitrate == other.minimumBitrate &&
          maximumBitrate == other.maximumBitrate &&
          encoderPreference == other.encoderPreference;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    width,
    height,
    fps,
    minimumBitrate,
    maximumBitrate,
    encoderPreference,
  );
}
