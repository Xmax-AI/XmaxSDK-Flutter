//
//  RealtimeNetworkQuality.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 上行或下行链路的网络质量等级。
enum RealtimeNetworkQualityLevel {

  /// 尚未取得有效的网络质量。
  unknown('Unknown'),

  /// 网络质量优秀。
  excellent('Excellent'),

  /// 网络质量良好。
  good('Good'),

  /// 网络质量一般。
  poor('Poor'),

  /// 网络质量差。
  bad('Bad'),

  /// 网络质量很差。
  veryBad('VeryBad'),

  /// 网络连接已断开。
  down('Down');

  /// 定义网络质量等级标识。
  const RealtimeNetworkQualityLevel(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}

/// 同一次 RTC 采样的上行与下行网络质量。
final class RealtimeNetworkQuality {

  /// 创建同一次采样的上下行网络质量记录。
  const RealtimeNetworkQuality({
    required this.uplink,
    required this.downlink,
  });

  /// 本地视频上行链路的网络质量。
  final RealtimeNetworkQualityLevel uplink;

  /// 本地视频下行链路的网络质量。
  final RealtimeNetworkQualityLevel downlink;

  /// 与 [other] 比较类型及 [uplink]、[downlink] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimeNetworkQuality &&
          uplink == other.uplink &&
          downlink == other.downlink;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(uplink, downlink);
}

/// 接收同一次采样中上下行网络质量的回调。
///
/// - [quality]：同一次采样得到的上下行网络质量。
typedef RealtimeNetworkQualityListener =
    void Function(
      RealtimeNetworkQuality quality,
    );
