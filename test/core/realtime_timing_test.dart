import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/realtime/RealtimeTiming.dart';
import 'package:xmax_sdk/src/core/XmaxEnvironment.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLoggerOption.dart';

void main() {
  final messages = <String>[];
  setUp(() {
    messages.clear();
    XmaxLogger.configure(
      options: XmaxLoggerOption.performance,
      environment: XmaxEnvironment.global,
    );
    XmaxLogger.setSink((_, message) => messages.add(message));
  });
  tearDown(XmaxLogger.reset);

  test('startup timing reports distinct monotonic stages once', () {
    var now = 0;
    final timing = RealtimeTiming(now: () => now);
    timing.beginConnection();
    timing.beginSessionCreation();
    now = 2000;
    timing.finishSessionCreation();
    timing.beginRoomJoin();
    now = 5000;
    timing.finishRoomJoin();
    timing.finishConnection();
    timing.beginSignal();
    now = 8000;
    timing.confirmRemoteStream();
    now = 12000;
    timing.finish();
    timing.finish();
    expect(messages, hasLength(1));
    final log = messages.single;
    expect(log, contains('Total Duration: 12.0 ms'));
    expect(log, contains('Realtime Connection: 5.0 ms'));
    expect(log, contains('Server Session Creation: 2.0 ms'));
    expect(log, contains('RTC Room Connection: 3.0 ms'));
    expect(log, contains('Waiting for Remote Stream: 3.0 ms'));
    expect(log, contains('First Frame Ready: 4.0 ms'));
  });

  test(
    'failure records the pending stage and suppresses deliberate cancellation',
    () {
      var now = 0;
      final timing = RealtimeTiming(now: () => now)..beginSignal();
      now = 1000;
      timing.confirmRemoteStream();
      now = 4000;
      timing.finishFailure(
        const XmaxError(code: XmaxErrorCode.timeout, message: 'frame timeout'),
      );
      expect(
        messages.single,
        contains(
          'Current Stage: Result Stream Confirmed, Waiting for First Frame',
        ),
      );
      expect(messages.single, contains('Elapsed Time: 4.0 ms'));
      expect(messages.single, contains('Failure Reason: frame timeout'));
      RealtimeTiming().finishFailure(
        const XmaxError(code: XmaxErrorCode.cancelled, message: 'cancelled'),
      );
      expect(messages, hasLength(1));
    },
  );

  test('performance switch and language apply to timing diagnostics', () {
    XmaxLogger.configure(options: XmaxLoggerOption.business);
    RealtimeTiming().finish();
    expect(messages, isEmpty);
    XmaxLogger.configure(options: XmaxLoggerOption.performance);
    RealtimeTiming().finish();
    expect(messages.single, contains('总耗时：'));
  });

  test('overlapping attempts keep separate stage state', () {
    var now = 0;
    final old = RealtimeTiming(now: () => now)..beginSignal();
    now = 2000;
    final current = RealtimeTiming(now: () => now)..beginSessionCreation();
    now = 5000;
    old.finishFailure(
      const XmaxError(code: XmaxErrorCode.cancelled, message: 'superseded'),
    );
    current.finishFailure(
      const XmaxError(code: XmaxErrorCode.apiError, message: 'session failed'),
    );
    expect(messages, hasLength(1));
    expect(messages.single, contains('Current Stage: Server Session Creation'));
    expect(messages.single, contains('Elapsed Time: 3.0 ms'));
  });
}
