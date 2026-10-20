import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/app.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_page.dart';

void main() {
  testWidgets('XLab restores the saved model', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'xlab.language': 'en',
          'xlab.realtime.model': 'x2.1.1-preview-us',
        });
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);

    await tester.pumpWidget(const XLabApp());
    await tester.pumpAndSettle();
    final proRow = find.byKey(
      const ValueKey<String>('model-x2.1.1-preview-us'),
    );
    expect(
      tester
          .widget<Semantics>(
            find.ancestor(of: proRow, matching: find.byType(Semantics)).first,
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'XLab persists x2.1.1-preview-us and passes it to the realtime page',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'xlab.language': 'en',
            'xlab.realtime.apiKey': 'test-key',
          });
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);

      await tester.pumpWidget(const XLabApp());
      await tester.pumpAndSettle();
      expect(find.text('MODELS: 2'), findsOneWidget);
      expect(find.text('X2.0 PRO'), findsNothing);
      expect(find.text('X2.1.1-preview-us'), findsOneWidget);

      final proRow = find.byKey(
        const ValueKey<String>('model-x2.1.1-preview-us'),
      );
      await tester.tap(proRow);
      await tester.pump();
      expect(
        await SharedPreferencesAsync().getString('xlab.realtime.model'),
        'x2.1.1-preview-us',
      );
      expect(
        tester
            .widget<Semantics>(
              find.ancestor(of: proRow, matching: find.byType(Semantics)).first,
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.scrollUntilVisible(
        find.text('Live Camera'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Live Camera'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<RealtimePage>(find.byType(RealtimePage)).model,
        RealtimeModel.x2_1_1_preview_us,
      );
    },
  );
}
