import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_statistics_panel.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  for (final enabled in [false, true]) {
    testWidgets(
      'quality controls dispatch only while available (enabled=$enabled)',
      (tester) async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({});
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
        await XLabLocalization.shared.setLanguage(XLabLanguage.english);
        RealtimeQualityLevel? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RealtimeStatisticsPanel(
                uplinkLevel: RealtimeQualityLevel.l2,
                downlinkLevel: RealtimeQualityLevel.l3,
                canAdjustQuality: enabled,
                onUplinkLevelChanged: (value) => selected = value,
              ),
            ),
          ),
        );
        await tester.tap(find.text('L1').first);
        expect(selected, enabled ? RealtimeQualityLevel.l1 : isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'quality changes are disabled while a previous change is pending',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({});
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      await XLabLocalization.shared.setLanguage(XLabLanguage.english);
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RealtimeStatisticsPanel(
              canAdjustQuality: true,
              isAdjustingQuality: true,
              onUplinkLevelChanged: (_) => changes++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('L1').first);
      expect(changes, 0);
    },
  );

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
      expect(find.text('—'), findsWidgets);
      expect(tester.getSize(find.byType(RealtimeStatisticsPanel)).width, 184);
      expect(
        tester.getTopLeft(find.text('L1').first).dy,
        lessThan(tester.getTopLeft(find.text('Resolution').first).dy),
      );
      expect(find.text('Quality level'), findsNothing);
      expect(
        find.text(
          'L1 highest · L5 lowest. Automatic adaptation remains active.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected quality is not submitted again and buttons are 28 high',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({});
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      await XLabLocalization.shared.setLanguage(XLabLanguage.english);
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RealtimeStatisticsPanel(
              uplinkLevel: RealtimeQualityLevel.l2,
              canAdjustQuality: true,
              onUplinkLevelChanged: (_) => changes++,
            ),
          ),
        ),
      );
      final selected = find.ancestor(
        of: find.text('L2').first,
        matching: find.byType(GestureDetector),
      );
      expect(tester.getSize(selected).height, 28);
      await tester.tap(find.text('L2').first);
      expect(changes, 0);
      await tester.tap(find.text('L1').first);
      expect(changes, 1);
    },
  );

  testWidgets('panel fits available height and scrolls to its localized hint', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(height: 220, child: RealtimeStatisticsPanel()),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(RealtimeStatisticsPanel)),
      const Size(184, 220),
    );
    final hint = find.text('L1 最高 · L5 最低，手动调整后仍会自动调档。');
    await tester.ensureVisible(hint);
    await tester.pumpAndSettle();
    expect(hint.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
