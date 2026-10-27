import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/app.dart';

void main() {
  testWidgets('shows the supported capability entry points', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'xlab.realtime.apiKey': 'cached-api-key',
          'xlab.language': 'zh-Hans',
        });
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);
    await tester.pumpWidget(const XLabApp());
    await tester.pumpAndSettle();

    expect(find.text('XLAB'), findsOneWidget);
    expect(find.text('v1.1.0'), findsOneWidget);
    expect(find.text('Android 8.0+'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('latest-model-metric')),
        matching: find.text(RealtimeModel.values.last.displayName),
      ),
      findsOneWidget,
    );
    expect(find.text('X2.1.1'), findsNothing);
    final apiKeyField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('api-key-field')),
    );
    expect(apiKeyField.controller?.text, 'cached-api-key');
    expect(find.text('前往 Xmax 开放平台申请'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('api-key-field')),
      'updated-api-key',
    );
    await tester.pumpAndSettle();
    expect(
      await SharedPreferencesAsync().getString('xlab.realtime.apiKey'),
      'updated-api-key',
    );

    await tester.scrollUntilVisible(
      find.text('摄像头实时流'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('摄像头实时流'), findsOneWidget);
    expect(find.text('图片生成管线'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('存储服务'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('自定义轨迹渲染'), findsNothing);
    expect(find.text('外部采集'), findsOneWidget);
    expect(find.text('存储服务'), findsOneWidget);
  });
}
