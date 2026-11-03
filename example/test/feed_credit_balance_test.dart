import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/home/feed_credit_balance.dart';

void main() {
  test(
    'credit formatting preserves zero and fractions with a stable decimal locale',
    () {
      for (final (balance, expected) in <(double?, String)>[
        (null, '—'),
        (0, '0'),
        (0.25, '0.25'),
        (12, '12'),
        (1250.75, '1,250.75'),
        (0.1234567, '0.123457'),
        (1234567.123456, '1,234,567.123456'),
      ]) {
        expect(formatFeedCreditBalance(balance), expected);
      }
    },
  );

  testWidgets('empty keys and hidden pages never query credits', (
    tester,
  ) async {
    final poller = FeedCreditBalancePoller(
      makeQuery: (_, _) => throw StateError('Unexpected query'),
    );
    addTearDown(poller.dispose);
    poller.update(
      apiKey: ' \n ',
      environment: XmaxEnvironment.china,
      isActive: true,
    );
    await tester.pump(const Duration(seconds: 10));
    poller.update(
      apiKey: 'key',
      environment: XmaxEnvironment.china,
      isActive: false,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(poller.state, const FeedCreditBalanceState());
  });

  testWidgets(
    'edits debounce for 250 ms and polls reuse one query every five seconds',
    (tester) async {
      final accounts = <(String, XmaxEnvironment)>[];
      var calls = 0;
      final poller = FeedCreditBalancePoller(
        makeQuery: (key, environment) {
          accounts.add((key, environment));
          return () async => ++calls / 2;
        },
      );
      addTearDown(poller.dispose);
      poller.update(
        apiKey: 'k',
        environment: XmaxEnvironment.global,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 200));
      poller.update(
        apiKey: ' key \n',
        environment: XmaxEnvironment.global,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 249));
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 1);
      expect(poller.state, const FeedCreditBalanceState(balance: 0.5));
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.global,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 4999));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      expect(poller.state.balance, 1);
      expect(accounts, [('key', XmaxEnvironment.global)]);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.global,
        isActive: false,
      );
    },
  );

  testWidgets(
    'slow requests do not overlap and polling waits after completion',
    (tester) async {
      final response = Completer<double>();
      var calls = 0;
      final poller = FeedCreditBalancePoller(
        makeQuery: (_, _) => () {
          calls++;
          return response.future;
        },
      );
      addTearDown(poller.dispose);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(poller.state.isLoading, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1);
      response.complete(100);
      await tester.pump();
      expect(poller.state.balance, 100);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: false,
      );
    },
  );

  testWidgets(
    'failed refresh keeps the last balance and the next poll recovers',
    (tester) async {
      var calls = 0;
      final poller = FeedCreditBalancePoller(
        makeQuery: (_, _) => () async {
          calls++;
          if (calls == 2) throw StateError('offline');
          return calls == 1 ? 1250.75 : 42.5;
        },
      );
      addTearDown(poller.dispose);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(poller.state.balance, 1250.75);
      await tester.pump(const Duration(seconds: 5));
      expect(
        poller.state,
        const FeedCreditBalanceState(balance: 1250.75, refreshFailed: true),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(poller.state, const FeedCreditBalanceState(balance: 42.5));
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: false,
      );
    },
  );

  for (final failing in [false, true]) {
    testWidgets(
      'account replacement ignores late ${failing ? 'failure' : 'success'}',
      (tester) async {
        final old = Completer<double>();
        final poller = FeedCreditBalancePoller(
          makeQuery: (key, _) =>
              key == 'old' ? () => old.future : () async => 42.5,
        );
        addTearDown(poller.dispose);
        poller.update(
          apiKey: 'old',
          environment: XmaxEnvironment.china,
          isActive: true,
        );
        await tester.pump(const Duration(milliseconds: 250));
        poller.update(
          apiKey: 'new',
          environment: XmaxEnvironment.global,
          isActive: true,
        );
        expect(poller.state, const FeedCreditBalanceState());
        await tester.pump(const Duration(milliseconds: 250));
        expect(poller.state.balance, 42.5);
        if (failing) {
          old.completeError(StateError('old request failed'));
        } else {
          old.complete(999);
        }
        await tester.pump();
        expect(poller.state, const FeedCreditBalanceState(balance: 42.5));
        poller.update(
          apiKey: 'new',
          environment: XmaxEnvironment.global,
          isActive: false,
        );
      },
    );
  }

  testWidgets(
    'pause retains the balance but environment changes and key clearing reset it',
    (tester) async {
      var calls = 0;
      final poller = FeedCreditBalancePoller(
        makeQuery: (_, _) =>
            () async => (++calls).toDouble(),
      );
      addTearDown(poller.dispose);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 250));
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: false,
      );
      expect(poller.state.balance, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(poller.state.balance, 2);
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.global,
        isActive: false,
      );
      expect(poller.state, const FeedCreditBalanceState());
      poller.update(
        apiKey: '',
        environment: XmaxEnvironment.global,
        isActive: true,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 2);
    },
  );

  testWidgets('pausing an in-flight query ignores its result after resume', (
    tester,
  ) async {
    final old = Completer<double>();
    var cycles = 0;
    final poller = FeedCreditBalancePoller(
      makeQuery: (_, _) => ++cycles == 1 ? () => old.future : () async => 10.5,
    );
    addTearDown(poller.dispose);
    poller.update(
      apiKey: 'key',
      environment: XmaxEnvironment.china,
      isActive: true,
    );
    await tester.pump(const Duration(milliseconds: 250));
    poller.update(
      apiKey: 'key',
      environment: XmaxEnvironment.china,
      isActive: false,
    );
    expect(poller.state.isLoading, isFalse);
    poller.update(
      apiKey: 'key',
      environment: XmaxEnvironment.china,
      isActive: true,
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(poller.state.balance, 10.5);
    old.complete(999);
    await tester.pump();
    expect(poller.state.balance, 10.5);
    poller.update(
      apiKey: 'key',
      environment: XmaxEnvironment.china,
      isActive: false,
    );
  });

  testWidgets(
    'disposal rejects pending responses and cancels scheduled refreshes',
    (tester) async {
      final response = Completer<double>();
      var calls = 0;
      final poller = FeedCreditBalancePoller(
        makeQuery: (_, _) => () {
          calls++;
          return response.future;
        },
      );
      poller.update(
        apiKey: 'key',
        environment: XmaxEnvironment.china,
        isActive: true,
      );
      await tester.pump(const Duration(milliseconds: 250));
      poller.dispose();
      response.complete(999);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
