import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_media_top_bar.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  testWidgets(
    'external controls use labeled 48 by 50 buttons and omit camera actions',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({});
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
      var mute = 0, statistics = 0, gallery = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topRight,
              child: RealtimeMediaTopBar(
                enabled: false,
                isMuted: false,
                statisticsVisible: true,
                onGallery: () => gallery++,
                onMute: () => mute++,
                onVolume: (_) {},
                onStatistics: () => statistics++,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(RealtimeMediaTopBar)),
        const Size(192, 50),
      );
      expect(find.text('统计'), findsOneWidget);
      expect(find.text('音量'), findsOneWidget);
      expect(find.text('相册'), findsOneWidget);
      expect(find.text('翻转'), findsNothing);
      await tester.tap(find.text('相册'));
      await tester.tap(find.text('声音'));
      await tester.tap(find.text('统计'));
      expect(gallery, 0);
      expect(mute, 1);
      expect(statistics, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
