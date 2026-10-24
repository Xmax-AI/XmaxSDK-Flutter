import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeErrorManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeLifecycleManager.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeMediaStream.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeState.dart';

void main() {
  test('state listeners immediately receive the shared lifecycle snapshot', () {
    final dependencies = _Dependencies();
    final manager = dependencies.manager;
    final states = <RealtimeState>[];
    manager.setStateListener(states.add);
    expect(states.single.connectionState, RealtimeConnectionState.idle);

    manager.emit(
      const RealtimeState(connectionState: RealtimeConnectionState.preparing),
    );
    manager.markPreviewReady();
    expect(states.last.connectionState, RealtimeConnectionState.ready);
    expect(identical(states.last, manager.currentState), isTrue);
    manager.setStateListener(null);
    manager.emit(
      const RealtimeState(connectionState: RealtimeConnectionState.idle),
    );
    expect(states.length, 3);
  });

  test('a failed queued operation does not block the next operation', () async {
    final manager = _Dependencies().manager;
    final events = <String>[];
    final first = manager.enqueueGenerationOperation<void>(() async {
      events.add('first');
      throw StateError('failed');
    });
    final failure = expectLater(first, throwsStateError);
    final second = manager.enqueueGenerationOperation(() async {
      events.add('second');
      return 42;
    });

    await failure;
    expect(await second, 42);
    expect(events, ['first', 'second']);
  });

  test(
    'disconnection invalidates active and queued generation preparation',
    () async {
      final dependencies = _Dependencies();
      final manager = dependencies.manager;
      dependencies.connect();
      final started = Completer<void>();
      final release = Completer<void>();
      var queuedRan = false;
      final first = manager.enqueueGenerationOperation<void>(() async {
        started.complete();
        await release.future;
      });
      final firstFailure = expectLater(first, throwsA(_cancelled));
      await started.future;
      final second = manager.enqueueGenerationOperation<void>(() async {
        queuedRan = true;
      });
      final secondFailure = expectLater(second, throwsA(_cancelled));

      await manager.disconnect();
      release.complete();
      await Future.wait([firstFailure, secondFailure]);
      expect(queuedRan, isFalse);
      expect(dependencies.connectionCleanups, 1);
      expect(dependencies.localStops, 0);
      expect(
        manager.currentState.connectionState,
        RealtimeConnectionState.ready,
      );
    },
  );

  test('disconnect and close share pending connection cleanup', () async {
    final dependencies = _Dependencies();
    final manager = dependencies.manager;
    dependencies.connect();
    dependencies.cleanupGate = Completer<void>();
    final disconnected = manager.disconnect();
    final repeatedDisconnect = manager.disconnect();
    final closed = manager.close();
    final repeatedClose = manager.close();
    await Future<void>.delayed(Duration.zero);

    expect(dependencies.connectionCleanups, 1);
    expect(dependencies.localStops, 0);
    dependencies.cleanupGate!.complete();
    await Future.wait([
      disconnected,
      repeatedDisconnect,
      closed,
      repeatedClose,
    ]);
    expect(dependencies.connectionCleanups, 1);
    expect(dependencies.localStops, 1);
    expect(manager.isClosing, isFalse);
    expect(manager.isDisconnecting, isFalse);
    expect(manager.currentState.connectionState, RealtimeConnectionState.idle);
  });

  test(
    'shutdown waits for failed camera creation before releasing local media',
    () async {
      final dependencies = _Dependencies();
      final manager = dependencies.manager;
      final camera = Completer<RealtimeMediaStream>();
      manager.emit(
        const RealtimeState(connectionState: RealtimeConnectionState.preparing),
      );
      manager.trackCameraCreation(camera.future);
      final version = manager.beginOperation();
      final closing = manager.close();
      await Future<void>.delayed(Duration.zero);
      expect(dependencies.localStops, 0);
      expect(() => manager.ensureCurrent(version), throwsA(_cancelled));

      camera.completeError(StateError('capture failed'));
      await closing;
      expect(dependencies.localStops, 1);
      expect(
        manager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
    },
  );

  test('stale readiness completion cannot clear a newer task', () async {
    final dependencies = _Dependencies();
    final manager = dependencies.manager;
    dependencies.connect();
    final first = manager.beginGenerationWait('first');
    final second = manager.beginGenerationWait('second');
    final cancelled = expectLater(second.future, throwsA(_cancelled));
    manager.detachGenerationWait(first);
    manager.finishGenerationWait(first);
    first.complete();
    expect(manager.startingGenerationTaskID, 'second');
    expect(identical(manager.generationReadiness, second.future), isTrue);

    await manager.stopGeneration();
    await cancelled;
    expect(dependencies.stoppedTasks, ['second']);
    expect(dependencies.connectionCleanups, 0);
    expect(dependencies.localStops, 0);
    expect(manager.startingGenerationTaskID, isNull);
    expect(
      manager.currentState.connectionState,
      RealtimeConnectionState.connected,
    );
  });

  test(
    'new generation requests invalidate older requests without leaving RTC',
    () {
      final dependencies = _Dependencies();
      final manager = dependencies.manager;
      final first = manager.beginGenerationRequest();
      final second = manager.beginGenerationRequest();
      expect(
        () => manager.ensureGenerationRequestCurrent(first),
        throwsA(_cancelled),
      );
      manager.ensureGenerationRequestCurrent(second);
      expect(dependencies.cancelledStarts, 2);
      expect(dependencies.connectionCleanups, 0);
    },
  );

  test(
    'runtime failure cleanup respects validity and resource scope',
    () async {
      final dependencies = _Dependencies();
      final manager = dependencies.manager;
      dependencies.connect();
      const error = XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'runtime failure',
      );
      await manager.handleFailure(error, RealtimeFailureScope.all, () => false);
      expect(dependencies.connectionCleanups, 0);
      await manager.handleFailure(
        error,
        RealtimeFailureScope.connection,
        () => true,
      );
      expect(dependencies.connectionCleanups, 1);
      expect(dependencies.localStops, 0);
      expect(manager.currentState.reason?.error, same(error));

      await manager.handleFailure(error, RealtimeFailureScope.all, () => true);
      expect(dependencies.localStops, 1);
      expect(
        manager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
      expect(manager.currentState.reason?.error, same(error));
    },
  );
}

final _cancelled = isA<XmaxError>().having(
  (error) => error.code,
  'code',
  XmaxErrorCode.cancelled,
);

final class _Dependencies {
  _Dependencies() {
    manager = XmaxRealtimeLifecycleManager(
      errorManager: XmaxRealtimeErrorManager(),
      cleanupConnection: (taskID) async {
        connectionCleanups++;
        await cleanupGate?.future;
        return RealtimeCleanupResult(sessionID: sessionID, hasLocalMedia: true);
      },
      stopLocalMedia: () async => localStops++,
      stopGeneration: (taskID) async => stoppedTasks.add(taskID),
      cancelPendingStart: () => cancelledStarts++,
      currentSessionID: () => sessionID,
    );
  }

  final String sessionID = 'session-test';
  int connectionCleanups = 0;
  int localStops = 0;
  int cancelledStarts = 0;
  final stoppedTasks = <String>[];
  Completer<void>? cleanupGate;
  late final XmaxRealtimeLifecycleManager manager;

  void connect() {
    manager.emit(
      RealtimeState(
        connectionState: RealtimeConnectionState.connected,
        sessionID: sessionID,
      ),
    );
  }
}
