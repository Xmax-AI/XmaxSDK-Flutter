import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/app.dart';
import 'package:xmax_sdk_example/features/home/feed_credit_balance.dart';
import 'package:xmax_sdk_example/features/home/feed_credit_balance_pill.dart';
import 'package:xmax_sdk_example/features/home/home_page.dart';
import 'package:xmax_sdk_example/features/storage/storage_page.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';
import 'package:xmax_sdk_example/ui/xlab_theme.dart';

const _pillKey = ValueKey('feed.creditBalance');
const _inputKey = ValueKey<String>('api-key-field');

void _lifecycle(WidgetTester tester, AppLifecycleState target) {
  final binding = tester.binding;
  const states = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ];
  if (binding.lifecycleState == null ||
      binding.lifecycleState == AppLifecycleState.detached) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  final start = states.indexOf(binding.lifecycleState!);
  final end = states.indexOf(target);
  if (start == end) return;
  final step = start < end ? 1 : -1;
  for (var i = start + step; i != end + step; i += step) {
    binding.handleAppLifecycleStateChanged(states[i]);
  }
}

Future<void> _tick(
  WidgetTester tester, [
  Duration duration = Duration.zero,
]) async {
  await tester.pump(duration);
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  _Queries queries, {
  String apiKey = 'key',
}) async {
  await SharedPreferencesAsync().setString('xlab.realtime.apiKey', apiKey);
  await tester.pumpWidget(
    XLabApp(creditBalanceQueryFactory: queries.makeQuery),
  );
  await _tick(tester);
}

Finder _value(String value) =>
    find.descendant(of: find.byKey(_pillKey), matching: find.text(value));

