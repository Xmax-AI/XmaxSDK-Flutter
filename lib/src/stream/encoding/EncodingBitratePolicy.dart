//
//  EncodingBitratePolicy.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;

import '../../foundation/errors/XmaxError.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// Calculates encoding budgets in kbps for use by uplink and downlink transport.
abstract final class EncodingBitratePolicy {

  /// Validates the video format and resolves bitrate bounds, preferring explicit settings over
  /// default curves.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  ///
  /// Returns minimum and maximum bitrates, in kbps.
  static (int, int) resolve(
    RealtimeVideoFormat videoFormat,
  ) {
    videoFormat.validate();

    final int minimum;
    final int maximum;
    final explicitMinimum = videoFormat.minimumBitrate;
    final explicitMaximum = videoFormat.maximumBitrate;

    if (explicitMinimum != null && explicitMaximum != null) {
      minimum = explicitMinimum;
      maximum = explicitMaximum;
    } else {
      final defaults = _defaultBitrates(videoFormat);

      minimum = explicitMinimum ?? defaults.$1;
      maximum = explicitMaximum ?? defaults.$2;
    }

    if (minimum > maximum) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Minimum bitrate must not exceed maximum bitrate after applying '
            'SDK defaults',
      );
    }

    return (minimum, maximum);
  }

  /// Calculates the default minimum and maximum bitrates for a video format.
  ///
  /// Parameters:
  /// - [format]: The target video dimensions, frame rate, and encoding settings.
  ///
  /// Returns minimum and maximum bitrates, in kbps.
  static (int, int) _defaultBitrates(
    RealtimeVideoFormat format,
  ) {
    final bitrates = _resolveBitrates(
      pixels: format.width.toDouble() * format.height.toDouble(),
      fps: format.fps.toDouble(),
    );
    final value = bitrates.$2 * 0.6;
    final floor = value.floorToDouble();
    final roundedMaximum = value - floor == 0.5 && floor % 2 == 0
        ? floor
        : value.roundToDouble();

    // Reject bitrates outside the native signed integer range.
    if (!roundedMaximum.isFinite || roundedMaximum >= 9223372036854775808.0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Realtime video format exceeds the supported bitrate range',
      );
    }

    return (100, math.max(100, roundedMaximum.toInt()));
  }

  // Interpolate by pixel count; extrapolate outside the table using the nearest endpoint ratio.

  /// The pixel-count and reference-bitrate samples for 15 fps.
  static const _referenceBitratesAt15FPS = <_BitratePoint>[
    _BitratePoint(
      120 * 120,
      50,
    ),
    _BitratePoint(
      160 * 120,
      65,
    ),
    _BitratePoint(
      180 * 180,
      100,
    ),
    _BitratePoint(
      240 * 180,
      120,
    ),
    _BitratePoint(
      320 * 180,
      140,
    ),
    _BitratePoint(
      320 * 240,
      200,
    ),
    _BitratePoint(
      424 * 240,
      220,
    ),
    _BitratePoint(
      360 * 360,
      260,
    ),
    _BitratePoint(
      480 * 360,
      320,
    ),
    _BitratePoint(
      640 * 360,
      400,
    ),
    _BitratePoint(
      640 * 480,
      500,
    ),
    _BitratePoint(
      848 * 480,
      610,
    ),
    _BitratePoint(
      960 * 720,
      910,
    ),
    _BitratePoint(
      1280 * 720,
      1130,
    ),
    _BitratePoint(
      1920 * 1080,
      2080,
    ),
  ];

  /// The pixel-count and reference-bitrate samples for 30 fps.
  static const _referenceBitratesAt30FPS = <_BitratePoint>[
    _BitratePoint(
      360 * 360,
      400,
    ),
    _BitratePoint(
      480 * 360,
      490,
    ),
    _BitratePoint(
      640 * 360,
      600,
    ),
    _BitratePoint(
      640 * 480,
      750,
    ),
    _BitratePoint(
      848 * 480,
      930,
    ),
    _BitratePoint(
      960 * 720,
      1380,
    ),
    _BitratePoint(
      1280 * 720,
      1710,
    ),
    _BitratePoint(
      1920 * 1080,
      3150,
    ),
  ];

  /// Interpolates reference bitrate bounds by pixel count and frame rate.
  ///
  /// Parameters:
  /// - [pixels]: The total pixel count, calculated as width times height.
  /// - [fps]: The video frame rate, in fps.
  ///
  /// Returns reference minimum and maximum bitrates, in kbps.
  static (double, double) _resolveBitrates({
    required double pixels,
    required double fps,
  }) {
    final bitrate15 = _interpolate(
      pixels,
      _referenceBitratesAt15FPS,
    );
    final first30 = _referenceBitratesAt30FPS.first;
    final bitrate30 = pixels < first30.value
        ? bitrate15 *
              (first30.bitrate /
                  _interpolate(
                    first30.value,
                    _referenceBitratesAt15FPS,
                  ))
        : _interpolate(
          pixels,
          _referenceBitratesAt30FPS,
        );

    // Use the 15 fps size curve for 10 fps and the 30 fps size curve for 60 fps.
    final bitrate10 = bitrate15 * (400.0 / 500);
    final minimum60 = bitrate30 * (4780.0 / 3150);
    final maximum60 = bitrate30 * (6500.0 / 3150);

    return (
      _interpolate(
        fps,
        <_BitratePoint>[
        _BitratePoint(
          10,
          bitrate10,
        ),
        _BitratePoint(
          15,
          bitrate15,
        ),
        _BitratePoint(
          30,
          bitrate30,
        ),
        _BitratePoint(
          60,
          minimum60,
        ),
      ],
      ),
      _interpolate(
        fps,
        <_BitratePoint>[
        _BitratePoint(
          10,
          bitrate10 * 2,
        ),
        _BitratePoint(
          15,
          bitrate15 * 2,
        ),
        _BitratePoint(
          30,
          bitrate30 * 2,
        ),
        _BitratePoint(
          60,
          maximum60,
        ),
      ],
      ),
    );
  }

  /// Linearly interpolates adjacent reference samples or extrapolates beyond the curve boundaries.
  ///
  /// Parameters:
  /// - [value]: The pixel count for which to resolve a reference bitrate.
  /// - [points]: Reference bitrate samples sorted by ascending pixel count.
  static double _interpolate(
    double value,
    List<_BitratePoint> points,
  ) {
    final first = points.first;

    if (value <= first.value) {
      return first.bitrate * (value / first.value);
    }

    for (var index = 1; index < points.length; index++) {
      final upper = points[index];

      if (value <= upper.value) {
        final lower = points[index - 1];
        final ratio = (value - lower.value) / (upper.value - lower.value);

        return lower.bitrate + (upper.bitrate - lower.bitrate) * ratio;
      }
    }

    final last = points.last;

    return last.bitrate * (value / last.value);
  }
}

/// A pixel-count and bitrate sample on a reference curve.
final class _BitratePoint {

  /// Creates a bitrate curve sample.
  const _BitratePoint(
    this.value,
    this.bitrate,
  );

  /// The total pixel count at this reference sample.
  final double value;

  /// The reference bitrate, in kbps.
  final double bitrate;
}
