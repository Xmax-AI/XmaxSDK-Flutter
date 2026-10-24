//
//  VideoStatistics.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Statistics for the outgoing RTC video stream.
///
/// Missing or invalid metrics are null; valid zero frame rates, bitrates, and packet loss remain
/// zero.
final class UplinkVideoStatistics {

  /// Creates uplink video statistics.
  const UplinkVideoStatistics({
    this.width,
    this.height,
    this.captureFrameRate,
    this.encodeFrameRate,
    this.sendFrameRate,
    this.bitrateKbps,
    this.packetLossPercent,
  });

  /// The encoded width, in pixels.
  final int? width;

  /// The encoded height, in pixels.
  final int? height;

  /// The measured capture frame rate, in frames per second.
  final int? captureFrameRate;

  /// The encoder output frame rate, in fps.
  final int? encodeFrameRate;

  /// The transmitted frame rate, in fps.
  final int? sendFrameRate;

  /// The sending bitrate, in kbps.
  final int? bitrateKbps;

  /// The local-to-RTC packet loss percentage, from 0 to 100.
  final int? packetLossPercent;
}

/// Statistics for the incoming RTC video stream.
///
/// Missing or invalid metrics are null; valid zero frame rates, bitrates, loss, and delay remain
/// zero.
final class DownlinkVideoStatistics {

  /// Creates downlink video statistics.
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

  /// The remote RTC account, not a numeric UID.
  final String userID;

  /// The received video width, in pixels.
  final int? width;

  /// The received height, in pixels.
  final int? height;

  /// The decoder output frame rate, in fps.
  final int? decodeFrameRate;

  /// The RTC rendering frame rate, in fps.
  final int? renderFrameRate;

  /// The receiving bitrate, in kbps.
  final int? bitrateKbps;

  /// The downlink packet loss percentage, from 0 to 100.
  final int? packetLossPercent;

  /// The RTC media end-to-end delay, in milliseconds; excludes the full AI generation duration.
  final int? endToEndDelayMs;
}

/// Receives local uplink video statistics.
///
/// Parameters:
/// - [statistics]: The sample, or null to clear uplink statistics after unpublishing or
///   disconnection.
typedef UplinkVideoStatisticsListener =
    void Function(
      UplinkVideoStatistics? statistics,
    );

/// A listener receiving downlink statistics for the current result stream.
///
/// Parameters:
/// - [statistics]: The sample, or null to clear downlink statistics after stream removal or
///   disconnection.
typedef DownlinkVideoStatisticsListener =
    void Function(
      DownlinkVideoStatistics? statistics,
    );
