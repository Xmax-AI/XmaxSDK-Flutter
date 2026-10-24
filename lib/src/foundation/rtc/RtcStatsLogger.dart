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

/// Logs the same values exposed by statistics callbacks without controlling callback delivery.
abstract final class RtcStatsLogger {

  /// Selects a metric label for the configured log language.
  ///
  /// Parameters:
  /// - [cn]: The Chinese text.
  /// - [en]: The English text.
  ///
  /// Returns the metric text in the configured log language.
  static String _t(
    String cn,
    String en,
  ) => XmaxLogger.localized(
    cn,
    en,
  );

  /// Logs uplink video statistics when performance logging is enabled.
  ///
  /// Parameters:
  /// - [v]: The current uplink video statistics.
  static void logUplinkVideoStatistics(
    UplinkVideoStatistics v,
  ) => _write(
    '本地视频发送 (Local Video Uplink)',
    {
    _t(
      '分辨率',
      'Resolution',
    ): '${v.width ?? '--'} × ${v.height ?? '--'}',
    _t(
      '采集帧率',
      'Capture Frame Rate',
    ): v.captureFrameRate,
    _t(
      '编码帧率',
      'Encode Frame Rate',
    ): v.encodeFrameRate,
    _t(
      '发送帧率',
      'Send Frame Rate',
    ): v.sendFrameRate,
    _t(
      '发送码率 kbps',
      'Bitrate kbps',
    ): v.bitrateKbps,
    _t(
      '丢包率 %',
      'Packet Loss %',
    ): v.packetLossPercent,
  },
  );

  /// Logs downlink video statistics when performance logging is enabled.
  ///
  /// Parameters:
  /// - [v]: The current downlink video statistics.
  static void logDownlinkVideoStatistics(
    DownlinkVideoStatistics v,
  ) => _write(
    '远端视频接收 (Remote Video Downlink)',
    {
    _t(
      '分辨率',
      'Resolution',
    ): '${v.width ?? '--'} × ${v.height ?? '--'}',
    _t(
      '解码帧率',
      'Decode Frame Rate',
    ): v.decodeFrameRate,
    _t(
      '渲染帧率',
      'Render Frame Rate',
    ): v.renderFrameRate,
    _t(
      '接收码率 kbps',
      'Bitrate kbps',
    ): v.bitrateKbps,
    _t(
      '丢包率 %',
      'Packet Loss %',
    ): v.packetLossPercent,
    _t(
      '端到端时延 ms',
      'End-to-End Delay ms',
    ): v.endToEndDelayMs,
  },
  );

  /// Logs uplink and downlink quality when performance logging is enabled.
  ///
  /// Parameters:
  /// - [v]: The uplink and downlink measurements from the same sample.
  static void logNetworkQuality(
    RealtimeNetworkQuality v,
  ) => _write(
    '网络质量 (Network Quality)',
    {
    _t(
      '上行',
      'Uplink',
    ): networkQualityName(v.uplink),
    _t(
      '下行',
      'Downlink',
    ): networkQualityName(v.downlink),
  },
  );

  /// Formats a network quality level in the configured log language.
  ///
  /// Parameters:
  /// - [q]: The current network quality.
  ///
  /// Returns the localized network quality name.
  static String networkQualityName(
    RealtimeNetworkQualityLevel q,
  ) => switch (q) {
    RealtimeNetworkQualityLevel.excellent => _t(
      '极好',
      'Excellent',
    ),
    RealtimeNetworkQualityLevel.good => _t(
      '良好',
      'Good',
    ),
    RealtimeNetworkQualityLevel.poor => _t(
      '一般',
      'Poor',
    ),
    RealtimeNetworkQualityLevel.bad => _t(
      '较差',
      'Bad',
    ),
    RealtimeNetworkQualityLevel.veryBad => _t(
      '极差',
      'Very Bad',
    ),
    RealtimeNetworkQualityLevel.down => _t(
      '断开',
      'Down',
    ),
    _ => _t(
      '未知',
      'Unknown',
    ),
  };

  /// Formats a valid percentage, using -- for missing values.
  ///
  /// Parameters:
  /// - [value]: The packet loss percentage to format, or null when unavailable.
  ///
  /// Returns a percentage string, or -- for missing values.
  static String percentage(
    num value,
  ) => '${(value * 100).toStringAsFixed(2)}%';

  /// Writes formatted logs using the current logging options.
  ///
  /// Parameters:
  /// - [title]: The log group's title.
  /// - [metrics]: The metric lines in the log group.
  static void _write(
    String title,
    Map<String, Object?> metrics,
  ) {
    if (!XmaxLogger.isEnabled(XmaxLoggerOption.performance)) {
      return;
    }

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
