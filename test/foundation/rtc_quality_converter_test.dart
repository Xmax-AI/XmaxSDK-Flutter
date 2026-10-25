import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcQualityConverter.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test(
    'uplink conversion distinguishes dimensions, rates, bitrate, and loss',
    () {
      final value = RtcQualityConverter.uplinkVideoStatistics(
        const LocalVideoStats(
          encodedFrameWidth: 0,
          encodedFrameHeight: 1920,
          captureFrameRate: 30,
          encoderOutputFrameRate: 24,
          sentFrameRate: 20,
          sentBitrate: 1800,
          txPacketLossRate: 0,
        ),
      );
      expect(value.width, isNull);
      expect(value.height, 1920);
      expect(value.captureFrameRate, 30);
      expect(value.encodeFrameRate, 24);
      expect(value.sendFrameRate, 20);
      expect(value.bitrateKbps, 1800);
      expect(value.packetLossPercent, 0);
    },
  );

  test(
    'downlink conversion discards invalid measurements and preserves zeros',
    () {
      final value = RtcQualityConverter.downlinkVideoStatistics(
        userID: 'bot',
        stats: const RemoteVideoStats(
          width: -1,
          height: 1024,
          decoderOutputFrameRate: -1,
          rendererOutputFrameRate: 0,
          receivedBitrate: 0,
          packetLossRate: 101,
          e2eDelay: 0,
        ),
      );
      expect(value.userID, 'bot');
      expect(value.width, isNull);
      expect(value.height, 1024);
      expect(value.decodeFrameRate, isNull);
      expect(value.renderFrameRate, 0);
      expect(value.bitrateKbps, 0);
      expect(value.packetLossPercent, isNull);
      expect(value.endToEndDelayMs, 0);
    },
  );

  test(
    'native quality levels map without treating unknown samples as good',
    () {
      expect(
        RtcQualityConverter.quality(QualityType.qualityBad),
        RealtimeNetworkQualityLevel.bad,
      );
      expect(
        RtcQualityConverter.quality(QualityType.qualityGood),
        RealtimeNetworkQualityLevel.good,
      );
      expect(
        RtcQualityConverter.quality(QualityType.qualityUnknown),
        RealtimeNetworkQualityLevel.unknown,
      );
    },
  );

  test(
    'performance suggestions require valid encoded dimensions and frame rate',
    () {
      expect(
        RtcQualityConverter.performanceAlarm(const LocalVideoStats()),
        isNull,
      );
      final limited = RtcQualityConverter.performanceAlarm(
        const LocalVideoStats(
          encodedFrameWidth: 832,
          encodedFrameHeight: 1472,
          encoderOutputFrameRate: 24,
          qualityAdaptIndication: QualityAdaptIndication.adaptDownBandwidth,
        ),
      )!;
      expect(limited.status, RealtimePerformanceStatus.limited);
      expect(limited.suggestedVideoFormat!.width, 832);
      expect(limited.suggestedVideoFormat!.fps, 24);
      final recovered = RtcQualityConverter.performanceAlarm(
        const LocalVideoStats(
          encodedFrameWidth: 0,
          qualityAdaptIndication: QualityAdaptIndication.adaptUpBandwidth,
        ),
      )!;
      expect(recovered.status, RealtimePerformanceStatus.recovered);
      expect(recovered.suggestedVideoFormat, isNull);
    },
  );
}
