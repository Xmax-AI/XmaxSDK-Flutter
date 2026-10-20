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
import 'RtcModels.dart';
import 'VideoStatistics.dart';

/// RTC 媒体发布、首帧、网络质量、统计和错误的内部事件集合。
final class RtcEventListener {

  /// 创建 RTC 事件回调集合。
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

  /// 远端用户视频发布状态的变化通知。
  final void Function(
    RemoteStream stream,
    bool published,
  )?
  onRemoteVideoPublished;

  /// 远端有效首帧完成渲染时的通知。
  final void Function(
    RemoteStream stream,
  )?
  onFirstRemoteVideoFrameRendered;

  /// 远端有效首帧完成解码时的通知。
  final void Function(
    RemoteStream stream,
  )?
  onFirstRemoteVideoFrameDecoded;

  /// 远端用户音频发布状态的变化通知。
  final void Function(
    RemoteStream stream,
    bool published,
  )?
  onRemoteAudioPublished;

  /// RTC 运行错误通知。
  final void Function(
    Object error,
  )?
  onError;

  /// 当前本地用户上下行网络质量通知。
  final void Function(
    RealtimeNetworkQuality quality,
  )?
  onNetworkQuality;

  /// 性能受限或恢复通知。
  final void Function(
    RealtimePerformanceAlarm alarm,
  )?
  onPerformanceAlarm;

  /// 本地视频上行统计通知；样本及清理语义见 [UplinkVideoStatisticsListener]。
  final UplinkVideoStatisticsListener? onUplinkVideoStatistics;

  /// 下行视频统计通知；样本及清理语义见 [DownlinkVideoStatisticsListener]。
  final DownlinkVideoStatisticsListener? onDownlinkVideoStatistics;
}
