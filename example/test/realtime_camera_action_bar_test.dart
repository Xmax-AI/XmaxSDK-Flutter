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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: RealtimeCameraActionBar(
              cameraEnabled: false,
              statisticsVisible: true,
              onSwitchCamera: () => cameraTaps++,
              onToggleStatistics: () => statisticsTaps++,
            ),
          ),
        ),
      ),
    );

    final camera = find.byIcon(Icons.sync_rounded);
    final format = find.byIcon(Icons.aspect_ratio_rounded);
    final statistics = find.byIcon(Icons.bar_chart_rounded);
    expect(tester.getCenter(statistics).dx, tester.getCenter(camera).dx);
    expect(format, findsNothing);
    expect(tester.getCenter(statistics).dy - tester.getCenter(camera).dy, 62);
    expect(
      tester.getSize(find.byType(RealtimeCameraActionBar)),
      const Size(58, 124),
    );
    expect(find.text('翻转'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(tester.widget<Icon>(statistics).color, const Color(0xFF007AFF));
    expect(tester.widget<Text>(find.text('统计')).style?.fontSize, 11);
    await tester.tap(camera);
    await tester.tap(statistics);
    expect(cameraTaps, 0);
    expect(statisticsTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
