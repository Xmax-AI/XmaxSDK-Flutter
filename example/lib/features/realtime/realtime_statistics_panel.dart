import 'package:flutter/material.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import '../../localization/xlab_localization.dart';

/// 仅展示 SDK 统计，不推导或控制 RTC 档位。
class RealtimeStatisticsPanel extends StatelessWidget {
  const RealtimeStatisticsPanel({
    super.key,
    this.uplink,
    this.downlink,
    this.networkQuality,
  });
  final UplinkVideoStatistics? uplink;
  final DownlinkVideoStatistics? downlink;
  final RealtimeNetworkQuality? networkQuality;
  String _value(int? value, [String unit = '']) =>
      value == null ? '--' : '$value${unit.isEmpty ? '' : ' $unit'}';
  String _size(int? width, int? height) =>
      width == null || height == null ? '--' : '$width × $height';
  String _quality(RealtimeNetworkQualityLevel? value) => XLabLocalization.shared
      .text('statistics.quality.${value?.name ?? 'unknown'}');

  @override
  Widget build(BuildContext context) {
    final t = XLabLocalization.shared.text;
    Widget heading(String key) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 3),
      child: Text(
        t('statistics.$key'),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
    Widget row(String key, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              t('statistics.$key'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xB3FFFFFF)),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      width: 216,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.48,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xA3000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            heading('uplink'),
            row('resolution', _size(uplink?.width, uplink?.height)),
            row('captureFPS', _value(uplink?.captureFrameRate, 'fps')),
            row('encodeFPS', _value(uplink?.encodeFrameRate, 'fps')),
            row('sendFPS', _value(uplink?.sendFrameRate, 'fps')),
            row('bitrate', _value(uplink?.bitrateKbps, 'kbps')),
            row('loss', _value(uplink?.packetLossPercent, '%')),
            row('quality', _quality(networkQuality?.uplink)),
            const SizedBox(height: 6),
            heading('downlink'),
            row('resolution', _size(downlink?.width, downlink?.height)),
            row('decodeFPS', _value(downlink?.decodeFrameRate, 'fps')),
            row('renderFPS', _value(downlink?.renderFrameRate, 'fps')),
            row('bitrate', _value(downlink?.bitrateKbps, 'kbps')),
            row('loss', _value(downlink?.packetLossPercent, '%')),
            row('quality', _quality(networkQuality?.downlink)),
            row('delay', _value(downlink?.endToEndDelayMs, 'ms')),
          ],
        ),
      ),
    );
  }
}
