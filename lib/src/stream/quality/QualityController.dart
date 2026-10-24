//
//  QualityController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../core/realtime/RealtimeQualityLevel.dart';
import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import 'QualityControlling.dart';
import 'QualityConfiguration.dart';
import 'QualityDirection.dart';
import 'QualityHistory.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// Maintains independent link quality levels, proposes adjustments, and records successful updates.
final class QualityController implements QualityControlling {

  /// The current uplink quality policy.
  QualityDirection? _up;

  /// The current downlink quality policy.
  QualityDirection? _down;

  /// The local store for successfully applied link levels for the current model.
  QualityHistory? _history;

  /// The asynchronous operation revision.
  int _version = 0;

  /// Loads valid model history, prepares independent link policies, and applies the initial
  /// transport format.
  ///
  /// See [QualityControlling.prepareQuality] for the usage contract.
  @override
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
  }) async {
    final version = ++_version;
    final history = QualityHistory(model);
    final up = await history.read(downlink: false);
    final down = await history.read(downlink: true);

    if (version != _version) {
      return;
    }

    _history = history;
    _up = QualityDirection(
      baseline: baseline,
      level: up,
      downlink: false,
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
    );
  }

  /// Proposes independent link levels using consecutive network samples and cooldown windows.
  ///
  /// See [QualityControlling.proposeQuality] for the usage contract.
  @override
  QualityChange proposeQuality(
    RealtimeNetworkQuality quality,
    double now,
  ) => QualityChange(
    uplink: _up?.observe(
      quality.uplink,
      sampledAt: now,
      now: now,
    ),
    downlink: _down?.observe(
      quality.downlink,
      sampledAt: now,
      now: now,
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
    _networkQualityListener?.call(quality);
  }

  /// Notifies the listener of performance limitation or recovery.
  ///
  /// Parameters:
  /// - [alarm]: The performance limitation or recovery event.
  @override
  void emitPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  ) {
    _performanceAlarmListener?.call(alarm);
  }
}
