import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/app.dart';
import 'package:xmax_sdk_example/features/storage/storage_page.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  testWidgets('follow system updates language and service environment', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'xlab.language': 'system',
        });
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    tester.binding.platformDispatcher.localeTestValue = const Locale('zh');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await XLabLocalization.shared.setLanguage(XLabLanguage.system);

    await tester.pumpWidget(const XLabApp());
    await tester.pumpAndSettle();
    expect(find.text('实时交互视频模型'), findsOneWidget);
    expect(XLabLocalization.shared.environment, XmaxEnvironment.china);
    expect(find.text('X2.1'), findsOneWidget);

    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    XLabLocalization.shared.systemLocaleDidChange();
    await tester.pumpAndSettle();
    expect(find.text('Realtime Interactive Video'), findsOneWidget);
    expect(XLabLocalization.shared.environment, XmaxEnvironment.global);
    expect(find.text('X2.1'), findsOneWidget);
  });

  for (final (language, savedModel) in [
    (XLabLanguage.english, RealtimeModel.x2_1),
    (XLabLanguage.simplifiedChinese, RealtimeModel.x2_1),
  ]) {
    testWidgets('model selection persists independently of ${language.name}', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform
          .instance = InMemorySharedPreferencesAsync.withData(<String, Object>{
        'xlab.language': language == XLabLanguage.english ? 'en' : 'zh-Hans',
        'xlab.realtime.model': savedModel.value,
      });
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
      await XLabLocalization.shared.setLanguage(language);
      await tester.pumpWidget(const XLabApp());
      await tester.pumpAndSettle();

      void expectSelected(RealtimeModel model) {
        for (final item in RealtimeModel.values) {
          expect(find.text(item.displayName), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(ValueKey<String>('model-${item.value}')),
              matching: find.text(
                XLabLocalization.shared.text('feed.selected'),
              ),
            ),
            item == model ? findsOneWidget : findsNothing,
          );
        }
        expect(
          find.text(
            XLabLocalization.shared.formatCount(
              'feed.model.count',
              RealtimeModel.values.length,
            ),
          ),
          findsOneWidget,
        );
      }

      expectSelected(savedModel);
      final row = find.byKey(ValueKey<String>('model-${savedModel.value}'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expectSelected(savedModel);
      expect(
        await SharedPreferencesAsync().getString('xlab.realtime.model'),
        savedModel.value,
      );

      await XLabLocalization.shared.setLanguage(
        language == XLabLanguage.english
            ? XLabLanguage.simplifiedChinese
            : XLabLanguage.english,
      );
      await tester.pumpAndSettle();
      expectSelected(savedModel);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const XLabApp());
      await tester.pumpAndSettle();
      expectSelected(savedModel);
    });
  }

  testWidgets(
    'language selection translates the home page and selects region',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'xlab.language': 'en',
            'xlab.realtime.apiKey': 'cached-api-key',
          });
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);

      await tester.pumpWidget(const XLabApp());
      await tester.pumpAndSettle();

      expect(find.text('Realtime Interactive Video'), findsOneWidget);
      expect(find.text('Get One At Xmax Open Platform'), findsOneWidget);
      expect(XLabLocalization.shared.environment, XmaxEnvironment.global);
      expect(
        XLabLocalization.shared.apiKeyApplicationURL.host,
        'platform.xmax.ai',
      );

      await tester.tap(find.byKey(const ValueKey<String>('language-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<XLabLanguage> &&
              widget.value == XLabLanguage.simplifiedChinese,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('实时交互视频模型'), findsOneWidget);
      expect(find.text('前往 Xmax 开放平台申请'), findsOneWidget);
      expect(XLabLocalization.shared.environment, XmaxEnvironment.china);
      expect(
        await SharedPreferencesAsync().getString('xlab.language'),
        'zh-Hans',
      );

      await tester.scrollUntilVisible(
        find.text('存储服务'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('存储服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('存储服务'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StoragePage>(find.byType(StoragePage)).environment,
        XmaxEnvironment.china,
      );

      Navigator.of(tester.element(find.byType(StoragePage))).pop();
      await tester.pumpAndSettle();
      await XLabLocalization.shared.setLanguage(XLabLanguage.english);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Storage Service'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Storage Service'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Storage Service'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StoragePage>(find.byType(StoragePage)).environment,
        XmaxEnvironment.global,
      );
      expect(find.text('Storage Service'), findsOneWidget);
      expect(find.text('File Preview'), findsOneWidget);
    },
  );
}
