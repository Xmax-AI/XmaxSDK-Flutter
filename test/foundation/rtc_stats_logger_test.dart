import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcStatsLogger.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  setUp(XmaxLogger.reset);
  tearDown(XmaxLogger.reset);
  test(
    'statistics logs are localized and remain filtered by performance option',
    () {
      final messages = <String>[];
      XmaxLogger.configure(
        options: XmaxLoggerOption.all,
        environment: XmaxEnvironment.global,
      );
      XmaxLogger.setSink((_, message) => messages.add(message));
      RtcStatsLogger.logUplinkVideoStatistics(
        const UplinkVideoStatistics(
          width: 1024,
          height: 1920,
          captureFrameRate: 30,
          bitrateKbps: 1200,
        ),
      );
      expect(messages.single, contains('Resolution: 1024 × 1920'));
      expect(messages.single, contains('Capture Frame Rate: 30'));
      expect(
        RtcStatsLogger.networkQualityName(RealtimeNetworkQualityLevel.veryBad),
        'Very Bad',
      );
      XmaxLogger.configure(
        options: XmaxLoggerOption.business,
        environment: XmaxEnvironment.global,
      );
      RtcStatsLogger.logUplinkVideoStatistics(const UplinkVideoStatistics());
      expect(messages, hasLength(1));
    },
  );
}
