import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_media_top_bar.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_video_recorder.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  testWidgets(
    'recording uses a red stop button and disables saving transitions',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({});
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
      var taps = 0;
      for (final state in [
        RealtimeRecordingState.recording,
        RealtimeRecordingState.saving,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Align(
                alignment: Alignment.topRight,
                child: RealtimeMediaTopBar(
                  enabled: true,
                  isMuted: false,
                  statisticsVisible: false,
                  recordingState: state,
                  onRecording: () => taps++,
                  onGallery: () {},
                  onMute: () {},
                  onVolume: (_) {},
                  onStatistics: () {},
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(RealtimeMediaTopBar)),
          const Size(240, 50),
        );
        if (state == RealtimeRecordingState.recording) {
          expect(
            tester.widget<Icon>(find.byIcon(Icons.stop_circle_outlined)).color,
            const Color(0xFFFF3B30),
          );
          await tester.tap(find.text('停止'));
        } else {
          await tester.tap(find.text('保存中'));
        }
      }
      expect(taps, 1);
    },
  );
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
