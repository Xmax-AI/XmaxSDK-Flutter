//
//  RealtimePerformanceAlarm.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeVideoFormat.dart';

/// 实时媒体传输的性能受限或恢复状态。
enum RealtimePerformanceStatus {

  /// 设备或链路性能受限。
  limited('Limited'),

  /// 设备或链路性能已恢复。
  recovered('Recovered');

  /// 定义性能状态标识。
  const RealtimePerformanceStatus(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}

/// 性能状态和可用的视频规格建议；建议值不代表已应用的采集配置。
final class RealtimePerformanceAlarm {

  /// 创建性能状态与视频规格建议。
  const RealtimePerformanceAlarm({
    required this.status,
    this.suggestedVideoFormat,
  });

  /// 本次事件的性能受限或恢复状态。
  final RealtimePerformanceStatus status;

  /// 性能事件建议的视频规格；不可用时为空。
  final RealtimeVideoFormat? suggestedVideoFormat;

  /// 与 [other] 比较类型及 [status]、[suggestedVideoFormat] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimePerformanceAlarm &&
          status == other.status &&
          suggestedVideoFormat == other.suggestedVideoFormat;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(status, suggestedVideoFormat);
}

/// 接收性能受限或恢复状态及可用规格建议的回调。
///
/// - [alarm]：性能受限或恢复事件。
typedef RealtimePerformanceAlarmListener =
    void Function(
      RealtimePerformanceAlarm alarm,
    );
