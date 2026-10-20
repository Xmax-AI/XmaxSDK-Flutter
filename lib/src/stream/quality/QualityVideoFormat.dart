//
//  QualityVideoFormat.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;
import 'dart:ui';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// 从固定媒体基准计算传输档位，不改变采集和模型生成规格。
abstract final class QualityVideoFormat {

  /// 按质量档位排列的视频尺寸缩放比例。
  static const scales = [1.0, 0.8, 0.65, 0.5, 0.5];

  /// 按质量档位排列的上行目标帧率，单位为 fps。
  static const frameRates = [30, 24, 24, 20, 16];

  /// 解析目标档位的缩放比例，同时保留最低短边约束。
  ///
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [level]：需要解析的质量档位，限制为 1～5。
  ///
  /// 返回计算得到的数值。
  static double scale(
    RealtimeVideoFormat baseline,
    int level,
  ) => math.max(
    scales[level.clamp(1, 5) - 1],
    math.min(math.min(baseline.width, baseline.height), 240) /
        math.min(baseline.width, baseline.height),
  );

  /// 根据基准和档位计算回传尺寸的最大宽高。
  ///
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [level]：需要解析的质量档位，限制为 1～5。
  ///
  /// 返回该档位允许的最大回传宽高，尚未进行像素对齐。
  static Size downlinkMaximumSize(
    RealtimeVideoFormat baseline,
    int level,
  ) => Size(
    baseline.width * scale(baseline, level),
    baseline.height * scale(baseline, level),
  );

  /// 按指定方向和档位解析传输规格，不改变采集基准。
  ///
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [level]：需要解析的质量档位，限制为 1～5。
  /// - [downlink]：是否计算下行规格；下行预算固定为 24 fps。
  ///
  /// 返回包含有效尺寸、帧率及编码配置的视频规格。
  static RealtimeVideoFormat resolve(
    RealtimeVideoFormat baseline,
    int level, {
    required bool downlink,
  }) {
    final s = scale(baseline, level),
        divisor = baseline.width.gcd(baseline.height);
    final units = ((divisor * s + 0.0000001).floor() ~/ 2) * 2;
    final width = units >= 2
        ? baseline.width ~/ divisor * units
        : math.max(2, (baseline.width * s / 2).floor() * 2);
    final height = units >= 2
        ? baseline.height ~/ divisor * units
        : math.max(2, (baseline.height * s / 2).floor() * 2);

    return RealtimeVideoFormat(
      width: width,
      height: height,
      fps: downlink
          ? 24
          : math.min(baseline.fps, frameRates[level.clamp(1, 5) - 1]),
      minimumBitrate: downlink ? null : baseline.minimumBitrate,
      maximumBitrate: downlink ? null : baseline.maximumBitrate,
      encoderPreference: baseline.encoderPreference,
    );
  }
}
