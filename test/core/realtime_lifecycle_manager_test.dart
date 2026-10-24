import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeErrorManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeLifecycleManager.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

final _cancelled = isA<XmaxError>().having(
  (e) => e.code,
  'code',
  XmaxErrorCode.cancelled,
);
final _conflict = isA<XmaxError>().having(
  (e) => e.code,
  'code',
  XmaxErrorCode.invalidConfiguration,
);
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'state delivery is immediate on registration and otherwise deduplicated',
    () async {
      final d = _Dependencies(), states = <RealtimeState>[];
      d.manager.setStateListener(states.add);
      await d.connect();
      await d.connect();
      expect(states.map((s) => s.connectionState), [
        RealtimeConnectionState.idle,
        RealtimeConnectionState.connected,
      ]);
      d.manager.setStateListener(null);
      await d.manager.disconnect();
      expect(states, hasLength(2));
    },
  );

  test(
    'completion releases admission before reentrant state callbacks',
    () async {
      final d = _Dependencies();
      Future<int>? reentered;
      d.manager.setStateListener((state) {
        if (state.connectionState == RealtimeConnectionState.connected) {
          reentered = d.manager.run(
            kind: RealtimeOperationKind.configuration,
            operation: (_) async => 42,
          );
        }
      });
      await d.connect();
      expect(await reentered, 42);
    },
  );

  test('media and foreground configuration conflicts are rejected', () async {
    final d = _Dependencies(), gate = Completer<void>();
    final first = d.manager.run(
      kind: RealtimeOperationKind.media,
      operation: (_) async => gate.future,
    );
    await expectLater(
      d.manager.run(
        kind: RealtimeOperationKind.connection,
        operation: (_) async {},
      ),
      throwsA(_conflict),
    );
    gate.complete();
    await first;
    expect(
      await d.manager.run(
        kind: RealtimeOperationKind.media,
        operation: (_) async => 7,
      ),
      7,
    );
  });

  test(
    'replacement cancels passive readiness and retains the connection',
    () async {
      final d = _Dependencies(), started = Completer<void>();
      await d.connect();
      final first = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (token) async {
          token.setFailureScope(RealtimeTerminationScope.connection);
          started.complete();
          await token.wait(Completer<void>().future);
        },
      );
      final failure = expectLater(first, throwsA(_cancelled));
      await started.future;
      final second = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (token) async => token.ensureCurrent(),
      );
      await second;
      await failure;
      expect(d.scopes, [RealtimeTerminationScope.generation]);
      expect(
        d.manager.currentState.connectionState,
        RealtimeConnectionState.connected,
      );
    },
  );

  test(
    'only the latest queued replacement executes after native work settles',
    () async {
      final d = _Dependencies(),
          gate = Completer<void>(),
          started = Completer<void>();
      await d.connect();
      final first = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (token) async {
          token.setFailureScope(RealtimeTerminationScope.connection);
          started.complete();
          await gate.future;
          token.ensureCurrent();
        },
      );
      final f1 = expectLater(first, throwsA(_cancelled));
      await started.future;
      var middleRan = false;
      final middle = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (_) async => middleRan = true,
      );
      final f2 = expectLater(middle, throwsA(_cancelled));
      final last = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (_) async => 9,
      );
      await _settle();
      expect(d.scopes, isEmpty);
      gate.complete();
      expect(await last, 9);
      await Future.wait([f1, f2]);
      expect(middleRan, isFalse);
    },
  );

  test(
    'close waits for in-flight capture and merges with pending disconnect',
    () async {
      final d = _Dependencies(),
          gate = Completer<void>(),
          started = Completer<void>();
      final media = d.manager.run(
        kind: RealtimeOperationKind.media,
        operation: (token) async {
          d.manager.commit(
            const RealtimeState(
              connectionState: RealtimeConnectionState.preparing,
            ),
            token: token,
          );
          started.complete();
          await gate.future;
          token.ensureCurrent();
        },
      );
      final failure = expectLater(media, throwsA(_cancelled));
      await started.future;
      final close = d.manager.terminate(RealtimeTerminationScope.all);
      final repeated = d.manager.terminate(RealtimeTerminationScope.all);
      final disconnect = d.manager.disconnect();
      await _settle();
      expect(d.scopes, isEmpty);
      gate.complete();
      await Future.wait([close, repeated, disconnect, failure]);
      expect(d.scopes, [RealtimeTerminationScope.all]);
      expect(
        d.manager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
    },
  );

  test(
    'disconnect cancels queued replacements without restarting generation',
    () async {
      final d = _Dependencies(),
          gate = Completer<void>(),
          started = Completer<void>();
      await d.connect();
      final first = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (token) async {
          token.setFailureScope(RealtimeTerminationScope.connection);
          started.complete();
          await gate.future;
          token.ensureCurrent();
        },
      );
      final f1 = expectLater(first, throwsA(_cancelled));
      await started.future;
      var replacementRan = false;
      final second = d.manager.run(
        kind: RealtimeOperationKind.generation,
        operation: (_) async => replacementRan = true,
      );
      final f2 = expectLater(second, throwsA(_cancelled));
      final disconnect = d.manager.disconnect();
      gate.complete();
      await Future.wait([f1, f2, disconnect]);
      expect(replacementRan, isFalse);
      expect(d.scopes, [RealtimeTerminationScope.connection]);
    },
  );

  test(
    'background configuration yields to foreground work and drains before cleanup',
    () async {
      final d = _Dependencies(),
          gate = Completer<void>(),
          started = Completer<void>();
      await d.generating();
      final background = d.manager.runAdaptiveConfiguration((token) async {
        started.complete();
        await gate.future;
        token.ensureCurrent();
      });
      await started.future;
      var foregroundRan = false;
      final foreground = d.manager.run(
        kind: RealtimeOperationKind.configuration,
        operation: (_) async => foregroundRan = true,
      );
      expect(await d.manager.runAdaptiveConfiguration((_) async {}), isFalse);
      await _settle();
      expect(foregroundRan, isFalse);
      gate.complete();
      expect(await background, isTrue);
      await foreground;
      expect(foregroundRan, isTrue);
    },
  );

  test(
    'terminal state releases cleanup ownership before reentrant close',
    () async {
      final d = _Dependencies();
      await d.connect();
      Future<void>? closing;
      d.manager.setStateListener((state) {
        if (state.connectionState == RealtimeConnectionState.ready) {
          closing = d.manager.terminate(RealtimeTerminationScope.all);
        }
      });
      await d.manager.disconnect();
      await closing;
      expect(d.scopes, [
        RealtimeTerminationScope.connection,
        RealtimeTerminationScope.all,
      ]);
      expect(
        d.manager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
    },
  );

  test(
    'repeated close during cleanup shares one resource-release pass',
    () async {
      final d = _Dependencies(),
          gate = Completer<void>(),
          started = Completer<void>();
      await d.connect();
      final operation = d.manager.run(
        kind: RealtimeOperationKind.configuration,
        operation: (token) async {
          started.complete();
          await token.wait(Completer<void>().future);
        },
      );
      final cancelled = expectLater(operation, throwsA(_cancelled));
      await started.future;
      d.gate = gate;
      final first = d.manager.terminate(RealtimeTerminationScope.all);
      await _settle();
      expect(d.scopes, [RealtimeTerminationScope.all]);
      final second = d.manager.terminate(RealtimeTerminationScope.all);
      gate.complete();
      await Future.wait([first, second, cancelled]);
      expect(d.scopes, [RealtimeTerminationScope.all]);
    },
  );

  test(
    'media failure expands active connection cleanup and preserves the first failure',
    () async {
      final d = _Dependencies(), cleanup = Completer<void>();
      await d.connect();
      d.gate = cleanup;
      const error = XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'camera failed',
      );
      final disconnect = d.manager.disconnect();
      await _settle();
      final failure = d.manager.handleFailure(
        error,
        RealtimeFailureScope.all,
        () => true,
      );
      cleanup.complete();
      await Future.wait([disconnect, failure]);
      expect(d.scopes.last, RealtimeTerminationScope.all);
      expect(d.manager.currentState.reason?.error, same(error));
      expect(
        d.manager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
    },
  );
}

class _Dependencies {
  _Dependencies() {
    manager = XmaxRealtimeLifecycleManager(
      errorManager: XmaxRealtimeErrorManager(),
      cleanup: (scope, taskID) async {
        scopes.add(scope);
        await gate?.future;
        return RealtimeCleanupResult(
          sessionID: 'session',
          hasLocalMedia: scope != RealtimeTerminationScope.all,
        );
      },
    );
  }
  late final XmaxRealtimeLifecycleManager manager;
  final scopes = <RealtimeTerminationScope>[];
  Completer<void>? gate;
  Future<void> connect() => manager.run(
    kind: RealtimeOperationKind.connection,
    operation: (token) async => manager.complete(
      const RealtimeState(
        connectionState: RealtimeConnectionState.connected,
        sessionID: 'session',
      ),
      token: token,
    ),
  );
  Future<void> generating() => manager.run(
    kind: RealtimeOperationKind.generation,
    operation: (token) async => manager.complete(
      const RealtimeState(
        connectionState: RealtimeConnectionState.generating,
        sessionID: 'session',
        taskID: 'task',
      ),
      token: token,
    ),
  );
}
