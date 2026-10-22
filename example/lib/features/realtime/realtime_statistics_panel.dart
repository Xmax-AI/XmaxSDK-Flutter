import 'package:flutter/material.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import '../../localization/xlab_localization.dart';

/// 展示 SDK 统计与档位，档位切换由 SDK 负责执行。
class RealtimeStatisticsPanel extends StatelessWidget {
  const RealtimeStatisticsPanel({
    super.key,
    this.uplink,
    this.downlink,
    this.networkQuality,
    this.uplinkLevel,
    this.downlinkLevel,
    this.canAdjustQuality = false,
    this.isAdjustingQuality = false,
    this.qualityError,
    this.onUplinkLevelChanged,
    this.onDownlinkLevelChanged,
  });
  final UplinkVideoStatistics? uplink;
  final DownlinkVideoStatistics? downlink;
  final RealtimeNetworkQuality? networkQuality;
  final RealtimeQualityLevel? uplinkLevel;
  final RealtimeQualityLevel? downlinkLevel;
  final bool canAdjustQuality;
  final bool isAdjustingQuality;
  final String? qualityError;
  final ValueChanged<RealtimeQualityLevel>? onUplinkLevelChanged;
  final ValueChanged<RealtimeQualityLevel>? onDownlinkLevelChanged;
  String _value(int? value, [String unit = '']) =>
      value == null ? '--' : '$value${unit.isEmpty ? '' : ' $unit'}';
  String _size(int? width, int? height) =>
      width == null || height == null ? '--' : '$width × $height';
  String _quality(RealtimeNetworkQualityLevel? value) => XLabLocalization.shared
      .text('statistics.quality.${value?.name ?? 'unknown'}');

  @override
  Widget build(BuildContext context) {
    final t = XLabLocalization.shared.text;
    Widget levels(
      RealtimeQualityLevel? selected,
      ValueChanged<RealtimeQualityLevel>? onChanged,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          for (final level in RealtimeQualityLevel.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == level,
                enabled: canAdjustQuality && !isAdjustingQuality,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      canAdjustQuality &&
                          !isAdjustingQuality &&
                          onChanged != null
                      ? () => onChanged(level)
                      : null,
                  child: Container(
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected == level
                          ? const Color(0xFF007AFF)
                          : const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'L${level.value}',
                      style: TextStyle(
                        fontSize: 10,
                        color: canAdjustQuality ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
            row('level', uplinkLevel == null ? '--' : 'L${uplinkLevel!.value}'),
            levels(uplinkLevel, onUplinkLevelChanged),
            const SizedBox(height: 6),
            heading('downlink'),
            row('resolution', _size(downlink?.width, downlink?.height)),
            row('decodeFPS', _value(downlink?.decodeFrameRate, 'fps')),
            row('renderFPS', _value(downlink?.renderFrameRate, 'fps')),
            row('bitrate', _value(downlink?.bitrateKbps, 'kbps')),
            row('loss', _value(downlink?.packetLossPercent, '%')),
            row('quality', _quality(networkQuality?.downlink)),
            row('delay', _value(downlink?.endToEndDelayMs, 'ms')),
            row(
              'level',
              downlinkLevel == null ? '--' : 'L${downlinkLevel!.value}',
            ),
            levels(downlinkLevel, onDownlinkLevelChanged),
            if (isAdjustingQuality)
              Text(
                t('statistics.adjusting'),
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            if (qualityError != null)
              Text(
                qualityError!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.orangeAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
