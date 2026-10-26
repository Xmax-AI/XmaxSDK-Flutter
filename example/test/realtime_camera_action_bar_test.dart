import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_camera_action_bar.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  testWidgets('camera actions form a labeled vertical strip', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
    var statisticsTaps = 0;
    var cameraTaps = 0;
    var volumeTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: RealtimeCameraActionBar(
              cameraEnabled: false,
              formatEnabled: false,
              statisticsVisible: true,
              onSwitchCamera: () => cameraTaps++,
              onOpenCameraFormat: () =>
                  fail('Disabled format button was invoked'),
              onToggleStatistics: () => statisticsTaps++,
              onOpenAudioVolume: (_) => volumeTaps++,
            ),
          ),
        ),
      ),
    );

    final camera = find.byIcon(Icons.sync_rounded);
    final format = find.byIcon(Icons.aspect_ratio_rounded);
    final statistics = find.byIcon(Icons.bar_chart_rounded);
    expect(tester.getCenter(statistics).dx, tester.getCenter(camera).dx);
    expect(format, findsOneWidget);
    expect(tester.getCenter(format).dy - tester.getCenter(camera).dy, 62);
    expect(tester.getCenter(statistics).dy - tester.getCenter(camera).dy, 186);
    expect(
      tester.getSize(find.byType(RealtimeCameraActionBar)),
      const Size(58, 248),
    );
    expect(find.text('翻转'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('音量'), findsOneWidget);
    expect(find.text('比例'), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.tune_rounded)).dy -
          tester.getCenter(camera).dy,
      124,
    );
    expect(tester.widget<Icon>(statistics).color, const Color(0xFF007AFF));
    expect(tester.widget<Text>(find.text('统计')).style?.fontSize, 11);
    await tester.tap(camera);
    await tester.tap(format);
    await tester.tap(statistics);
    await tester.tap(find.text('音量'));
    expect(cameraTaps, 0);
    expect(statisticsTaps, 1);
    expect(volumeTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
