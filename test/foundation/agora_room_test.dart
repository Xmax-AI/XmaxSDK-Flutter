import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/AgoraRtcRoom.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test(
    'room traffic and account queries use the assigned local connection',
    () async {
      final engine = _Engine()..localUid = 42;
      final published = <RemoteStream>[];
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => RtcEventListener(
          onRemoteVideoPublished: (stream, active) {
            if (active) published.add(stream);
          },
        ),
      );
      await room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      );
      expect(room.connection.channelId, 'room');
      expect(room.connection.localUid, 42);
      await room.sendMessage('{"event":"start","uid":"task"}');
      expect(await room.resolveUID('bot'), 7);
      engine.handler!.onUserJoined!(
        const RtcConnection(channelId: 'room', localUid: 99),
        7,
        0,
      );
      await Future<void>.delayed(Duration.zero);
      expect(published, isEmpty);
      engine.handler!.onUserJoined!(room.connection, 7, 0);
      await Future<void>.delayed(Duration.zero);
      expect(published.single.localUid, 42);
      for (final name in [
        #createDataStreamEx,
        #sendStreamMessageEx,
        #getUserInfoByUserAccountEx,
        #getUserInfoByUidEx,
      ]) {
        final calls = engine.calls.where((call) => call.memberName == name);
        expect(calls, isNotEmpty);
        for (final call in calls) {
          final connection = call.namedArguments[#connection] as RtcConnection;
          expect(connection.channelId, 'room');
          expect(connection.localUid, 42);
        }
      }
      await room.destroy();
      await room.destroy();
      final leaves = engine.calls.where(
        (call) => call.memberName == #leaveChannelWithUserAccountEx,
      );
      expect(leaves, hasLength(1));
      expect(leaves.single.namedArguments[#channelId], 'room');
      expect(leaves.single.namedArguments[#userAccount], 'user');
    },
  );

  test(
    'early publications are resolved after the local connection is known',
    () async {
      final engine = _Engine()..publishBeforeJoin = true;
      final published = <RemoteStream>[];
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => RtcEventListener(
          onRemoteVideoPublished: (stream, active) {
            if (active) published.add(stream);
          },
        ),
      );
      await room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(published, hasLength(1));
      expect(published.single.localUid, 1);
      await room.destroy();
    },
  );

  test(
    'failed join closes only its account and cleanup is idempotent',
    () async {
      final engine = _Engine()..failJoin = true;
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => null,
      );
      await expectLater(
        room.join(
          const RoomJoinConfiguration(
            roomID: 'room',
            userID: 'user',
            token: 'token',
          ),
        ),
        throwsStateError,
      );
      await room.destroy();
      expect(room.isClosed, isTrue);
      expect(
        engine.calls.where(
          (call) => call.memberName == #leaveChannelWithUserAccountEx,
        ),
        hasLength(1),
      );
    },
  );

  test('missing local UID fails before creating a data stream', () async {
    final engine = _Engine()..localUid = 0;
    final room = AgoraRtcRoom(
      engine: engine,
      roomID: 'room',
      listener: () => null,
    );
    await expectLater(
      room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      ),
      throwsA(
        isA<XmaxError>().having(
          (error) => error.message,
          'message',
          contains('no local UID'),
        ),
      ),
    );
    expect(
      engine.calls.where((call) => call.memberName == #createDataStreamEx),
      isEmpty,
    );
    expect(room.isClosed, isTrue);
  });

  test(
    'missing native leave callback times out and unregisters room events',
    () async {
      final engine = _Engine()..autoLeave = false;
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => null,
        leaveTimeout: const Duration(milliseconds: 10),
      );
      await room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      );
      await expectLater(room.destroy(), throwsA(isA<TimeoutException>()));
      expect(
        engine.calls.where(
          (call) => call.memberName == #unregisterEventHandler,
        ),
        hasLength(1),
      );
      await expectLater(room.destroy(), throwsA(isA<TimeoutException>()));
      expect(
        engine.calls.where(
          (call) => call.memberName == #leaveChannelWithUserAccountEx,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'target-size rejection is nonfatal to the room and later conditions',
    () async {
      final engine = _Engine()..failEvent = 'change_target_size';
      final errors = <Object>[];
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => RtcEventListener(onError: errors.add),
      );
      await room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      );
      await expectLater(
        room.sendMessage('{"event":"change_target_size","uid":"task"}'),
        throwsA(isA<XmaxError>()),
      );
      await room.sendMessage('{"event":"change_condition","uid":"task"}');
      expect(errors, isEmpty);
      expect(engine.sent, hasLength(1));
      await room.destroy();
    },
  );
  test(
    'account mapping retains early frames and filters closed-room callbacks',
    () async {
      final engine = _Engine(),
          published = <RemoteStream>[],
          decoded = <RemoteStream>[];
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => RtcEventListener(
          onRemoteVideoPublished: (stream, active) {
            if (active) published.add(stream);
          },
          onFirstRemoteVideoFrameDecoded: decoded.add,
        ),
      );
      await room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      );
      final handler = engine.handler!;
      handler.onFirstRemoteVideoDecoded!(
        const RtcConnection(channelId: 'room'),
        7,
        1024,
        1920,
        0,
      );
      handler.onUserInfoUpdated!(7, const UserInfo(uid: 7, userAccount: 'bot'));
      handler.onUserJoined!(const RtcConnection(channelId: 'room'), 7, 0);
      await Future<void>.delayed(Duration.zero);
      expect(published, hasLength(1));
      expect(published.single.userID, 'bot');
      expect(published.single.uid, 7);
      expect(decoded, isNotEmpty);
      await room.destroy();
      handler.onUserJoined!(const RtcConnection(channelId: 'room'), 8, 0);
      handler.onUserInfoUpdated!(
        8,
        const UserInfo(uid: 8, userAccount: 'other'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(published, hasLength(1));
    },
  );
  test(
    'join publishes no microphone and subscribes no remote media automatically',
    () async {
      final engine = _Engine();
      final room = AgoraRtcRoom(
        engine: engine,
        roomID: 'room',
        listener: () => null,
      );
      await room.join(
        const RoomJoinConfiguration(
          roomID: 'room',
          userID: 'user',
          token: 'token',
        ),
      );
      expect(engine.options!.publishMicrophoneTrack, false);
      expect(engine.options!.publishCameraTrack, false);
      expect(engine.options!.autoSubscribeAudio, false);
      expect(engine.options!.autoSubscribeVideo, false);
      await room.sendMessage('{"event":"start","uid":"task"}');
      expect(engine.sent, hasLength(1));
      await room.destroy();
    },
  );
}

