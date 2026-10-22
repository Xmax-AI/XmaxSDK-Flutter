//
//  QualityControlling.dart
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
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'QualityConfiguration.dart';

/// 上下行档位准备、候选决策、结果提交和质量通知接口。
abstract interface class QualityControlling {

  /// 读取模型的有效档位历史，准备独立上下行策略并应用初始传输规格。
  ///
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [model]：用于隔离档位历史的模型标识。
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
  });

  /// 当前连接的媒体基准和成功应用的上下行档位。
  QualityConfiguration? get qualityConfiguration;

  /// 依据连续网络样本和冷却期提出独立的上行、下行候选档位。
  ///
  /// - [quality]：同一次采样得到的上下行网络质量。
  /// - [now]：当前单调时钟时间，单位为秒。
  ///
  /// 返回上下行候选档位；空值表示该方向保持不变。
  QualityChange proposeQuality(
    RealtimeNetworkQuality quality,
    double now,
  );

  /// 提交本次调档结果，成功时保存对应方向的模型档位历史。
  ///
  /// - [level]：目标质量档位，范围为 1～5。
  /// - [downlink]：是否提交下行档位结果；false 表示上行。
  /// - [success]：目标档位是否已成功应用。
  /// - [now]：当前单调时钟时间，单位为秒。
  Future<void> completeQuality(
    RealtimeQualityLevel level, {
    required bool downlink,
    required bool success,
    required double now,
  });

  /// 清除连续好坏网络样本，保留当前档位。
  void resetQualitySamples();

  /// 清除当前上下行策略及历史绑定，使尚未完成的准备任务失效。
  void resetQuality();

  /// 设置上下行网络质量监听器，不替换 SDK 内部自适应策略。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  );

  /// 设置性能受限及恢复事件的监听器。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  );

  /// 通知网络质量监听器，不替换内部质量策略。
  ///
  /// - [quality]：同一次采样得到的上下行网络质量。
  void emitNetworkQuality(
    RealtimeNetworkQuality quality,
  );

  /// 通知性能受限或恢复事件。
  ///
  /// - [alarm]：性能受限或恢复事件。
  void emitPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  );
}
