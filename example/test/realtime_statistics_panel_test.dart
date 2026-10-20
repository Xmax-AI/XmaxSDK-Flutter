import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_statistics_panel.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  testWidgets(
    'statistics display SDK values and localized empty placeholders',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({});
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      await XLabLocalization.shared.setLanguage(XLabLanguage.english);
      await tester.pumpWidget(
        const MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RealtimeStatisticsPanel(
              uplink: UplinkVideoStatistics(
                width: 1024,
                height: 1920,
                captureFrameRate: 30,
                bitrateKbps: 1800,
              ),
              downlink: DownlinkVideoStatistics(
                userID: 'bot',
                width: 800,
                height: 1500,
                renderFrameRate: 24,
                endToEndDelayMs: 200,
              ),
              networkQuality: RealtimeNetworkQuality(
                uplink: RealtimeNetworkQualityLevel.good,
                downlink: RealtimeNetworkQualityLevel.poor,
              ),
            ),
          ),
        ),
      );
      expect(find.text('1024 × 1920'), findsOneWidget);
      expect(find.text('800 × 1500'), findsOneWidget);
      expect(find.text('30 fps'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('--'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
