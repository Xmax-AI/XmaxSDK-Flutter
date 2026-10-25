import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final modelRow = find.byKey(
      const ValueKey<String>('model-x2.1.1-preview-us'),
    );
    expect(
      tester
          .widget<Semantics>(
            find.ancestor(of: modelRow, matching: find.byType(Semantics)).first,
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'retired model fallback retains the full catalog and camera uses the selected model',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'xlab.language': 'en',
            'xlab.realtime.apiKey': 'test-key',
            'xlab.realtime.model': 'x2.1',
          });
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);

      await tester.pumpWidget(const XLabApp());
      await tester.pumpAndSettle();
      expect(find.text('MODELS: 2'), findsOneWidget);
      expect(find.text('X2.0 PRO'), findsNothing);
      expect(find.text('X2.1.1-preview-cn'), findsOneWidget);
      expect(find.text('X2.1.1-preview-us'), findsOneWidget);

      final defaultRow = find.byKey(
        const ValueKey<String>('model-x2.1.1-preview-cn'),
      );
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(of: defaultRow, matching: find.byType(Semantics))
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );

      final modelRow = find.byKey(
        const ValueKey<String>('model-x2.1.1-preview-us'),
      );
      await tester.ensureVisible(modelRow);
      await tester.pumpAndSettle();
      await tester.tap(modelRow);
      await tester.pump();
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(of: modelRow, matching: find.byType(Semantics))
                  .first,
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
