//
//  QualityControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../foundation/rtc/RtcQualityListener.dart';
import '../../foundation/rtc/VideoStatistics.dart';
import 'QualityConfiguration.dart';
import 'RealtimeQualityLevel.dart';

/// An interface for link policy preparation, level proposals, result commits, and quality
/// notifications.
abstract interface class QualityControlling implements RtcQualityListener {

  /// The current monotonic time, in seconds, used by sample and adjustment deadlines.
  double get currentTime;

  /// Sets the internal adaptation receiver independently of public quality notifications.
  ///
  /// Parameters:
  /// - [listener]: The SDK sample and timestamp handler, or null to disable adaptation.
  void setAdaptiveQualityListener(
    void Function(
      RealtimeNetworkQuality quality,
      double sampledAt,
    )? listener,
  );

  /// Sets the uplink statistics receiver; null removes it.
  ///
  /// Parameters:
  /// - [listener]: The public handler, receiving null when uplink availability changes.
  void setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  );

  /// Sets the current result stream's statistics receiver; null removes it.
  ///
  /// Parameters:
  /// - [listener]: The public handler, receiving null when the target user changes or clears.
  void setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  );

  /// Changes uplink statistics availability and clears the previous sample.
  ///
  /// Parameters:
  /// - [enabled]: Whether local video is currently published.
  void setUplinkVideoStatisticsEnabled(
    bool enabled,
  );

  /// Changes the downlink statistics user and clears the previous sample.
  ///
  /// Parameters:
  /// - [userID]: The result user to accept, or null to stop statistics delivery.
  void setDownlinkVideoStatisticsUser(
    String? userID,
  );

  /// Prepares independent link policies from model history or L1.
  ///
  /// Parameters:
  /// - [baseline]: The media dimensions, frame rate, and encoding settings unaffected by quality
  ///   updates.
  /// - [model]: The model identifier used to isolate quality-level history.
  /// - [minimumInputPixels]: The model's minimum uplink area, in pixels.
  /// - [isAdaptiveQualityEnabled]: Whether to use quality history. Disabled
  ///   connections start at L1 without reading or saving history.
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
    int minimumInputPixels = 0,
    bool isAdaptiveQualityEnabled = true,
  });

  /// The media baseline and successfully applied link levels for the current connection.
  QualityConfiguration? get qualityConfiguration;

  /// Proposes independent link levels using consecutive network samples and cooldown windows.
  ///
  /// Parameters:
  /// - [quality]: The uplink and downlink measurements from the same sample.
  /// - [now]: The monotonic time, in seconds.
  /// - [currentTime]: The processing time; defaults to [now] for immediate sample evaluation.
  ///
  /// Returns candidate link levels; null leaves that direction unchanged.
  QualityChange proposeQuality(
    RealtimeNetworkQuality quality,
    double now, {
    double? currentTime,
  });

  /// Commits an adjustment result, saving the model's level history for successful updates.
  ///
  /// Parameters:
  /// - [level]: The target quality level, from 1 to 5.
  /// - [downlink]: Whether this result is for the downlink; false means uplink.
  /// - [success]: Whether the target level was applied successfully.
  /// - [now]: The monotonic time, in seconds.
  Future<void> completeQuality(
    RealtimeQualityLevel level, {
    required bool downlink,
    required bool success,
    required double now,
  });

  /// Clears consecutive network sample counters while retaining current levels.
  void resetQualitySamples();

  /// Clears link policies and history bindings, invalidating pending preparation.
  void resetQuality();

  /// Sets the network quality listener without replacing the SDK's adaptation policy.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  );

  /// Sets the listener for performance limitation and recovery events.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  );

  /// Notifies the quality listener without replacing the internal policy.
  ///
  /// Parameters:
  /// - [quality]: The uplink and downlink measurements from the same sample.
  void emitNetworkQuality(
    RealtimeNetworkQuality quality,
  );

  /// Notifies the listener of performance limitation or recovery.
  ///
  /// Parameters:
  /// - [alarm]: The performance limitation or recovery event.
  void emitPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  );
}
