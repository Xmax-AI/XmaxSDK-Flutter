import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeErrorManager.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLoggerOption.dart';

void main() {
  setUp(() => XmaxLogger.configure(options: XmaxLoggerOption.all));
  tearDown(XmaxLogger.reset);

  test('generation errors are logged even without an error listener', () {
    final messages = <String>[];
    XmaxLogger.setSink((level, message) {
      expect(level, XmaxLogLevel.error);
      messages.add(message);
    });
    const error = XmaxError(
      code: XmaxErrorCode.timeout,
      message: 'Realtime generation start timed out',
    );

    expect(XmaxRealtimeErrorManager().report(error), same(error));
    expect(messages.single, contains('[Xmax][Realtime]'));
    expect(messages.single, contains(error.message));
  });

  test(
    'a failing diagnostic sink cannot suppress the original error',
    () async {
      XmaxLogger.setSink((_, _) => throw StateError('sink failed'));
      final received = <XmaxError>[];
      final handler = XmaxRealtimeErrorManager()
        ..setFailureHandler((error, _, _) async => received.add(error));
      const error = XmaxError(
        code: XmaxErrorCode.timeout,
        message: 'Realtime generation start timed out',
      );

      expect(handler.report(error), same(error));
      expect(
        received,
        isEmpty,
        reason: 'Method failures only throw to their caller',
      );
      handler.forward(error);
      await Future<void>.delayed(Duration.zero);
      expect(received.single, same(error));
    },
  );

  test(
    'connection reset drops queued room failures but retains media failures',
    () async {
      XmaxLogger.setSink((_, _) {});
      final scopes = <RealtimeFailureScope>[];
      final handler = XmaxRealtimeErrorManager()
        ..setFailureHandler((_, scope, isCurrent) async {
          if (isCurrent()) scopes.add(scope);
        });
      const error = XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'old failure',
      );
      handler.forward(error);
      handler.forward(error, scope: RealtimeFailureScope.all);
      handler.invalidatePendingFailures(scope: RealtimeFailureScope.connection);
      await Future<void>.delayed(Duration.zero);
      expect(scopes, [RealtimeFailureScope.all]);

      scopes.clear();
      handler.forward(error);
      handler.forward(error, scope: RealtimeFailureScope.all);
      handler.invalidatePendingFailures();
      await Future<void>.delayed(Duration.zero);
      expect(scopes, isEmpty);
    },
  );

  test(
    'termination can recheck validity after its own asynchronous work',
    () async {
      XmaxLogger.setSink((_, _) {});
      bool Function()? isCurrent;
      final handler = XmaxRealtimeErrorManager()
        ..setFailureHandler((_, _, check) async => isCurrent = check);
      handler.forward(
        const XmaxError(code: XmaxErrorCode.rtcError, message: 'failure'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(isCurrent!(), isTrue);
      handler.invalidatePendingFailures();
      expect(isCurrent!(), isFalse);
    },
  );
}
