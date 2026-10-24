//
//  RtcQualityListener.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import 'VideoStatistics.dart';

/// Receives RTC quality events independently of room publication and generation events.
abstract interface class RtcQualityListener {

  /// Receives the local video uplink sample.
  ///
  /// Parameters:
  /// - [statistics]: The local encoding and sending measurements.
  void onUplinkVideoStatistics(
    UplinkVideoStatistics statistics,
  );

  /// Receives a remote user's downlink sample.
  ///
  /// Parameters:
  /// - [statistics]: The receiving and rendering measurements, including their remote user.
  void onDownlinkVideoStatistics(
    DownlinkVideoStatistics statistics,
  );

  /// Receives directional network quality from one RTC sample.
  ///
  /// Parameters:
  /// - [quality]: The uplink and downlink measurements.
  void onNetworkQuality(
    RealtimeNetworkQuality quality,
  );

  /// Receives a performance limitation or recovery suggestion.
  ///
  /// Parameters:
  /// - [alarm]: The status and optional suggested video format.
  void onPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  );
}
