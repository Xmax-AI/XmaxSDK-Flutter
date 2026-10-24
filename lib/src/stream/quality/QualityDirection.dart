//
//  QualityDirection.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../encoding/EncodingBitratePolicy.dart';
import 'QualityVideoFormat.dart';
import 'RealtimeQualityLevel.dart';

/// The sampling, level adjustment, and recovery cooldown policy for one transport direction.
final class QualityDirection {

  /// Creates a directional quality policy with the initial level constrained to the supported
  /// range.
  ///
  /// Parameters:
  /// - [baseline]: The media format that remains fixed across network quality adjustments.
  /// - [level]: The initial level; raises the format until the bitrate budget is valid or L1 is
  ///   reached.
  /// - [downlink]: Whether to apply the downlink policy; false means uplink.
  QualityDirection({
    required this.baseline,
    required this.level,
    required this.downlink,
  }) {
    while (level != RealtimeQualityLevel.l1 && !_supports(level)) {
      level = RealtimeQualityLevel.values[level.index - 1];
    }
  }

  /// The media dimensions, frame rate, and encoding settings unaffected by quality updates.
  final RealtimeVideoFormat baseline;

  /// Whether to resolve a downlink format; false resolves uplink encoding.
  final bool downlink;

  /// The target quality level, from 1 to 5.
  RealtimeQualityLevel level;

  /// The number of consecutive good network samples.
  int _good = 0;

  /// The number of consecutive poor network samples.
  int _poor = 0;

  /// The monotonic time of the last valid network sample, in seconds.
  double? _lastSample;

  /// The stability window's end, in monotonic seconds; adjustments are suspended until then.
  double _stableUntil = 0;

  /// The earliest permitted quality upgrade time, in monotonic seconds.
  double _upgradeAfter = 0;

  /// The upgrade observation deadline, in monotonic seconds.
  double _probeUntil = 0;

  /// The target video dimensions, frame rate, and encoding settings.
  RealtimeVideoFormat get format =>
      QualityVideoFormat.resolve(
        baseline,
        level,
        downlink: downlink,
      );

  /// Clears sample counters and the last sample time, retaining the level and cooldown windows.
  void resetSamples() {
    _good = 0;
    _poor = 0;
    _lastSample = null;
  }

  /// Checks whether the target level has a valid encoding budget for this direction.
  ///
  /// Parameters:
  /// - [level]: The target quality level to validate.
  ///
  /// Returns whether the target level resolves to a valid transport format.
  bool _supports(
    RealtimeQualityLevel level,
  ) {
    if (downlink) {
      return true;
    }

    try {
      EncodingBitratePolicy.resolve(
        QualityVideoFormat.resolve(
          baseline,
          level,
          downlink: false,
        ),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Proposes a level using consecutive valid samples and stability, probing, and recovery windows.
  ///
  /// Parameters:
  /// - [quality]: The network quality of this transport direction.
  /// - [sampledAt]: The network sample's monotonic timestamp, in seconds.
  /// - [now]: The monotonic time, in seconds.
  ///
  /// Returns a candidate level, or null for invalid samples, cooldown, or no required adjustment.
  RealtimeQualityLevel? observe(
    RealtimeNetworkQualityLevel quality, {
    required double sampledAt,
    required double now,
  }) {
    if (sampledAt > now || (_lastSample != null && sampledAt <= _lastSample!)) {
      return null;
    }

    if (_lastSample != null && sampledAt - _lastSample! > 5) {
      resetSamples();
    }

    _lastSample = sampledAt;
    if (now - sampledAt > 5 || now < _stableUntil) {
      _good = 0;
      _poor = 0;

      return null;
    }

    final int step;

    switch (quality) {
      case RealtimeNetworkQualityLevel.bad:
      case RealtimeNetworkQualityLevel.veryBad:
        _good = 0;
        if (++_poor < 3) {
          return null;
        }
        step = 1;
      case RealtimeNetworkQualityLevel.excellent:
      case RealtimeNetworkQualityLevel.good:
        _poor = 0;
        if (++_good < 5 || now < _upgradeAfter) {
          return null;
        }
        step = -1;
      default:
        _good = 0;
        _poor = 0;
        return null;
    }
    for (
      var candidate = level.value + step;
      candidate >= 1 && candidate <= 5;
      candidate += step
    ) {
      final next = RealtimeQualityLevel.values[candidate - 1];

      if (QualityVideoFormat.resolve(
        baseline,
        next,
        downlink: downlink,
      ) !=
              format &&
          _supports(next)) {
        return next;
      }
    }

    return null;
  }

  /// Records adjustment success and updates stability, upgrade probing, and recovery cooldown
  /// windows.
  ///
  /// Parameters:
  /// - [next]: The quality level attempted by this adjustment.
  /// - [success]: Whether the target level was applied successfully.
  /// - [now]: The monotonic time, in seconds.
  void complete(
    RealtimeQualityLevel next, {
    required bool success,
    required double now,
  }) {
    resetSamples();
    _stableUntil = now + 4;
    if (!success) {
      return;
    }

    if (next.value < level.value) {
      _probeUntil = now + 20;
    } else if (next.value > level.value) {
      if (now < _probeUntil) {
        _upgradeAfter = now + 60;
      }

      _probeUntil = 0;
    }

    level = next;
  }
}
