import 'package:flutter/material.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import '../../localization/xlab_localization.dart';

/// Displays SDK statistics and transport quality controls.
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
      value == null ? '—' : '$value${unit.isEmpty ? '' : ' $unit'}';
  String _size(int? width, int? height) =>
      width == null || height == null ? '—' : '$width × $height';
  String _quality(RealtimeNetworkQualityLevel? value) =>
      value == null || value == RealtimeNetworkQualityLevel.unknown
      ? '—'
      : XLabLocalization.shared.text('statistics.quality.${value.name}');

  @override
  Widget build(BuildContext context) {
    final t = XLabLocalization.shared.text;
    Widget levels(
      String direction,
      RealtimeQualityLevel? selected,
      ValueChanged<RealtimeQualityLevel>? onChanged,
    ) => Opacity(
      opacity: canAdjustQuality && !isAdjustingQuality ? 1 : 0.5,
      child: Row(
        spacing: 3,
        children: [
          for (final level in RealtimeQualityLevel.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == level,
                label: '${t('statistics.$direction')} L${level.value}',
                enabled:
                    canAdjustQuality &&
                    !isAdjustingQuality &&
                    selected != level,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      canAdjustQuality &&
                          !isAdjustingQuality &&
                          selected != level &&
                          onChanged != null
                      ? () => onChanged(level)
                      : null,
                  child: Container(
                    alignment: Alignment.center,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected == level
                          ? const Color(0xFF007AFF)
                          : const Color(0x26FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'L${level.value}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    Widget heading(String key) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 15),
      child: Text(
        t('statistics.$key'),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
    Widget row(String key, String value) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 14),
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
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                fontFeatures: [FontFeature.tabularFigures()],
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      width: 184,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xA3000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            heading('uplink'),
            levels('uplink', uplinkLevel, onUplinkLevelChanged),
            row('resolution', _size(uplink?.width, uplink?.height)),
            row('captureFPS', _value(uplink?.captureFrameRate, 'fps')),
            row('encodeFPS', _value(uplink?.encodeFrameRate, 'fps')),
            row('sendFPS', _value(uplink?.sendFrameRate, 'fps')),
            row('bitrate', _value(uplink?.bitrateKbps, 'kbps')),
            row('loss', _value(uplink?.packetLossPercent, '%')),
            row('quality', _quality(networkQuality?.uplink)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: heading('downlink'),
            ),
            levels('downlink', downlinkLevel, onDownlinkLevelChanged),
            row('resolution', _size(downlink?.width, downlink?.height)),
            row('decodeFPS', _value(downlink?.decodeFrameRate, 'fps')),
            row('renderFPS', _value(downlink?.renderFrameRate, 'fps')),
            row('bitrate', _value(downlink?.bitrateKbps, 'kbps')),
            row('loss', _value(downlink?.packetLossPercent, '%')),
            row('quality', _quality(networkQuality?.downlink)),
            row('delay', _value(downlink?.endToEndDelayMs, 'ms')),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('statistics.level.hint'),
                style: const TextStyle(fontSize: 9, color: Color(0x99FFFFFF)),
              ),
            ),
            if (qualityError != null)
              Text(
                qualityError!,
                style: const TextStyle(fontSize: 10, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}
