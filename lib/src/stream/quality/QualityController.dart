//
//  QualityController.dart
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
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/VideoStatistics.dart';
import 'QualityConfiguration.dart';
import 'QualityControlling.dart';
import 'QualityDirection.dart';
import 'QualityHistory.dart';
import 'RealtimeQualityLevel.dart';

/// Routes RTC quality and statistics events and maintains independent link adaptation policies.
final class QualityController implements QualityControlling {

  /// Creates directional policies and registers an independent RTC quality receiver.
  ///
  /// Parameters:
  /// - [rtcManager]: The event source; omit when exercising the policy without RTC.
  /// - [monotonicTime]: The clock in seconds; defaults to a monotonic stopwatch.
  QualityController({
    RtcManaging? rtcManager,
    double Function()? monotonicTime,
  }) : _monotonicTime = monotonicTime {
    rtcManager?.setQualityListener(this);
  }

  /// The injectable monotonic clock, in seconds.
  final double Function()? _monotonicTime;

  /// The default clock shared by sampling and adjustment deadlines.
  final Stopwatch _clock = Stopwatch()..start();

  /// The current monotonic time, in seconds.
  @override
  double get currentTime => _monotonicTime?.call() ?? _clock.elapsedMicroseconds / 1e6;

  /// The internal adaptation receiver.
  void Function(
    RealtimeNetworkQuality quality,
    double sampledAt,
  )? _adaptiveListener;

  /// The public uplink statistics receiver.
  UplinkVideoStatisticsListener? _uplinkStatisticsListener;

  /// The public downlink statistics receiver.
  DownlinkVideoStatisticsListener? _downlinkStatisticsListener;

  /// Whether uplink statistics describe currently published video.
  bool _uplinkStatisticsEnabled = false;

  /// The user providing the current result stream, or null when cleared.
  String? _downlinkStatisticsUser;

  /// Sets the internal adaptation receiver independently of public notifications.
  ///
  /// See [QualityControlling.setAdaptiveQualityListener] for the usage contract.
  @override
  void setAdaptiveQualityListener(
    void Function(
      RealtimeNetworkQuality quality,
      double sampledAt,
    )? listener,
  ) {
    _adaptiveListener = listener;
  }

