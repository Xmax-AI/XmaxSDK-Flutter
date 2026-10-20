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
import 'QualityControlling.dart';
import 'QualityDirection.dart';
import 'QualityHistory.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// 独立维护上下行质量档位，提供调档建议并记录成功应用的档位。
final class QualityController implements QualityControlling {

  /// 当前上行链路的档位策略。
  QualityDirection? _up;

  /// 当前下行链路的档位策略。
  QualityDirection? _down;

  /// 当前模型上下行成功档位的本地历史存储。
  QualityHistory? _history;

  /// 当前异步操作的版本号。
  int _version = 0;

  /// 读取模型的有效档位历史，准备独立上下行策略并应用初始传输规格。
  ///
  /// 详细说明见 [QualityControlling.prepareQuality]。
  @override
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
  }) async {
    final version = ++_version;
    final history = QualityHistory(model);
    final up = await history.read(downlink: false);
    final down = await history.read(downlink: true);

    if (version != _version) return;

    _history = history;
    _up = QualityDirection(baseline: baseline, level: up, downlink: false);
    _down = QualityDirection(baseline: baseline, level: down, downlink: true);
  }

  /// 当前上行档位的视频规格；质量策略尚未准备时为空。
  @override
  RealtimeVideoFormat? get uplinkFormat => _up?.format;

  /// 不随网络调档改变的媒体尺寸、帧率和编码配置。
  @override
  RealtimeVideoFormat? get baseline => _up?.baseline;

  /// 当前下行质量档位，范围为 1～5；默认值为 2。
  @override
  int get downlinkLevel => _down?.level ?? 2;

  /// 依据连续网络样本和冷却期提出独立的上行、下行候选档位。
  ///
  /// 详细说明见 [QualityControlling.proposeQuality]。
  @override
  (int?, int?) proposeQuality(
    RealtimeNetworkQuality quality,
    double now,
  ) => (
    _up?.observe(quality.uplink, sampledAt: now, now: now),
    _down?.observe(quality.downlink, sampledAt: now, now: now),
  );

  /// 提交本次调档结果，成功时保存对应方向的模型档位历史。
  ///
  /// 详细说明见 [QualityControlling.completeQuality]。
  @override
  Future<void> completeQuality(
    int level, {
    required bool downlink,
    required bool success,
    required double now,
  }) async {
    (downlink ? _down : _up)?.complete(level, success: success, now: now);

    final history = _history;

    if (success && history != null) {
      await history.write(level, downlink: downlink);
    }
  }

  /// 清除连续好坏网络样本，保留当前档位。
  @override
  void resetQualitySamples() {
    _up?.resetSamples();
    _down?.resetSamples();
  }

  /// 清除当前上下行策略及历史绑定，使尚未完成的准备任务失效。
  @override
  void resetQuality() {
    _version++;
    _up = null;
    _down = null;
    _history = null;
  }

  /// 网络质量事件的外部监听器。
  RealtimeNetworkQualityListener? _networkQualityListener;

  /// 性能受限与恢复事件的外部监听器。
  RealtimePerformanceAlarmListener? _performanceAlarmListener;

  /// 设置上下行网络质量监听器，不替换 SDK 内部自适应策略。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  ) {
    _networkQualityListener = listener;
  }

  /// 设置性能受限及恢复事件的监听器。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  ) {
    _performanceAlarmListener = listener;
  }

  /// 通知网络质量监听器，不替换内部质量策略。
  ///
  /// - [quality]：同一次采样得到的上下行网络质量。
  @override
  void emitNetworkQuality(
    RealtimeNetworkQuality quality,
  ) {
    _networkQualityListener?.call(quality);
  }

  /// 通知性能受限或恢复事件。
  ///
  /// - [alarm]：性能受限或恢复事件。
  @override
  void emitPerformanceAlarm(
    RealtimePerformanceAlarm alarm,
  ) {
    _performanceAlarmListener?.call(alarm);
  }
}
