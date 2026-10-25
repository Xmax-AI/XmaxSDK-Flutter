import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/render/RenderController.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';

class _Rtc implements RtcManaging {
  final bindings =
      <(RemoteStream?, void Function(RealtimeMediaFrameContent)?)>[];
  Completer<void>? gate;
  @override
  Future<void> setRemoteMediaFrameListener({
    required RemoteStream? stream,
    required void Function(RealtimeMediaFrameContent)? listener,
  }) async {
    bindings.add((stream, listener));
    final current = gate;
    gate = null;
    await current?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

const stream = RemoteStream(roomID: 'room', userID: 'bot', streamID: 'bot');
RealtimeVideoFrame video(int pts) => RealtimeVideoFrame(
  data: Uint8List(6),
  width: 2,
  height: 2,
  presentationTimeStamp: Duration(microseconds: pts),
);
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test(
    'failed observer replacement restores the last successful callback',
    () async {
      final rtc = _Rtc();
      final original = <RealtimeMediaFrame>[],
          rejected = <RealtimeMediaFrame>[];
      final render = RenderController(rtcManager: rtc);
      final track = createRealtimeVideoTrack(id: 'remote');
      render.registerRemoteTrack(track, interactionListener: (_) {});
      render.setRemoteStream(stream);
      await settle();
      await render.setRemoteMediaFrameListener(original.add);
      final gate = Completer<void>();
      rtc.gate = gate;
      final replacement = render.setRemoteMediaFrameListener(rejected.add);
      final failure = expectLater(replacement, throwsStateError);
      await settle();
      gate.completeError(StateError('native observer unavailable'));
      await failure;
      await settle();
      rtc.bindings.last.$2!(video(1000));
      await settle();
      expect(original, hasLength(1));
      expect(rejected, isEmpty);
      render.resetRemoteTrack(track);
      await settle();
    },
  );
  test(
    'listener can precede generation and old producers cannot reach a new binding',
    () async {
      final rtc = _Rtc(), output = <RealtimeMediaFrame>[];
      final render = RenderController(rtcManager: rtc);
      await render.setRemoteMediaFrameListener(output.add);
      expect(rtc.bindings.single.$2, isNull);
      final track = createRealtimeVideoTrack(id: 'remote');
      render.registerRemoteTrack(track, interactionListener: (_) {});
      render.setRemoteStream(stream);
      await settle();
      final old = rtc.bindings.last.$2!;
      old(video(1000));
      await settle();
      final token = output.single.streamID;
      render.setRemoteStream(null);
      old(video(2000));
      render.setRemoteStream(stream);
      await settle();
      old(video(3000));
      rtc.bindings.last.$2!(video(4000));
      await settle();
      expect(output, hasLength(2));
      expect(output.last.streamID, isNot(token));
      expect(output.last.presentationTimeStamp.inMicroseconds, 4000);
      await render.setRemoteMediaFrameListener(null);
      expect(rtc.bindings.last.$2, isNull);
      render.resetRemoteTrack(track);
      await settle();
    },
  );

  test(
    'expired observer configuration failure does not interrupt a later binding',
    () async {
      final rtc = _Rtc(), errors = <Object>[];
      final render = RenderController(rtcManager: rtc, onError: errors.add);
      final track = createRealtimeVideoTrack(id: 'remote');
      await render.setRemoteMediaFrameListener((_) {});
      render.registerRemoteTrack(track, interactionListener: (_) {});
      final gate = Completer<void>();
      rtc.gate = gate;
      render.setRemoteStream(stream);
      await settle();
      render.resetRemoteTrack(track);
      gate.completeError(StateError('old native failure'));
      await settle();
      expect(errors, isEmpty);
      expect(rtc.bindings.last.$2, isNull);
    },
  );
}