  /// Sets the public uplink statistics receiver.
  ///
  /// See [QualityControlling.setUplinkVideoStatisticsListener] for the usage contract.
  @override
  void setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  ) {
    _uplinkStatisticsListener = listener;
  }

  /// Sets the public downlink statistics receiver.
  ///
  /// See [QualityControlling.setDownlinkVideoStatisticsListener] for the usage contract.
  @override
  void setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  ) {
    _downlinkStatisticsListener = listener;
  }

  /// Changes uplink statistics availability and clears the previous sample.
  ///
  /// See [QualityControlling.setUplinkVideoStatisticsEnabled] for the usage contract.
  @override
  void setUplinkVideoStatisticsEnabled(
    bool enabled,
  ) {
    _uplinkStatisticsEnabled = enabled;
    _notify(() => _uplinkStatisticsListener?.call(null));
  }

  /// Changes the result stream's statistics target and clears the previous sample.
  ///
  /// See [QualityControlling.setDownlinkVideoStatisticsUser] for the usage contract.
  @override
  void setDownlinkVideoStatisticsUser(
    String? userID,
  ) {
    _downlinkStatisticsUser = userID;
    _notify(() => _downlinkStatisticsListener?.call(null));
  }

  /// Delivers uplink statistics only while local video is published.
  ///
  /// Parameters:
  /// - [statistics]: The local encoding and sending measurements.
  @override
  void onUplinkVideoStatistics(
    UplinkVideoStatistics statistics,
  ) {
    if (_uplinkStatisticsEnabled) {
      _notify(() => _uplinkStatisticsListener?.call(statistics));
    }
  }

  /// Delivers statistics only for the user providing the current result.
  ///
  /// Parameters:
  /// - [statistics]: The receiving and rendering measurements, including their remote user.
  @override
  void onDownlinkVideoStatistics(
    DownlinkVideoStatistics statistics,
  ) {
    if (statistics.userID == _downlinkStatisticsUser) {
      _notify(() => _downlinkStatisticsListener?.call(statistics));
    }
  }

  /// Evaluates SDK adaptation before delivering the sample to your app.
  ///
  /// Parameters:
  /// - [quality]: The directional measurements from the same RTC sample.
  @override
  void onNetworkQuality(
    RealtimeNetworkQuality quality,
  ) {
    final sampledAt = currentTime;

    _notify(() => _adaptiveListener?.call(
      quality,
      sampledAt,
    ));
    emitNetworkQuality(quality);
  }

  /// Delivers device limitation or recovery to your app.
  ///
  /// Parameters:
  /// - [alarm]: The status and suggested format; does not change capture settings.
  @override
  void onPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  ) => emitPerformanceAlarm(alarm);

  /// Contains observer failures without interrupting media, adaptation, or other notifications.
  ///
  /// Parameters:
  /// - [notification]: The synchronous event delivery.
  void _notify(
    void Function() notification,
  ) {
    try {
      notification();
    } catch (_) {
      try {
        XmaxLogger.warn(
          category: XmaxLoggerCategory.rtc,
          message: XmaxLogger.localized(
            '质量事件回调失败 (Quality Event Callback Failed)',
            'Quality Event Callback Failed',
          ),
        );
      } catch (_) {}
    }
  }

  /// The current uplink quality policy.
  QualityDirection? _up;

  /// The current downlink quality policy.
  QualityDirection? _down;

  /// The local store for successfully applied link levels for the current model.
  QualityHistory? _history;

  /// The asynchronous operation revision.
  int _version = 0;

  /// Prepares independent link policies from model history or L1.
  ///
  /// See [QualityControlling.prepareQuality] for the usage contract.
  @override
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
    int minimumInputPixels = 0,
    bool isAdaptiveQualityEnabled = true,
  }) async {
    final version = ++_version;
    final history = isAdaptiveQualityEnabled ? QualityHistory(model) : null;
    final up = await history?.read(downlink: false) ?? RealtimeQualityLevel.l1;
    final down = await history?.read(downlink: true) ?? RealtimeQualityLevel.l1;

    if (version != _version) {
      return;
    }

    _history = history;
    _up = QualityDirection(
      baseline: baseline,
      level: up,
      downlink: false,
      minimumInputPixels: minimumInputPixels,
    );
    _down = QualityDirection(
      baseline: baseline,
      level: down,
      downlink: true,
    );
  }

  /// The prepared media baseline and applied levels; null before preparation or after cleanup.
  @override
  QualityConfiguration? get qualityConfiguration {
    final up = _up;
    final down = _down;

    if (up == null || down == null) {
      return null;
    }

    return QualityConfiguration(
      baseline: up.baseline,
      uplinkLevel: up.level,
      downlinkLevel: down.level,
      minimumInputPixels: up.minimumInputPixels,
    );
  }

  /// Proposes independent link levels using consecutive network samples and cooldown windows.
  ///
  /// See [QualityControlling.proposeQuality] for the usage contract.
  @override
  QualityChange proposeQuality(
    RealtimeNetworkQuality quality,
    double now, {
    double? currentTime,
  }) => QualityChange(
    uplink: _up?.observe(
      quality.uplink,
      sampledAt: now,
      now: currentTime ?? now,
    ),
    downlink: _down?.observe(
      quality.downlink,
      sampledAt: now,
      now: currentTime ?? now,
    ),
  );

  /// Commits an adjustment result, saving the model's level history for successful updates.
  ///
  /// See [QualityControlling.completeQuality] for the usage contract.
  @override
  Future<void> completeQuality(
    RealtimeQualityLevel level, {
    required bool downlink,
    required bool success,
    required double now,
  }) async {
    (downlink ? _down : _up)?.complete(
      level,
      success: success,
      now: now,
    );

    final history = _history;

    if (success && history != null) {
      await history.write(
        level,
        downlink: downlink,
      );
    }
  }

  /// Clears consecutive network sample counters while retaining current levels.
  @override
  void resetQualitySamples() {
    _up?.resetSamples();
    _down?.resetSamples();
  }

  /// Clears link policies and history bindings, invalidating pending preparation.
  @override
  void resetQuality() {
    _adaptiveListener = null;
    _version++;
    _up = null;
    _down = null;
    _history = null;
  }

  /// The external listener for network quality events.
  RealtimeNetworkQualityListener? _networkQualityListener;

  /// The external listener for performance limitation and recovery events.
  RealtimePerformanceAlarmListener? _performanceAlarmListener;

  /// Sets the network quality listener without replacing the SDK's adaptation policy.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  ) {
    _networkQualityListener = listener;
  }

  /// Sets the listener for performance limitation and recovery events.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  ) {
    _performanceAlarmListener = listener;
  }

  /// Notifies the quality listener without replacing the internal policy.
  ///
  /// Parameters:
  /// - [quality]: The uplink and downlink measurements from the same sample.
  @override
  void emitNetworkQuality(
    RealtimeNetworkQuality quality,
  ) {
    _notify(() => _networkQualityListener?.call(quality));
  }

  /// Notifies the listener of performance limitation or recovery.
  ///
  /// Parameters:
  /// - [alarm]: The performance limitation or recovery event.
  @override
  void emitPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  ) {
    _notify(() => _performanceAlarmListener?.call(alarm));
  }
}
