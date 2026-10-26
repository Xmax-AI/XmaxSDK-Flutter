import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/LocalStream.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcQualityListener.dart';
import 'package:xmax_sdk/src/stream/quality/QualityController.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  const sample = RealtimeNetworkQuality(
    uplink: RealtimeNetworkQualityLevel.bad,
    downlink: RealtimeNetworkQualityLevel.good,
  );
  test(
    'quality registers separately and runs adaptation before public callbacks',
    () {
      final rtc = _Rtc();
      var now = 5.0;
      final quality = QualityController(
        rtcManager: rtc,
        monotonicTime: () => now,
      );
      expect(rtc.quality, same(quality));
      final calls = <String>[];
      quality.setAdaptiveQualityListener((value, sampledAt) {
        expect(value, sample);
        expect(sampledAt, 5);
        calls.add('internal');
      });
      quality.setNetworkQualityListener((value) {
        calls.add('public');
        now = 100;
        throw StateError('Application callback failed');
      });
      expect(() => rtc.quality!.onNetworkQuality(sample), returnsNormally);
      expect(calls, ['internal', 'public']);
    },
  );

  test(
    'throwing internal, performance, and statistics observers cannot block other notifications',
    () {
      final quality = QualityController();
      var publicCalls = 0;
      quality.setAdaptiveQualityListener((_, _) => throw StateError('failed'));
      quality.setNetworkQualityListener((_) => publicCalls++);
      quality.onNetworkQuality(sample);
      expect(publicCalls, 1);
      quality.setUplinkVideoStatisticsListener(
        (_) => throw StateError('failed'),
      );
      quality.setDownlinkVideoStatisticsListener(
        (_) => throw StateError('failed'),
      );
      quality.setPerformanceAlarmListener((_) => throw StateError('failed'));
      expect(
        () => quality.setUplinkVideoStatisticsEnabled(true),
        returnsNormally,
      );
      expect(
        () => quality.setDownlinkVideoStatisticsUser('bot'),
        returnsNormally,
      );
      expect(
        () => quality.onUplinkVideoStatistics(const UplinkVideoStatistics()),
        returnsNormally,
      );
      expect(
        () => quality.onDownlinkVideoStatistics(
          const DownlinkVideoStatistics(userID: 'bot'),
        ),
        returnsNormally,
      );
      expect(
        () => quality.onPerformanceAlarm(
          const RealtimePerformanceAlarm(
            status: RealtimePerformanceStatus.limited,
          ),
        ),
        returnsNormally,
      );
    },
  );

  test(
    'statistics availability and result ownership are managed by quality',
    () {
      final quality = QualityController();
      final uplink = <UplinkVideoStatistics?>[];
      final downlink = <DownlinkVideoStatistics?>[];
      quality.setUplinkVideoStatisticsListener(uplink.add);
      quality.setDownlinkVideoStatisticsListener(downlink.add);
      const up = UplinkVideoStatistics(width: 1024, height: 1920);
      const first = DownlinkVideoStatistics(userID: 'first', width: 512);
      const second = DownlinkVideoStatistics(userID: 'second', width: 768);
      quality.onUplinkVideoStatistics(up);
      quality.onDownlinkVideoStatistics(first);
      expect(uplink, isEmpty);
      expect(downlink, isEmpty);
      quality.setUplinkVideoStatisticsEnabled(true);
      quality.onUplinkVideoStatistics(up);
      quality.setUplinkVideoStatisticsEnabled(false);
      quality.onUplinkVideoStatistics(up);
      expect(uplink, [null, up, null]);
      quality.setDownlinkVideoStatisticsUser('first');
      quality.onDownlinkVideoStatistics(first);
      quality.setDownlinkVideoStatisticsUser('second');
      quality.onDownlinkVideoStatistics(first);
      quality.onDownlinkVideoStatistics(second);
      quality.setDownlinkVideoStatisticsUser(null);
      quality.onDownlinkVideoStatistics(second);
      expect(downlink, [null, first, null, second, null]);
    },
  );

  test('reset stops adaptation but retains public quality receivers', () {
    final quality = QualityController();
    var internal = 0, external = 0;
    quality.setAdaptiveQualityListener((_, _) => internal++);
    quality.setNetworkQualityListener((_) => external++);
    quality.onNetworkQuality(sample);
    quality.resetQuality();
    quality.onNetworkQuality(sample);
    expect(internal, 1);
    expect(external, 2);
  });

  test(
    'delayed samples are evaluated against processing time instead of their own timestamp',
    () async {
      final quality = QualityController();
      await quality.prepareQuality(
        baseline: RealtimeModel.x2_1.defaultCameraVideoFormat,
        model: 'test',
        isAdaptiveQualityEnabled: false,
      );
      for (var time = 1.0; time <= 4; time++) {
        final result = quality.proposeQuality(sample, time, currentTime: 20);
        expect(result.uplink, isNull);
      }
      expect(
        quality.qualityConfiguration!.uplinkLevel,
        RealtimeQualityLevel.l1,
      );
    },
  );
}

class _Rtc implements RtcManaging {
  @override
  LocalStream get localStream => const LocalStream();

  RtcQualityListener? quality;
  @override
  void setQualityListener(RtcQualityListener? listener) => quality = listener;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
