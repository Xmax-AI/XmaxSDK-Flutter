import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcPlatform.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEngineManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcModels.dart';

void main() {
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
    final pool = RtcEngineManager.internal(createEngine: () async => platform);
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

class _Platform implements RtcPlatform {
  @override
  final _Engine engine = _Engine();
  int destroyCount = 0;
  bool failDestroy = false;
  @override
  Future<void> destroy() async {
    destroyCount++;
    if (failDestroy) throw StateError('destroy failed');
  }
}

class _Engine implements RtcEngine {
  final joinStarted = Completer<void>();
  bool failLeave = false;
  bool failUnregister = false;
  int leaveCount = 0;
  @override
  dynamic noSuchMethod(Invocation call) {
    if (call.memberName == #unregisterEventHandler && failUnregister) {
      throw StateError('handler removal failed');
    }
    if (call.memberName == #registerEventHandler ||
        call.memberName == #unregisterEventHandler) {
      return null;
    }
    if (call.memberName == #joinChannelWithUserAccount) {
      if (!joinStarted.isCompleted) joinStarted.complete();
      return Future<void>.value();
    }
    if (call.memberName == #leaveChannel) {
      leaveCount++;
      if (failLeave) return Future<void>.error(StateError('leave failed'));
    }
    return Future<void>.value();
  }
}
