import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/AgoraRtcRoom.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcModels.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
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

class _Engine implements RtcEngine {
  RtcEngineEventHandler? handler;
  ChannelMediaOptions? options;
  String? failEvent;
  final sent = <Object>[];
  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #registerEventHandler:
        handler = call.positionalArguments.first as RtcEngineEventHandler;
        return null;
      case #unregisterEventHandler:
        return null;
      case #joinChannelWithUserAccount:
        options = call.namedArguments[#options] as ChannelMediaOptions;
        handler!.onJoinChannelSuccess!(
          const RtcConnection(channelId: 'room', localUid: 1),
          0,
        );
        return Future<void>.value();
      case #createDataStream:
        return Future<int>.value(1);
      case #sendStreamMessage:
        final data = call.namedArguments[#data] as List<int>;
        if ((jsonDecode(utf8.decode(data)) as Map)['event'] == failEvent) {
          return Future<void>.error(StateError('configuration rejected'));
        }
        sent.add(call.namedArguments[#data]!);
        return Future<void>.value();
      case #getUserInfoByUid:
        return Future<UserInfo>.value(
          const UserInfo(uid: 7, userAccount: 'bot'),
        );
      default:
        return Future<void>.value();
    }
  }
}
