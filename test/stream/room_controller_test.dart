import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/foundation/runtime/RuntimeInfo.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcMessageQueue.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcRoomEvent.dart';
import 'package:xmax_sdk/src/stream/room/RoomController.dart';
import 'package:xmax_sdk/src/stream/room/RoomHeartbeat.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionConnection.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimePoint.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

const _connection = RealtimeSessionConnection(
  roomID: 'room',
  userID: 'user',
  token: 'token',
  botName: 'bot',
);
const _format = RealtimeVideoFormat(width: 576, height: 1024, fps: 30);

void main() {
  setUpAll(RuntimeInfo.resolve);
  testWidgets('room heartbeats have no xid or retry attempts', (tester) async {
    final rtc = _Rtc();
    final heartbeat = RoomHeartbeat(rtcManager: rtc);
    heartbeat.start(userID: 'user');
    try {
      await tester.pump(const Duration(seconds: 10));
      expect(rtc.signals, hasLength(1));
      expect(jsonDecode(rtc.signals.single)['event'], 'heartbeat');
      expect(jsonDecode(rtc.signals.single).containsKey('xid'), isFalse);
      await tester.pump(const Duration(seconds: 7));
      expect(rtc.signals, hasLength(1));
    } finally {
      heartbeat.stop();
    }
  });
  for (final kind in ['start', 'change_condition', 'change_target_size']) {
    _test(
      '$kind includes xid, retries unchanged, and isolates transport failure',
      (tester, rtc, room) async {
        await _send(room, kind);
        await tester.pump();
        final first = rtc.signals.single;
        final event = jsonDecode(first);
        expect(event['xid'], isA<String>());
        expect(event['params'].containsKey('xid'), isFalse);
        await tester.pump(const Duration(milliseconds: 300));
        expect(rtc.signals, [first, first]);
        expect(rtc.reportedFailures, everyElement(false));
        expect(rtc.cancellations.every((c) => c != null), isTrue);
        rtc.receipt(event['xid']);
        await tester.pump(const Duration(seconds: 7));
        expect(rtc.signals, hasLength(2));
      },
    );
  }

  _test('wrong room, sender, target, event, and count cannot cancel retries', (
    tester,
    rtc,
    room,
  ) async {
    await _send(room, 'start');
    final xid = jsonDecode(rtc.signals.first)['xid'] as String;
    rtc.receipt(xid, roomID: 'other');
    rtc.receipt(xid, sender: 'other');
    rtc.receipt(xid, sender: 'user');
    rtc.receipt(xid, sender: '');
    rtc.receipt(xid, target: 'other');
    rtc.receipt(xid, target: 42);
    rtc.receipt(xid, event: 'start');
    for (final count in [0, -1, 1.5, '1', true, 9007199254740992]) {
      rtc.receipt(xid, count: count);
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(rtc.signals, hasLength(2));
    rtc.receipt(xid, target: 'user');
    await tester.pump(const Duration(seconds: 7));
    expect(rtc.signals, hasLength(2));
  });

  _test('fragmented ACK is accepted after bounded reassembly', (
    tester,
    rtc,
    room,
  ) async {
    await _send(room, 'start');
    final xid = jsonDecode(rtc.signals.first)['xid'];
    final data = jsonEncode({
      'event': 'xid_ack',
      'xid': xid,
      'count': 2,
      'extra': 'x' * 2400,
    });
    for (final packet in RtcMessageCodec.encode(data).reversed) {
      rtc.listener!(RtcRoomMessage(stream: _stream(), data: packet));
    }
    await tester.pump(const Duration(seconds: 7));
    expect(rtc.signals, hasLength(1));
  });

  _test('stop cancels queued retries before its native send completes', (
    tester,
    rtc,
    room,
  ) async {
    await _send(room, 'start');
    rtc.sendGate = Completer<void>();
    var completed = false;
    final stop = room
        .stopGeneration(taskID: 'task')
        .then((_) => completed = true);
    await tester.pump(const Duration(seconds: 7));
    expect(completed, isFalse);
    expect(rtc.signals.map((s) => jsonDecode(s)['event']), ['start', 'stop']);
    rtc.sendGate!.complete();
    await stop;
    expect(jsonDecode(rtc.signals.last).containsKey('xid'), isFalse);
  });

  _test('tracks remain unacknowledged single sends', (tester, rtc, room) async {
    await room.sendTracks(
      taskID: 'task',
      points: const [RealtimePoint(x: 0.5, y: 0.5)],
    );
    await tester.pump(const Duration(seconds: 10));
    expect(rtc.signals.map((s) => jsonDecode(s)['event']), ['tracks']);
    expect(rtc.signals.every((s) => !jsonDecode(s).containsKey('xid')), isTrue);
  });

  _test(
    'leave invalidates callbacks and retries before asynchronous native cleanup',
    (tester, rtc, room) async {
      await _send(room, 'start');
      final oldListener = rtc.listener!;
      rtc.leaveGate = Completer<void>();
      final leaving = room.leave();
      expect(rtc.listener, isNull);
      await tester.pump(const Duration(seconds: 7));
      expect(rtc.signals, hasLength(1));
      rtc.leaveGate!.complete();
      await leaving;
      await tester.runAsync(
        () => room.join(connection: _connection, ensureActive: () {}),
      );
      await _send(room, 'start');
      final xid = jsonDecode(rtc.signals.last)['xid'];
      oldListener(
        RtcRoomMessage(
          stream: _stream(),
          data: utf8.encode(
            jsonEncode({'event': 'xid_ack', 'xid': xid, 'count': 1}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(rtc.signals, hasLength(3));
      expect(rtc.signals[1], rtc.signals[2]);
      rtc.receipt(jsonDecode(rtc.signals[1])['xid']);
    },
  );

  test(
    'obsolete room join cannot restore routing or close a newer room',
    () async {
      final rtc = _Rtc()..joinGate = Completer<void>();
      final room = RoomController(rtcManager: rtc);
      final oldJoin = room.join(connection: _connection, ensureActive: () {});
      final rejected = expectLater(oldJoin, throwsA(isA<XmaxError>()));
      await Future<void>.delayed(Duration.zero);
      await room.leave();
      final oldGate = rtc.joinGate!;
      rtc.joinGate = null;
      await room.join(connection: _connection, ensureActive: () {});
      final listener = rtc.listener;
      oldGate.complete();
      await Future<void>.delayed(Duration.zero);
      await rejected;
      expect(rtc.listener, same(listener));
      expect(rtc.leaves, 1);
      await _send(room, 'start');
      await room.leave();
    },
  );
}

Future<void> _send(RoomController room, String kind) => switch (kind) {
  'start' => room.startGeneration(
    taskID: 'task',
    videoFormat: _format,
    context: RealtimeContext(prompt: 'test'),
  ),
  'change_condition' => room.changeGenerationCondition(
    taskID: 'task',
    videoFormat: _format,
    context: RealtimeContext(prompt: 'test'),
  ),
  _ => room.changeTargetSize(
    taskID: 'task',
    targetSize: const Size(576, 1024),
    ensureActive: () {},
  ),
};

void _test(
  String name,
  Future<void> Function(WidgetTester, _Rtc, RoomController) body,
) {
  testWidgets(name, (tester) async {
    final rtc = _Rtc();
    final room = RoomController(rtcManager: rtc);
    try {
      await tester.runAsync(
        () => room.join(connection: _connection, ensureActive: () {}),
      );
      await body(tester, rtc, room);
    } finally {
      await room.leave();
      await tester.pump();
    }
  });
}

RemoteStream _stream({String roomID = 'room', String sender = 'bot'}) =>
    RemoteStream(roomID: roomID, userID: sender, streamID: sender);

class _Rtc implements RtcManaging {
  final signals = <String>[];
  final reportedFailures = <bool>[];
  final cancellations = <Future<void>?>[];
  void Function(RtcRoomMessage)? listener;
  Completer<void>? sendGate, leaveGate, joinGate;
  int leaves = 0;
  @override
  Future<void> joinRoom({required RoomJoinConfiguration configuration}) async =>
      await joinGate?.future;
  @override
  Future<void> leaveRoom() async {
    leaves++;
    await leaveGate?.future;
  }

  @override
  void setRoomMessageListener(void Function(RtcRoomMessage)? listener) =>
      this.listener = listener;
  @override
  Future<void> sendRoomMessage(
    String message, {
    bool reportFailure = true,
    Future<void>? cancellation,
  }) async {
    signals.add(message);
    reportedFailures.add(reportFailure);
    cancellations.add(cancellation);
    await sendGate?.future;
  }

  void receipt(
    String xid, {
    String roomID = 'room',
    String sender = 'bot',
    Object? target,
    Object count = 1,
    String event = 'xid_ack',
  }) => listener?.call(
    RtcRoomMessage(
      stream: _stream(roomID: roomID, sender: sender),
      data: utf8.encode(
        jsonEncode({
          'event': event,
          'xid': xid,
          'count': count,
          'user_id': target,
        }),
      ),
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
