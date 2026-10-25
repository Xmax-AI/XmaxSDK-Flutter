//
//  RtcQualityConverter.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'VideoStatistics.dart';

/// Converts Agora quality events to SDK metrics.
abstract final class RtcQualityConverter {

  /// Converts local video statistics, retaining valid zeros for rates and loss.
  ///
  /// [stats] contains the native encoding and sending measurements.
  static UplinkVideoStatistics uplinkVideoStatistics(
    LocalVideoStats stats,
  ) => UplinkVideoStatistics(
    width: _positive(stats.encodedFrameWidth),
    height: _positive(stats.encodedFrameHeight),
    captureFrameRate: _nonnegative(stats.captureFrameRate),
    encodeFrameRate: _nonnegative(stats.encoderOutputFrameRate),
    sendFrameRate: _nonnegative(stats.sentFrameRate),
    bitrateKbps: _nonnegative(stats.sentBitrate),
    packetLossPercent: _loss(stats.txPacketLossRate),
  );

  /// Converts remote video statistics for a resolved RTC account.
  ///
  /// Parameters:
  /// - [userID]: The remote RTC account.
  /// - [stats]: The native receiving and rendering measurements.
  static DownlinkVideoStatistics downlinkVideoStatistics({
    required String userID,
    required RemoteVideoStats stats,
  }) => DownlinkVideoStatistics(
    userID: userID,
    width: _positive(stats.width),
    height: _positive(stats.height),
    decodeFrameRate: _nonnegative(stats.decoderOutputFrameRate),
    renderFrameRate: _nonnegative(stats.rendererOutputFrameRate),
    bitrateKbps: _nonnegative(stats.receivedBitrate),
    packetLossPercent: _loss(stats.packetLossRate),
    endToEndDelayMs: _nonnegative(stats.e2eDelay),
  );

  /// Converts a directional native network rating.
  ///
  /// [value] is the native quality rating.
  static RealtimeNetworkQualityLevel quality(
    QualityType value,
  ) => switch (value) {
    QualityType.qualityExcellent => RealtimeNetworkQualityLevel.excellent,
    QualityType.qualityGood => RealtimeNetworkQualityLevel.good,
    QualityType.qualityPoor => RealtimeNetworkQualityLevel.poor,
    QualityType.qualityBad => RealtimeNetworkQualityLevel.bad,
    QualityType.qualityVbad => RealtimeNetworkQualityLevel.veryBad,
    QualityType.qualityDown => RealtimeNetworkQualityLevel.down,
    _ => RealtimeNetworkQualityLevel.unknown,
  };

  /// Converts an adaptation indication into a performance alarm, or null without a transition.
  ///
  /// [stats] contains the native encoding dimensions, frame rate, and adaptation status.
  static RealtimePerformanceAlarm? performanceAlarm(
    LocalVideoStats stats,
  ) {
    final adaptation = stats.qualityAdaptIndication;

    if (adaptation != QualityAdaptIndication.adaptDownBandwidth &&
        adaptation != QualityAdaptIndication.adaptUpBandwidth) {
      return null;
    }

    final value = uplinkVideoStatistics(stats);

    return RealtimePerformanceAlarm(
      status: adaptation == QualityAdaptIndication.adaptDownBandwidth
          ? RealtimePerformanceStatus.limited
          : RealtimePerformanceStatus.recovered,
      suggestedVideoFormat: value.width != null && value.height != null &&
          (value.encodeFrameRate ?? 0) > 0
          ? RealtimeVideoFormat(
            width: value.width!,
            height: value.height!,
            fps: value.encodeFrameRate!,
          )
          : null,
    );
  }

  /// Retains positive statistics values.
  ///
  /// Parameters:
  /// - [value]: The RTC statistic; missing or nonpositive values resolve to null.
  static int? _positive(
    int? value,
  ) => value != null && value > 0 ? value : null;

  /// Retains nonnegative statistics values, including valid zeros.
  ///
  /// Parameters:
  /// - [value]: The RTC statistic; missing or negative values resolve to null.
  static int? _nonnegative(
    int? value,
  ) => value != null && value >= 0 ? value : null;

  /// Retains valid packet loss percentages.
  ///
  /// Parameters:
  /// - [value]: The loss percentage; missing values or values outside 0 to 100 resolve to null.
  static int? _loss(
    int? value,
  ) => value != null && value >= 0 && value <= 100 ? value : null;
}
