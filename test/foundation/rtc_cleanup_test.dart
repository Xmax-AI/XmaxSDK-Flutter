import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcPlatform.dart';
import 'package:xmax_sdk/src/foundation/rtc/AgoraRtcPlatform.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEngineManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/xmax_sdk.dart' show XmaxError, XmaxErrorCode;

final _cancelled = throwsA(
  isA<XmaxError>().having(
    (error) => error.code,
    'code',
    XmaxErrorCode.cancelled,
  ),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'releasing an owner does not wait for another native initialization',
    () async {
      final nextEngine = Completer<RtcPlatform>();
      var creations = 0;
      final pool = RtcEngineManager.internal(
        createEngine: () =>
            creations++ == 0 ? Future.value(_Platform()) : nextEngine.future,
      );
      final first = await pool.acquire();
      final second = pool.acquire();
      await pool.release(first).timeout(const Duration(seconds: 1));
      expect(creations, 2);
      nextEngine.complete(_Platform());
      await pool.release(await second);
    },
  );

  test('an already completed cancellation does not create an engine', () async {
    var created = 0;
    final pool = RtcEngineManager.internal(
      createEngine: () async {
        created++;
        return _Platform();
      },
    );
    await expectLater(pool.acquire(cancellation: Future.value()), _cancelled);
    expect(created, 0);
    final lease = await pool.acquire();
    expect(created, 1);
    await pool.release(lease);
  });

  test(
    'cancelled waiters leave the active owner and remaining FIFO order unchanged',
    () async {
      final platforms = <_Platform>[];
      final pool = RtcEngineManager.internal(
        createEngine: () async {
          final platform = _Platform();
          platforms.add(platform);
          return platform;
        },
      );
      final first = await pool.acquire();
      final cancelled = Completer<void>();
      final pending = pool.acquire(cancellation: cancelled.future);
      final rejected = expectLater(pending, _cancelled);
      final third = pool.acquire();
      final fourth = pool.acquire();
      cancelled.complete();
      await rejected.timeout(const Duration(seconds: 1));
      expect(platforms, hasLength(1));
      expect(platforms.single.destroyCount, 0);
      await pool.release(first);
      final thirdLease = await third;
      expect(platforms, hasLength(2));
      await pool.release(thirdLease);
      final fourthLease = await fourth;
      expect(platforms, hasLength(3));
      await pool.release(fourthLease);
    },
  );

  test(
    'cancellation during engine creation settles creation and destruction before the next owner',
    () async {
      final creation = Completer<RtcPlatform>();
      final first = _Platform()..destroyGate = Completer<void>();
      final second = _Platform();
      var creations = 0;
      final pool = RtcEngineManager.internal(
        createEngine: () {
          creations++;
          return creations == 1 ? creation.future : Future.value(second);
        },
      );
      final cancelled = Completer<void>();
      final pending = pool.acquire(cancellation: cancelled.future);
      var finished = false;
      final rejected = expectLater(
        pending,
        _cancelled,
      ).then((_) => finished = true);
      await _settle();
      expect(creations, 1);
      cancelled.complete();
      final next = pool.acquire();
      await _settle();
      expect(finished, isFalse);
      creation.complete(first);
      await _settle();
      expect(first.destroyCount, 1);
      expect(finished, isFalse);
      expect(creations, 1);
      first.destroyGate!.complete();
      await rejected;
      final lease = await next;
      expect(lease.engine, same(second));
      expect(creations, 2);
      await pool.release(lease);
    },
  );

  test(
    'failed creation or destruction cannot strand the queue after cancellation',
    () async {
      for (final creationFails in [true, false]) {
        final creation = Completer<RtcPlatform>();
        final first = _Platform()..failDestroy = true;
        final second = _Platform();
        var creations = 0;
        final pool = RtcEngineManager.internal(
          createEngine: () {
            creations++;
            return creations == 1 ? creation.future : Future.value(second);
          },
        );
        final cancelled = Completer<void>();
        final rejected = expectLater(
          pool.acquire(cancellation: cancelled.future),
          _cancelled,
        );
        await _settle();
        cancelled.complete();
        await _settle();
        final next = pool.acquire();
        if (creationFails) {
          creation.completeError(StateError('creation failed'));
        } else {
          creation.complete(first);
        }
        await rejected;
        final lease = await next;
        expect(lease.engine, same(second));
        expect(first.destroyCount, creationFails ? 0 : 1);
        await pool.release(lease);
      }
    },
  );

  test(
    'late cancellation cannot release an engine already handed to its owner',
    () async {
      final platform = _Platform();
      final pool = RtcEngineManager.internal(
        createEngine: () async => platform,
      );
      final cancelled = Completer<void>();
      final lease = await pool.acquire(cancellation: cancelled.future);
      cancelled.complete();
      await _settle();
      expect(platform.destroyCount, 0);
      await pool.release(lease);
      expect(platform.destroyCount, 1);
    },
  );

  test(
    'destroying queued initialization does not wait for the active owner',
    () async {
      final platforms = <_Platform>[];
      final pool = RtcEngineManager.internal(
        createEngine: () async {
          final platform = _Platform();
          platforms.add(platform);
          return platform;
        },
      );
      final holder = await pool.acquire();
      final manager = RtcManager(engineManager: pool);
      final rejected = expectLater(manager.initialize(), _cancelled);
      await _settle();
      await manager.destroy().timeout(const Duration(seconds: 1));
      await rejected;
      expect(platforms, hasLength(1));
      expect(platforms.single.destroyCount, 0);
      await pool.release(holder);
      await manager.initialize();
      expect(platforms, hasLength(2));
      await manager.destroy();
      expect(platforms.last.destroyCount, 1);
    },
  );

  test(
    'immediate destruction cancels initialization before native allocation',
    () async {
      var creations = 0;
      final pool = RtcEngineManager.internal(
        createEngine: () async {
          creations++;
          return _Platform();
        },
      );
      final manager = RtcManager(engineManager: pool);
      final rejected = expectLater(manager.initialize(), _cancelled);
      await manager.destroy();
      await rejected;
      expect(creations, 0);
      await manager.initialize();
      expect(creations, 1);
      await manager.destroy();
    },
  );

  test(
    'initialization waits for preceding destruction and ignores stale signals',
    () async {
      final first = _Platform()..destroyGate = Completer<void>();
      final second = _Platform();
      var creations = 0;
      final pool = RtcEngineManager.internal(
        createEngine: () async => creations++ == 0 ? first : second,
      );
      final manager = RtcManager(engineManager: pool);
      final oldCancellation = Completer<void>();
      await manager.initialize(cancellation: oldCancellation.future);
      final destroying = manager.destroy();
      await _settle();
      var initialized = false;
      final initializing = manager.initialize().then((_) => initialized = true);
      oldCancellation.complete();
      await _settle();
      expect(initialized, isFalse);
      expect(creations, 1);
      first.destroyGate!.complete();
      await destroying;
      await initializing;
      expect(creations, 2);
      expect(second.destroyCount, 0);
      await manager.destroy();
      expect(second.destroyCount, 1);
    },
  );

  test('concurrent cold acquisitions create only one native engine', () async {
    final gate = Completer<RtcPlatform>();
    var count = 0;
    final first = _Platform(), second = _Platform();
    final pool = RtcEngineManager.internal(
      createEngine: () {
        count++;
        return count == 1 ? gate.future : Future.value(second);
      },
    );
    final a = pool.acquire(), b = pool.acquire();
    expect(count, 1);
    gate.complete(first);
    final lease = await a;
    expect(count, 1);
    await pool.release(lease);
    final next = await b;
    expect(count, 2);
    expect(next.engine, same(second));
    await pool.release(next);
  });
  test('failed engine destruction unblocks queued owners', () async {
    final first = _Platform()..failDestroy = true, second = _Platform();
    var count = 0;
    final pool = RtcEngineManager.internal(
      createEngine: () async => count++ == 0 ? first : second,
    );
    final lease = await pool.acquire();
    final pending = pool.acquire();
    await expectLater(pool.release(lease), throwsStateError);
    final next = await pending;
    expect(next.engine, same(second));
    await pool.release(next);
  });
  test(
    'handler removal failure still leaves and releases the engine',
    () async {
      final platform = _Platform();
      final pool = RtcEngineManager.internal(
        createEngine: () async => platform,
      );
      final manager = RtcManager(engineManager: pool);
      await manager.initialize();
      final failure = expectLater(
        manager.joinRoom(
          configuration: const RoomJoinConfiguration(
            roomID: 'room',
            userID: 'user',
            token: 'token',
          ),
        ),
        throwsA(anything),
      );
      await platform.engine.joinStarted.future;
      platform.engine.failUnregister = true;
      await manager.destroy();
      await failure;
      expect(platform.engine.leaveCount, 1);
      expect(platform.destroyCount, 1);
    },
  );
  test('leave failure still releases engine and ends a pending join', () async {
    final platform = _Platform();
    var creations = 0;
    final pool = RtcEngineManager.internal(
      createEngine: () async => creations++ == 0 ? platform : _Platform(),
    );
    final manager = RtcManager(engineManager: pool);
    await manager.initialize();
    final joining = manager.joinRoom(
      configuration: const RoomJoinConfiguration(
        roomID: 'room',
        userID: 'user',
        token: 'token',
      ),
    );
    final failure = expectLater(joining, throwsA(anything));
    await platform.engine.joinStarted.future;
    platform.engine.failLeave = true;
    await manager.destroy();
    await failure;
    expect(platform.destroyCount, 1);
    final lease = await pool.acquire();
    await pool.release(lease);
  });
}

