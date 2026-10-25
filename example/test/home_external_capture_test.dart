import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/home/home_page.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_local_input.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_page.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

void main() {
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'xlab.realtime.apiKey': 'test-key',
        });
    await XLabLocalization.shared.setLanguage(XLabLanguage.english);
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  for (final cancelled in [false, true]) {
    testWidgets(
      cancelled
          ? 'cancelling external video selection stays on the home page'
          : 'external capture passes the selected video instead of camera input',
      (tester) async {
        final observer = _RouteObserver();
        var selections = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: HomePage(
              pickVideo: () async {
                selections++;
                return cancelled ? null : XFile('/tmp/external.mp4');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.text(
          XLabLocalization.shared.text('feed.external.title'),
        );
        await tester.scrollUntilVisible(
          card,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.idle();

        expect(selections, 1);
        if (cancelled) {
          expect(observer.routes, hasLength(1));
        } else {
          expect(observer.routes, hasLength(2));
          final route = observer.routes.last as MaterialPageRoute<void>;
          // Inspect the destination before mounting native media resources.
          final page =
              route.builder(tester.element(find.byType(HomePage)))
                  as RealtimePage;
          expect(page.apiKey, 'test-key');
          expect(page.model, RealtimeModel.x2_1_1_preview_cn);
          expect(page.environment, XmaxEnvironment.global);
          expect(page.localInput, isA<XLabRealtimeExternalVideoInput>());
          final input = page.localInput! as XLabRealtimeExternalVideoInput;
          expect(input.path, '/tmp/external.mp4');
          expect(input.name, 'external.mp4');
          route.navigator!.removeRoute(route);
        }
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    super.didPush(route, previousRoute);
  }
}