Semantics _semantics(WidgetTester tester) =>
    tester.widget<Semantics>(find.byKey(_pillKey));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'xlab.language': 'en',
          'xlab.realtime.apiKey': 'key',
        });
    await XLabLocalization.shared.setLanguage(XLabLanguage.english);
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  testWidgets(
    'credits appear at the right of the API key header and load after the edit debounce',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final response = Completer<double>();
      final queries = _Queries()..fetch = (_, _) => response.future;
      await _mount(tester, queries, apiKey: ' key \n');
      expect(_value('—'), findsOneWidget);
      await _tick(tester, const Duration(milliseconds: 249));
      expect(queries.calls, isEmpty);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(queries.calls, [
        (key: 'key', environment: XmaxEnvironment.global),
      ]);
      expect(find.byKey(const ValueKey('feed-credit-loading')), findsOneWidget);
      expect(_semantics(tester).properties.value, 'Loading');
      final apiLabel = tester.getRect(find.text('API KEY'));
      final pill = tester.getRect(find.byKey(_pillKey));
      expect(pill.center.dy, closeTo(apiLabel.center.dy, 0.1));
      expect(pill.left, greaterThan(apiLabel.right));
      expect(pill.height, 26);
      response.complete(1250.75);
      await _tick(tester);
      expect(_value('1,250.75'), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-credit-loading')), findsNothing);
      expect(_semantics(tester).properties.label, 'Credits');
      expect(_semantics(tester).properties.value, '1,250.75');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'API key edits query only the final nonempty key and clearing hides the old balance',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final queries = _Queries();
      await _mount(tester, queries, apiKey: '');
      await _tick(tester, const Duration(seconds: 10));
      expect(queries.calls, isEmpty);
      await tester.enterText(find.byKey(_inputKey), 'a');
      await _tick(tester, const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(_inputKey), 'ab');
      await _tick(tester, const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(_inputKey), ' final-key \n');
      await _tick(tester, const Duration(milliseconds: 249));
      expect(queries.calls, isEmpty);
      await _tick(tester, const Duration(milliseconds: 1));
      expect(queries.calls.single.key, 'final-key');
      expect(
        await SharedPreferencesAsync().getString('xlab.realtime.apiKey'),
        ' final-key ',
      );
      expect(_value('1,250.75'), findsOneWidget);
      await tester.enterText(find.byKey(_inputKey), ' \n ');
      await _tick(tester, const Duration(seconds: 10));
      expect(_value('—'), findsOneWidget);
      expect(queries.calls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late preferences never replace a newly entered API key or query its old account',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final preferences = _DelayedPreferences();
      SharedPreferencesAsyncPlatform.instance = preferences;
      final queries = _Queries();
      await tester.pumpWidget(
        XLabApp(creditBalanceQueryFactory: queries.makeQuery),
      );
      await _tick(tester);
      await tester.enterText(find.byKey(_inputKey), 'new-key');
      preferences.storedKey.complete('cached-key');
      await _tick(tester, const Duration(milliseconds: 250));
      expect(
        tester.widget<TextField>(find.byKey(_inputKey)).controller!.text,
        'new-key',
      );
      expect(queries.calls.single.key, 'new-key');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mounting an inactive homepage waits until the app becomes active',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.inactive);
      final queries = _Queries();
      await _mount(tester, queries);
      await _tick(tester, const Duration(seconds: 10));
      expect(queries.calls, isEmpty);
      _lifecycle(tester, AppLifecycleState.resumed);
      await _tick(tester, const Duration(milliseconds: 250));
      expect(queries.calls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed refresh keeps the displayed balance, marks it stale, and recovers on the next poll',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final queries = _Queries();
      await _mount(tester, queries);
      await _tick(tester, const Duration(milliseconds: 250));
      queries.fetch = (_, _) async => throw StateError('offline');
      await _tick(tester, const Duration(seconds: 5));
      expect(_value('1,250.75'), findsOneWidget);
      expect(
        tester.widget<Text>(_value('1,250.75')).style?.color,
        XLabPalette.orange,
      );
      expect(_semantics(tester).properties.hint, 'Unable to refresh credits.');
      expect(find.text('Unable to refresh credits.'), findsNothing);
      queries.fetch = (_, _) async => 0;
      await _tick(tester, const Duration(seconds: 5));
      expect(_value('0'), findsOneWidget);
      expect(tester.widget<Text>(_value('0')).style?.color, XLabPalette.mint);
      expect(_semantics(tester).properties.hint, isNull);
      expect(queries.factories, hasLength(1));
      expect(queries.calls, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'changing language clears the previous environment and rejects its late response',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final old = Completer<double>();
      final queries = _Queries()
        ..fetch = (_, environment) => environment == XmaxEnvironment.global
            ? old.future
            : Future.value(42.5);
      await _mount(tester, queries);
      await _tick(tester, const Duration(milliseconds: 250));
      await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
      await _tick(tester);
      expect(_value('—'), findsOneWidget);
      expect(_semantics(tester).properties.label, '积分');
      await _tick(tester, const Duration(milliseconds: 250));
      expect(_value('42.5'), findsOneWidget);
      old.complete(999);
      await _tick(tester);
      expect(_value('42.5'), findsOneWidget);
      expect(queries.calls.map((request) => request.environment), [
        XmaxEnvironment.global,
        XmaxEnvironment.china,
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final backgroundState in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    testWidgets(
      '${backgroundState.name} pauses polling and resuming refreshes the visible homepage',
      (tester) async {
        _lifecycle(tester, AppLifecycleState.resumed);
        final queries = _Queries();
        await _mount(tester, queries);
        await _tick(tester, const Duration(milliseconds: 250));
        expect(queries.calls, hasLength(1));
        _lifecycle(tester, backgroundState);
        await _tick(tester, const Duration(seconds: 30));
        expect(queries.calls, hasLength(1));
        expect(_value('1,250.75'), findsOneWidget);
        _lifecycle(tester, AppLifecycleState.resumed);
        await _tick(tester, const Duration(milliseconds: 249));
        expect(queries.calls, hasLength(1));
        await _tick(tester, const Duration(milliseconds: 1));
        expect(queries.calls, hasLength(2));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'leaving the homepage stops polling and returning refreshes even after backgrounding another page',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final queries = _Queries();
      await _mount(tester, queries);
      await _tick(tester, const Duration(milliseconds: 250));
      await tester.scrollUntilVisible(
        find.text('Storage Service'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Storage Service'));
      await tester.pumpAndSettle();
      final count = queries.calls.length;
      await tester.tap(find.text('Storage Service'));
      await tester.pumpAndSettle();
      expect(find.byType(StoragePage), findsOneWidget);
      _lifecycle(tester, AppLifecycleState.paused);
      await _tick(tester, const Duration(seconds: 10));
      _lifecycle(tester, AppLifecycleState.resumed);
      await _tick(tester, const Duration(seconds: 10));
      expect(queries.calls, hasLength(count));
      Navigator.of(tester.element(find.byType(StoragePage))).pop();
      await tester.pumpAndSettle();
      await _tick(tester, const Duration(milliseconds: 250));
      expect(queries.calls, hasLength(count + 1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'external media selection pauses polling and cancelling resumes it',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final selection = Completer<XFile?>();
      final queries = _Queries();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            pickVideo: () => selection.future,
            creditBalanceQueryFactory: queries.makeQuery,
          ),
        ),
      );
      await _tick(tester, const Duration(milliseconds: 250));
      await _tick(tester, const Duration(milliseconds: 250));
      await tester.scrollUntilVisible(
        find.text('External Capture'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('External Capture'));
      await tester.pumpAndSettle();
      final count = queries.calls.length;
      await tester.tap(find.text('External Capture'));
      await _tick(tester, const Duration(seconds: 20));
      expect(queries.calls, hasLength(count));
      selection.complete(null);
      await _tick(tester);
      await _tick(tester, const Duration(milliseconds: 250));
      expect(queries.calls, hasLength(count + 1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disposal during a query ignores late results and stops all updates',
    (tester) async {
      _lifecycle(tester, AppLifecycleState.resumed);
      final response = Completer<double>();
      final queries = _Queries()..fetch = (_, _) => response.future;
      await _mount(tester, queries);
      await _tick(tester, const Duration(milliseconds: 250));
      await tester.pumpWidget(const SizedBox());
      response.complete(999);
      await _tick(tester, const Duration(seconds: 20));
      expect(queries.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final (language, label, unavailable, hint) in [
    (
      XLabLanguage.english,
      'Credits',
      'Unavailable',
      'Unable to refresh credits.',
    ),
    (XLabLanguage.simplifiedChinese, '积分', '不可用', '积分刷新失败。'),
  ]) {
    testWidgets(
      'credit loading and unavailable states are localized in ${language.name}',
      (tester) async {
        await XLabLocalization.shared.setLanguage(language);
        Future<void> show(FeedCreditBalanceState state) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: FeedCreditBalancePill(state: state)),
            ),
          ),
        );
        await show(const FeedCreditBalanceState());
        expect(_value('—'), findsOneWidget);
        expect(_semantics(tester).properties.label, label);
        await show(const FeedCreditBalanceState(isLoading: true));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          _semantics(tester).properties.value,
          language == XLabLanguage.english ? 'Loading' : '加载中',
        );
        await show(const FeedCreditBalanceState(refreshFailed: true));
        expect(_value(unavailable), findsOneWidget);
        expect(_semantics(tester).properties.hint, hint);
        expect(
          tester.widget<Text>(_value(unavailable)).style?.color,
          XLabPalette.orange,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'credit pill fits a narrow layout and enlarged text without overflow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Center(
                child: SizedBox(
                  width: 160,
                  child: FeedCreditBalancePill(
                    state: FeedCreditBalanceState(balance: 1234567890.123456),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

typedef _Account = ({String key, XmaxEnvironment environment});

final class _Queries {
  final calls = <_Account>[];
  final factories = <_Account>[];
  Future<double> Function(String, XmaxEnvironment)? fetch;

  FeedCreditBalanceQuery makeQuery(String key, XmaxEnvironment environment) {
    factories.add((key: key, environment: environment));
    return () {
      calls.add((key: key, environment: environment));
      return fetch?.call(key, environment) ?? Future.value(1250.75);
    };
  }
}

final class _DelayedPreferences extends InMemorySharedPreferencesAsync {
  _DelayedPreferences() : super.withData({'xlab.language': 'en'});

  final storedKey = Completer<String?>();

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) {
    if (key == 'xlab.realtime.apiKey') return storedKey.future;
    return super.getString(key, options);
  }
}
