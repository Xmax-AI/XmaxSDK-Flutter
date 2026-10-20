//
//  VideoStatistics.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 视频上行统计。
///
/// 未提供或不符合取值范围的指标为 null；有效的零帧率、零码率和零丢包率保留为 0。
final class UplinkVideoStatistics {

  /// 创建上行视频统计信息。
  const UplinkVideoStatistics({
    this.width,
    this.height,
    this.captureFrameRate,
    this.encodeFrameRate,
    this.sendFrameRate,
    this.bitrateKbps,
    this.packetLossPercent,
  });

  /// 实际编码宽度，单位为像素。
  final int? width;

  /// 实际编码高度，单位为像素。
  final int? height;

  /// 实际采集帧率，单位为 fps。
  final int? captureFrameRate;

  /// 编码器输出帧率，单位为 fps。
  final int? encodeFrameRate;

  /// 实际发送帧率，单位为 fps。
  final int? sendFrameRate;

  /// 发送码率，单位为 kbps。
  final int? bitrateKbps;

  /// 本地到 RTC 服务的丢包率，范围为 0～100。
  final int? packetLossPercent;
}

/// RTC 视频下行统计。
///
/// 未提供或不符合取值范围的指标为 null；有效的零帧率、零码率、零丢包率和零时延保留为 0。
final class DownlinkVideoStatistics {

  /// 创建下行视频统计信息。
  const DownlinkVideoStatistics({
    required this.userID,
    this.width,
    this.height,
    this.decodeFrameRate,
    this.renderFrameRate,
    this.bitrateKbps,
    this.packetLossPercent,
    this.endToEndDelayMs,
  });

  /// 远端 RTC 用户账号，不是数字 UID。
  final String userID;

  /// 接收视频宽度，单位为像素。
  final int? width;

  /// 接收视频高度，单位为像素。
  final int? height;

  /// 解码器输出帧率，单位为 fps。
  final int? decodeFrameRate;

  /// RTC 实际渲染帧率，单位为 fps。
  final int? renderFrameRate;

  /// 接收码率，单位为 kbps。
  final int? bitrateKbps;

  /// 下行视频丢包率，范围为 0～100。
  final int? packetLossPercent;

  /// RTC 媒体端到端时延，单位为毫秒，不代表完整 AI 生成耗时。
  final int? endToEndDelayMs;
}

/// 接收本地视频上行统计。
///
/// - [statistics]：当前样本；停止发布或断开连接时为 null，表示清除上行统计。
typedef UplinkVideoStatisticsListener =
    void Function(
      UplinkVideoStatistics? statistics,
    );

/// 接收当前结果流的下行视频统计。
///
/// - [statistics]：当前样本；结果流清理或断开连接时为 null，表示清除下行统计。
typedef DownlinkVideoStatisticsListener =
    void Function(
      DownlinkVideoStatistics? statistics,
    );
