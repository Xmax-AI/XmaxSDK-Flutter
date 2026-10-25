import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/foundation/rtc/LocalStream.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEngineManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcPlatform.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcQualityListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcRoom.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcRoomEvent.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

const _join = RoomJoinConfiguration(
  roomID: 'room',
  userID: 'user',
  token: 'token',
);

void main() {
  test(
    'RTC coordination interfaces do not import or call the vendor engine',
    () {
      for (final name in [
        'RtcManager',
        'RtcPlatform',
        'RtcRoom',
        'RtcRoomEvent',
      ]) {
        final source = File(
          'lib/src/foundation/rtc/$name.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('agora_rtc_engine')));
        expect(source, isNot(contains('RtcEngineEventHandler')));
        expect(source, isNot(contains('setVideoEncoderConfigurationEx')));
        expect(source, isNot(contains('AgoraRtcRoom')));
        expect(source, isNot(contains('/render/')));
      }
    },
  );

  test(
    'RTC manager operates through a platform without a native engine',
    () async {
      final platform = _Platform();
      final manager = _manager(platform);
      final RtcManaging input = manager;
      expect(() => input.localStream, throwsA(isA<XmaxError>()));
      await manager.initialize();
      const encoding = VideoEncodingConfiguration(
        width: 1024,
        height: 1920,
        frameRate: 30,
      );
      await manager.configureVideoEncoding(encoding);
      await manager.startVideoCapture(width: 1024, height: 1920, frameRate: 30);
      expect(platform.calls.map((call) => call.memberName), [
        #configureVideoEncoding,
        #startVideoCapture,
      ]);
      expect(platform.calls.first.positionalArguments.single, same(encoding));
      expect(input.localStream, same(platform.localStream));
      expect(input.localStream.engine, isNull);

      await manager.joinRoom(configuration: _join);
      final room = platform.rooms.single;
      await manager.publishLocalVideo(publish: true);
      await manager.subscribeRemoteVideo(streamID: 'bot', subscribe: true);
      await manager.subscribeRemoteAudio(streamID: 'bot', subscribe: false);
      await manager.setRemoteAudioVolume(volume: 45, streamID: 'bot');
      await manager.sendRoomMessage('{"event":"start"}');
      expect(room.calls.map((call) => call.memberName), [
        #publishLocalVideo,
        #subscribeRemoteVideo,
        #subscribeRemoteAudio,
        #setRemoteAudioVolume,
        #sendMessage,
      ]);
      expect(room.calls[1].namedArguments, {#userID: 'bot', #subscribe: true});
      expect(room.calls[3].namedArguments, {#volume: 45, #userID: 'bot'});
      await manager.leaveRoom();
      expect(room.closed, isTrue);
      expect(input.localStream, same(platform.localStream));
      expect(
        platform.calls.map((call) => call.memberName),
        isNot(contains(#stopVideoCapture)),
      );
      await manager.destroy();
      expect(platform.destroyed, 1);
      expect(() => input.localStream, throwsA(isA<XmaxError>()));
    },
  );

  test(
    'normalized events use current listeners and discard previous rooms',
    () async {
      final platform = _Platform();
      final manager = _manager(platform);
      final quality = _Quality();
      final publications = <RemoteStream>[];
      final decoded = <RemoteStream>[];
      final errors = <Object>[];
      final stream = RemoteStream(
        roomID: 'room',
        userID: 'bot',
        streamID: 'bot',
      );
      manager.setEventListener(
        RtcEventListener(
          onRemoteVideoPublished: (stream, published) {
            if (published) publications.add(stream);
          },
          onFirstRemoteVideoFrameDecoded: decoded.add,
          onError: errors.add,
        ),
      );
      manager.setQualityListener(quality);
      await manager.initialize();
      await manager.joinRoom(configuration: _join);
      final old = platform.rooms.single;
      final oldListener = old.listener!;
      oldListener(RtcRoomVideoPublication(stream: stream, published: true));
      oldListener(RtcRoomFirstVideoDecoded(stream: stream));
      oldListener(
        const RtcRoomUplinkVideoStatistics(
          statistics: UplinkVideoStatistics(sendFrameRate: 30),
        ),
      );
      oldListener(
        const RtcRoomFailure(
          error: XmaxError(code: XmaxErrorCode.rtcError, message: 'failed'),
        ),
      );
      expect(publications, [stream]);
      expect(decoded, [stream]);
      expect(quality.events, hasLength(1));
      expect(errors, hasLength(1));

      await manager.leaveRoom();
      await manager.joinRoom(configuration: _join);
      oldListener(RtcRoomVideoPublication(stream: stream, published: true));
      oldListener(
        const RtcRoomUplinkVideoStatistics(
          statistics: UplinkVideoStatistics(sendFrameRate: 1),
        ),
      );
      oldListener(
        const RtcRoomFailure(
          error: XmaxError(code: XmaxErrorCode.rtcError, message: 'stale'),
        ),
      );
      expect(publications, hasLength(1));
      expect(quality.events, hasLength(1));
      expect(errors, hasLength(1));

      manager.setQualityListener(null);
      platform.rooms.last.listener!(
        const RtcRoomUplinkVideoStatistics(
          statistics: UplinkVideoStatistics(sendFrameRate: 24),
        ),
      );
      expect(quality.events, hasLength(1));
      await manager.destroy();
    },
  );
}

RtcManager _manager(_Platform platform) => RtcManager(
  engineManager: RtcEngineManager.internal(createEngine: () async => platform),
);

class _Platform implements RtcPlatform {
  final calls = <Invocation>[];
  final rooms = <_Room>[];
  int destroyed = 0;

  @override
  void setEventListener(RtcEventListener? listener) {}

  @override
  void setCameraPreviewReadyListener(void Function()? listener) {}

  @override
  LocalStream get localStream => const LocalStream();

  @override
  RtcRoom createRoom({required String roomID, required Duration leaveTimeout}) {
    final room = _Room();
    rooms.add(room);
    return room;
  }

  @override
  Future<void> destroy() async => destroyed++;

  @override
  dynamic noSuchMethod(Invocation call) {
    calls.add(call);
    return Future<void>.value();
  }
}

class _Room implements RtcRoom {
  final calls = <Invocation>[];
  void Function(RtcRoomEvent)? listener;
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  void setEventListener(void Function(RtcRoomEvent)? listener) =>
      this.listener = listener;

  @override
  Future<void> join(RoomJoinConfiguration configuration) async {}

  @override
  Future<void> destroy() async {
    closed = true;
    listener = null;
  }

  @override
  dynamic noSuchMethod(Invocation call) {
    calls.add(call);
    return Future<void>.value();
  }
}

class _Quality implements RtcQualityListener {
  final events = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation call) {
    events.add(call);
    return null;
  }
}
