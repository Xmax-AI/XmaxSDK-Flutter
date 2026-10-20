//
//  RtcStatsLogger.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../logging/XmaxLogger.dart';
import '../logging/XmaxLoggerOption.dart';
import 'VideoStatistics.dart';

/// 输出与公开统计相同的数据，日志开关不会影响统计回调。
abstract final class RtcStatsLogger {

  /// 选择当前日志环境使用的指标文本。
  ///
  /// - [cn]：中文文本。
  /// - [en]：英文文本。
  ///
  /// 返回当前日志语言对应的指标文本。
  static String _t(
    String cn,
    String en,
  ) => XmaxLogger.localized(cn, en);

  /// 启用性能日志时，记录本地视频的上行统计。
  ///
  /// - [v]：本次上行视频统计。
  static void logUplinkVideoStatistics(
    UplinkVideoStatistics v,
  ) => _write('本地视频发送 (Local Video Uplink)', {
    _t('分辨率', 'Resolution'): '${v.width ?? '--'} × ${v.height ?? '--'}',
    _t('采集帧率', 'Capture Frame Rate'): v.captureFrameRate,
    _t('编码帧率', 'Encode Frame Rate'): v.encodeFrameRate,
    _t('发送帧率', 'Send Frame Rate'): v.sendFrameRate,
    _t('发送码率 kbps', 'Bitrate kbps'): v.bitrateKbps,
    _t('丢包率 %', 'Packet Loss %'): v.packetLossPercent,
  });

  /// 启用性能日志时，记录远端视频的下行统计。
  ///
  /// - [v]：本次下行视频统计。
  static void logDownlinkVideoStatistics(
    DownlinkVideoStatistics v,
  ) => _write('远端视频接收 (Remote Video Downlink)', {
    _t('分辨率', 'Resolution'): '${v.width ?? '--'} × ${v.height ?? '--'}',
    _t('解码帧率', 'Decode Frame Rate'): v.decodeFrameRate,
    _t('渲染帧率', 'Render Frame Rate'): v.renderFrameRate,
    _t('接收码率 kbps', 'Bitrate kbps'): v.bitrateKbps,
    _t('丢包率 %', 'Packet Loss %'): v.packetLossPercent,
    _t('端到端时延 ms', 'End-to-End Delay ms'): v.endToEndDelayMs,
  });

  /// 启用性能日志时，记录上下行网络质量。
  ///
  /// - [v]：同一次采样得到的上下行网络质量。
  static void logNetworkQuality(
    RealtimeNetworkQuality v,
  ) => _write('网络质量 (Network Quality)', {
    _t('上行', 'Uplink'): networkQualityName(v.uplink),
    _t('下行', 'Downlink'): networkQualityName(v.downlink),
  });

  /// 将网络质量等级转换为当前日志语言的名称。
  ///
  /// - [q]：当前网络质量等级。
  ///
  /// 返回当前日志语言中的网络质量名称。
  static String networkQualityName(
    RealtimeNetworkQualityLevel q,
  ) => switch (q) {
    RealtimeNetworkQualityLevel.excellent => _t('极好', 'Excellent'),
    RealtimeNetworkQualityLevel.good => _t('良好', 'Good'),
    RealtimeNetworkQualityLevel.poor => _t('一般', 'Poor'),
    RealtimeNetworkQualityLevel.bad => _t('较差', 'Bad'),
    RealtimeNetworkQualityLevel.veryBad => _t('极差', 'Very Bad'),
    RealtimeNetworkQualityLevel.down => _t('断开', 'Down'),
    _ => _t('未知', 'Unknown'),
  };

  /// 将有效百分比格式化为文本；缺失时显示 --。
  ///
  /// - [value]：待格式化的丢包率百分比；不可用时为空。
  ///
  /// 返回百分比文本；数值缺失时为 --。
  static String percentage(
    num value,
  ) => '${(value * 100).toStringAsFixed(2)}%';

  /// 按当前日志选项输出已格式化的日志。
  ///
  /// - [title]：日志组的标题。
  /// - [metrics]：日志组内的指标文本。
  static void _write(
    String title,
    Map<String, Object?> metrics,
  ) {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.performance)) return;

    final lines = [title];
    var index = 0;

    for (final metric in metrics.entries) {
      lines.add(
        '${++index == metrics.length ? '└─' : '├─'} ${metric.key}: ${metric.value ?? '--'}',
      );
    }

    XmaxLogger.debug(
      category: XmaxLoggerCategory.rtc,
      option: XmaxLoggerOption.performance,
      message: lines.join('\n'),
    );
  }
}
