//
//  QualityConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../core/realtime/RealtimeQualityLevel.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'QualityVideoFormat.dart';

/// 当前连接的固定媒体基准与已成功应用的上下行档位。
final class QualityConfiguration {

  /// 创建传输配置快照。
  const QualityConfiguration({
    required this.baseline,
    required this.uplinkLevel,
    required this.downlinkLevel,
  });

  /// 不随传输调档改变的媒体规格。
  final RealtimeVideoFormat baseline;

  /// 已成功应用的上行档位。
  final RealtimeQualityLevel uplinkLevel;

  /// 已成功提交的下行目标档位。
  final RealtimeQualityLevel downlinkLevel;

  /// 当前上行编码规格。
  RealtimeVideoFormat get uplink => QualityVideoFormat.resolve(
    baseline,
    uplinkLevel,
    downlink: false,
  );

  /// 当前下行目标规格，尚未应用服务端尺寸对齐约束。
  RealtimeVideoFormat get downlink => QualityVideoFormat.resolve(
    baseline,
    downlinkLevel,
    downlink: true,
  );
}

/// 同一次采样产生的候选档位；空值表示该方向保持不变。
final class QualityChange {

  /// 创建上下行调档建议。
  const QualityChange({
    this.uplink,
    this.downlink,
  });

  /// 上行候选档位。
  final RealtimeQualityLevel? uplink;

  /// 下行候选档位。
  final RealtimeQualityLevel? downlink;
}
