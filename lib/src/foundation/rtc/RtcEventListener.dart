//
//  RtcEventListener.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import 'RemoteStream.dart';
import 'VideoStatistics.dart';

/// The internal RTC publication, first-frame, quality, statistics, and failure callbacks.
final class RtcEventListener {

  /// Creates RTC event callbacks.
  const RtcEventListener({
    this.onRemoteVideoPublished,
    this.onFirstRemoteVideoFrameRendered,
    this.onFirstRemoteVideoFrameDecoded,
    this.onRemoteAudioPublished,
    this.onError,
    this.onNetworkQuality,
    this.onPerformanceAlarm,
    this.onUplinkVideoStatistics,
    this.onDownlinkVideoStatistics,
  });

  /// The remote video publication callback.
  final void Function(
    RemoteStream stream,
    bool published,
  )?
  onRemoteVideoPublished;

  /// The callback for a rendered first remote video frame.
  final void Function(
    RemoteStream stream,
  )?
  onFirstRemoteVideoFrameRendered;

  /// The callback for a decoded first remote video frame.
  final void Function(
    RemoteStream stream,
  )?
  onFirstRemoteVideoFrameDecoded;

  /// The remote audio publication callback.
  final void Function(
    RemoteStream stream,
    bool published,
  )?
  onRemoteAudioPublished;

  /// The RTC runtime failure callback.
  final void Function(
    Object error,
  )?
  onError;

  /// The local user's uplink and downlink quality callback.
  final void Function(
    RealtimeNetworkQuality quality,
  )?
  onNetworkQuality;

  /// The performance limitation or recovery callback.
  final void Function(
    RealtimePerformanceAlarm alarm,
  )?
  onPerformanceAlarm;

  /// The uplink statistics callback; see [UplinkVideoStatisticsListener] for sample and cleanup
  /// semantics.
  final UplinkVideoStatisticsListener? onUplinkVideoStatistics;

  /// The downlink statistics callback; see [DownlinkVideoStatisticsListener] for sample and cleanup
  /// semantics.
  final DownlinkVideoStatisticsListener? onDownlinkVideoStatistics;
}