class _Engine implements RtcEngineEx {
  final calls = <Invocation>[];
  int localUid = 1;
  bool failJoin = false;
  bool autoLeave = true;
  bool publishBeforeJoin = false;
  RtcEngineEventHandler? handler;
  ChannelMediaOptions? options;
  String? failEvent;
  final sent = <Object>[];
  @override
  dynamic noSuchMethod(Invocation call) {
    calls.add(call);
    switch (call.memberName) {
      case #joinChannelWithUserAccount:
      case #leaveChannel:
      case #createDataStream:
      case #sendStreamMessage:
      case #getUserInfoByUid:
      case #getUserInfoByUserAccount:
        throw StateError('Unexpected unscoped RTC call: ${call.memberName}');
      case #registerEventHandler:
        handler = call.positionalArguments.first as RtcEngineEventHandler;
        return null;
      case #unregisterEventHandler:
        return null;
      case #joinChannelWithUserAccountEx:
        options = call.namedArguments[#options] as ChannelMediaOptions;
        if (failJoin) return Future<void>.error(StateError('join rejected'));
        if (publishBeforeJoin) {
          handler!.onUserJoined!(
            RtcConnection(channelId: 'room', localUid: localUid),
            7,
            0,
          );
        }
        handler!.onJoinChannelSuccess!(
          RtcConnection(channelId: 'room', localUid: localUid),
          0,
        );
        return Future<void>.value();
      case #createDataStreamEx:
        return Future<int>.value(1);
      case #sendStreamMessageEx:
        final data = call.namedArguments[#data] as List<int>;
        if ((jsonDecode(utf8.decode(data)) as Map)['event'] == failEvent) {
          return Future<void>.error(StateError('configuration rejected'));
        }
        sent.add(call.namedArguments[#data]!);
        return Future<void>.value();
      case #getUserInfoByUidEx:
      case #getUserInfoByUserAccountEx:
        return Future<UserInfo>.value(
          const UserInfo(uid: 7, userAccount: 'bot'),
        );
      case #leaveChannelWithUserAccountEx:
        if (autoLeave) {
          handler!.onLeaveChannel!(
            RtcConnection(channelId: 'room', localUid: localUid),
            const RtcStats(),
          );
        }
        return Future<void>.value();
      default:
        return Future<void>.value();
    }
  }
}