class _Platform extends AgoraRtcPlatform {
  _Platform() : this._(_Engine());

  _Platform._(super.engine);

  @override
  _Engine get engine => super.engine as _Engine;
  int destroyCount = 0;
  bool failDestroy = false;
  Completer<void>? destroyGate;
  @override
  Future<void> destroy() async {
    destroyCount++;
    await destroyGate?.future;
    await super.destroy();
    if (failDestroy) throw StateError('destroy failed');
  }
}

class _Engine implements RtcEngineEx {
  final handlers = <RtcEngineEventHandler>{};
  final joinStarted = Completer<void>();
  bool failLeave = false;
  bool failUnregister = false;
  int leaveCount = 0;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #unregisterEventHandler && failUnregister) {
      throw StateError('handler removal failed');
    }
    if (call.memberName == #registerEventHandler) {
      handlers.add(call.positionalArguments.single as RtcEngineEventHandler);
      return null;
    }
    if (call.memberName == #unregisterEventHandler) {
      handlers.remove(call.positionalArguments.single);
      return null;
    }
    if (call.memberName == #joinChannelWithUserAccountEx) {
      if (!joinStarted.isCompleted) joinStarted.complete();
      return Future<void>.value();
    }
    if (call.memberName == #leaveChannelWithUserAccountEx) {
      leaveCount++;
      if (failLeave) return Future<void>.error(StateError('leave failed'));
      for (final handler in handlers.toList()) {
        handler.onLeaveChannel?.call(
          const RtcConnection(channelId: 'room'),
          const RtcStats(),
        );
      }
    }
    return Future<void>.value();
  }
}
