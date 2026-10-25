import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/XmaxEnvironment.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLoggerOption.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionConnection.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeTiming.dart';
import 'package:xmax_sdk/src/stream/StreamController.dart';

const _connection = RealtimeSessionConnection(
  roomID: 'room',
  userID: 'user',
  token: 'token',
  botName: 'bot',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'real room and stream controllers measure join and publication separately',
    () async {
      var now = 0;
      final timing = RealtimeTiming(now: () => now)..beginSessionCreation();
      now = 2000;
      timing.finishSessionCreation();
      final rtc = _Rtc(
        onJoin: () async => now = 5000,
        onPublish: () async => now = 5500,
      );
      final stream = StreamController(rtcManager: rtc, timing: timing);
      addTearDown(stream.disconnect);
      await stream.connect(connection: _connection, ensureActive: () {});
      timing.beginSignal();
      now = 8000;
      timing.finishFirstFrame();
      now = 12000;
      timing.finish();
      expect(messages.single, contains('Session Creation: 2.0 ms'));
      expect(messages.single, contains('RTC Room Join: 3.0 ms'));
      expect(messages.single, contains('Local Stream Publication: 0.5 ms'));
      expect(messages.single, contains('First Frame Arrival: 2.5 ms'));
      expect(messages.single, contains('Total Duration: 12.0 ms'));
    },
  );

  test(
    'publication failure retains completed join and unfinished publication durations',
    () async {
      var now = 0;
      final timing = RealtimeTiming(now: () => now);
      final error = StateError('publication failed');
      final rtc = _Rtc(
        onJoin: () async => now = 3000,
        onPublish: () async {
          now = 8000;
          throw error;
        },
      );
      final stream = StreamController(rtcManager: rtc, timing: timing);
      addTearDown(stream.disconnect);
      await expectLater(
        stream.connect(connection: _connection, ensureActive: () {}),
        throwsA(same(error)),
      );
      timing.finishFailure(error);
      expect(messages.single, contains('RTC Room Join: 3.0 ms'));
      expect(messages.single, contains('Local Stream Publication: 5.0 ms'));
      expect(messages.single, contains('First Frame Arrival: —'));
      expect(
        messages.single,
        contains('Current Stage: Publishing Local Stream'),
      );
    },
  );

  test('join failure never starts local publication timing', () async {
    var now = 0;
    final timing = RealtimeTiming(now: () => now);
    var published = false;
    final rtc = _Rtc(
      onJoin: () async {
        now = 3000;
        throw StateError('join failed');
      },
      onPublish: () async => published = true,
    );
    final stream = StreamController(rtcManager: rtc, timing: timing);
    addTearDown(stream.disconnect);
    try {
      await stream.connect(connection: _connection, ensureActive: () {});
      fail('RTC join should fail');
    } catch (error) {
      timing.finishFailure(error);
    }
    expect(published, isFalse);
    expect(messages.single, contains('RTC Room Join: 3.0 ms'));
    expect(messages.single, contains('Local Stream Publication: —'));
    expect(messages.single, contains('Current Stage: Joining RTC Room'));
  });
}

class _Rtc implements RtcManaging {
  _Rtc({required this.onJoin, required this.onPublish});

  final Future<void> Function() onJoin;
  final Future<void> Function() onPublish;

  @override
  Future<void> joinRoom({required RoomJoinConfiguration configuration}) =>
      onJoin();

  @override
  Future<void> publishLocalVideo({required bool publish}) async {
    if (publish) await onPublish();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
