//
//  QualityDirection.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../core/realtime/RealtimeQualityLevel.dart';
import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../encoding/EncodingBitratePolicy.dart';
import 'QualityVideoFormat.dart';

/// 单个传输方向的连续采样、升降档和恢复冷却规则。
final class QualityDirection {

  /// 创建单方向质量策略，并将初始档位限制到可用范围。
  ///
  /// - [baseline]：不随网络调档改变的媒体规格。
  /// - [level]：初始档位；预算不支持时逐级提高规格，直到预算有效或达到 L1。
  /// - [downlink]：是否应用下行策略；false 表示上行。
  QualityDirection({
    required this.baseline,
    required this.level,
    required this.downlink,
  }) {
    while (level != RealtimeQualityLevel.l1 && !_supports(level)) {
      level = RealtimeQualityLevel.values[level.index - 1];
    }
  }

  /// 不随网络调档改变的媒体尺寸、帧率和编码配置。
  final RealtimeVideoFormat baseline;

  /// 是否计算下行规格；false 表示计算上行编码规格。
  final bool downlink;

  /// 目标质量档位，范围为 1～5。
  RealtimeQualityLevel level;

  /// 连续网络质量良好的采样次数。
  int _good = 0;

  /// 连续网络质量较差的采样次数。
  int _poor = 0;

  /// 最近一次有效网络样本的单调时钟时间，单位为秒。
  double? _lastSample;

  /// 当前调档稳定期的结束时刻，单位为单调时钟秒；此前不再调档。
  double _stableUntil = 0;

  /// 最早可再次升档的时刻，单位为单调时钟秒。
  double _upgradeAfter = 0;

  /// 升档后观察效果的截止时刻，单位为单调时钟秒。
  double _probeUntil = 0;

  /// 目标视频尺寸、帧率和编码配置。
  RealtimeVideoFormat get format =>
      QualityVideoFormat.resolve(baseline, level, downlink: downlink);

  /// 清除连续采样计数和最后样本时间，保留档位及冷却窗口。
  void resetSamples() {
    _good = 0;
    _poor = 0;
    _lastSample = null;
  }

  /// 检查目标档位是否满足当前方向的编码预算。
  ///
  /// - [level]：需要检查的目标质量档位。
  ///
  /// 返回目标质量档位能否解析为有效的传输规格。
  bool _supports(
    RealtimeQualityLevel level,
  ) {
    if (downlink) return true;

    try {
      EncodingBitratePolicy.resolve(
        QualityVideoFormat.resolve(baseline, level, downlink: false),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// 根据有效连续样本和稳定、探测、恢复窗口提出调档候选。
  ///
  /// - [quality]：当前传输方向的网络质量等级。
  /// - [sampledAt]：网络质量样本的单调时钟时间，单位为秒。
  /// - [now]：当前单调时钟时间，单位为秒。
  ///
  /// 返回候选档位；样本无效、处于冷却期或无需调整时返回 null。
  RealtimeQualityLevel? observe(
    RealtimeNetworkQualityLevel quality, {
    required double sampledAt,
    required double now,
  }) {
    if (sampledAt > now || (_lastSample != null && sampledAt <= _lastSample!)) {
      return null;
    }

    if (_lastSample != null && sampledAt - _lastSample! > 5) resetSamples();

    _lastSample = sampledAt;
    if (now - sampledAt > 5 || now < _stableUntil) {
      _good = 0;
      _poor = 0;

      return null;
    }

    final int step;

    switch (quality) {
      case RealtimeNetworkQualityLevel.bad:
      case RealtimeNetworkQualityLevel.veryBad:
        _good = 0;
        if (++_poor < 3) return null;
        step = 1;
      case RealtimeNetworkQualityLevel.excellent:
      case RealtimeNetworkQualityLevel.good:
        _poor = 0;
        if (++_good < 5 || now < _upgradeAfter) return null;
        step = -1;
      default:
        _good = 0;
        _poor = 0;
        return null;
    }
    for (
      var candidate = level.value + step;
      candidate >= 1 && candidate <= 5;
      candidate += step
    ) {
      final next = RealtimeQualityLevel.values[candidate - 1];

      if (QualityVideoFormat.resolve(baseline, next, downlink: downlink) !=
              format &&
          _supports(next)) {
        return next;
      }
    }

    return null;
  }

  /// 记录调档是否成功，并更新稳定、升档探测和恢复冷却窗口。
  ///
  /// - [next]：本次尝试应用的质量档位。
  /// - [success]：目标档位是否已成功应用。
  /// - [now]：当前单调时钟时间，单位为秒。
  void complete(
    RealtimeQualityLevel next, {
    required bool success,
    required double now,
  }) {
    resetSamples();
    _stableUntil = now + 4;
    if (!success) return;

    if (next.value < level.value) {
      _probeUntil = now + 20;
    } else if (next.value > level.value) {
      if (now < _probeUntil) _upgradeAfter = now + 60;

      _probeUntil = 0;
    }

    level = next;
  }
}
