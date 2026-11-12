import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/app.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_page.dart';

import 'support/credit_balance_stub.dart';

void main() {
  for (final savedModel in [
    'x2.1',
    'x2.1-flash',
    'x2.1.1-preview-cn',
    'x2.1.1-preview-us',
    'x2.0',
    'unknown-model',
  ]) {
    final expectedModel = savedModel == 'x2.1-flash'
        ? RealtimeModel.x2_1_flash
        : RealtimeModel.x2_1;
    testWidgets(
      'XLab opens the camera with the restored model for $savedModel',
      (tester) async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData(<String, Object>{
              'xlab.language': 'en',
              'xlab.realtime.apiKey': 'test-key',
              'xlab.realtime.model': savedModel,
            });
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = null);

        await tester.pumpWidget(
          const XLabApp(creditBalanceQueryFactory: stubCreditBalanceQuery),
        );
        await tester.pumpAndSettle();
        expect(find.text('MODELS: 2'), findsOneWidget);
        final modelRow = find.byKey(
          ValueKey<String>('model-${expectedModel.value}'),
        );
        expect(
          find.descendant(
            of: modelRow,
            matching: find.text(expectedModel.displayName),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('preview'), findsNothing);

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
          expectedModel,
        );
      },
    );
  }
}
