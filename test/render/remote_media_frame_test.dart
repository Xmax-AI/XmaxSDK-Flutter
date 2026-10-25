import 'dart:async';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart' as agora;
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk/src/foundation/rtc/AgoraRemoteMediaObserver.dart';
import 'package:xmax_sdk/src/render/video/RealtimeMediaFrameDispatcher.dart';
import 'package:xmax_sdk/src/render/video/RemoteAudioTimeline.dart';

RealtimeAudioFrame _audio(int pts, {int rate = 48000, int samples = 480}) =>
    RealtimeAudioFrame(
      data: Uint8List(samples * 2),
      sampleRate: rate,
      channels: 1,
      samplesPerChannel: samples,
      presentationTimeStamp: Duration(microseconds: pts),
    );
RealtimeVideoFrame _video(int pts, {int rotation = 0}) => RealtimeVideoFrame(
  data: Uint8List(6),
  width: 2,
  height: 2,
  rotation: rotation,
  presentationTimeStamp: Duration(microseconds: pts),
);
Future<void> _drain() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('batched audio advances by samples, not callback arrival', () {
    final timeline = RemoteAudioTimeline();
    for (var index = 0; index < 10; index++) {
      final (packet, gap) = timeline.resolve(_audio(1000000))!;
      expect(
        packet.presentationTimeStamp.inMicroseconds,
        1000000 + index * 10000,
      );
      expect(gap, index == 0);
    }
    final (packet, gap) = timeline.resolve(_audio(1400000))!;
    expect(packet.presentationTimeStamp.inMicroseconds, 1400000);
    expect(gap, isTrue);
  });

  test('fractional sample durations do not accumulate rounding drift', () {
    final timeline = RemoteAudioTimeline();
    for (var index = 0; index < 10000; index++) {
      final pts = 1000000 + index * 128 * 1000000 ~/ 44100;
      final (packet, gap) = timeline.resolve(
        _audio(pts ~/ 1000 * 1000, rate: 44100, samples: 128),
      )!;
      expect(packet.presentationTimeStamp.inMicroseconds, pts);
      expect(gap, index == 0);
    }
    expect(timeline.resolve(_audio(0)), isNull);
    expect(timeline.resolve(_audio(1000000))!.$2, isTrue);
  });

  test(
    'slow callbacks are serial and packet loss marks the next video event',
    () async {
      final dispatcher = RealtimeMediaFrameDispatcher(maximumPendingFrames: 2);
      final output = <RealtimeMediaFrame>[];
      final gate = Completer<void>();
      dispatcher.setListener((frame) async {
        output.add(frame);
        if (frame.content is RealtimeAudioFrame) await gate.future;
      });
      final token = dispatcher.setStream(true)!;
      dispatcher.dispatch(_video(1000), streamID: token);
      await _drain();
      dispatcher.dispatch(_audio(1000000), streamID: token);
      await _drain();
      dispatcher.dispatch(_video(2000), streamID: token);
      dispatcher.dispatch(_video(3000), streamID: token);
      expect(output, hasLength(2));
      gate.complete();
      await _drain();
      dispatcher.dispatch(_video(4000), streamID: token);
      await _drain();
      expect(
        output.map((frame) => frame.presentationTimeStamp.inMicroseconds),
        [1000, 1000000, 2000, 4000],
      );
      expect(output.map((frame) => frame.isDiscontinuous), [
        true,
        true,
        false,
        true,
      ]);
    },
  );

  test(
    'listener replacement discards queued output and preserves active byte limits',
    () async {
      final dispatcher = RealtimeMediaFrameDispatcher(maximumPendingBytes: 6);
      final first = <RealtimeMediaFrame>[], second = <RealtimeMediaFrame>[];
      final gate = Completer<void>();
      dispatcher.setListener((frame) async {
        first.add(frame);
        await gate.future;
      });
      final token = dispatcher.setStream(true)!;
      dispatcher.dispatch(_video(1000), streamID: token);
      await _drain();
      dispatcher.setListener(second.add);
      dispatcher.dispatch(_video(2000), streamID: token);
      gate.complete();
      await _drain();
      expect(second, isEmpty);
      dispatcher.dispatch(_video(3000), streamID: token);
      await _drain();
      expect(second.single.isDiscontinuous, isTrue);
      dispatcher.setListener(null);
      dispatcher.dispatch(_video(4000), streamID: token);
      await _drain();
      expect(second, hasLength(1));
    },
  );

  test(
    'stream replacement rejects old producers and exposes video format changes',
    () async {
      final dispatcher = RealtimeMediaFrameDispatcher();
      final output = <RealtimeMediaFrame>[];
      dispatcher.setListener(output.add);
      final old = dispatcher.setStream(true)!;
      dispatcher.dispatch(_video(1000), streamID: old);
      final current = dispatcher.setStream(true)!;
      expect(current, isNot(old));
      dispatcher.dispatch(_video(2000), streamID: old);
      dispatcher.dispatch(_video(3000), streamID: current);
      dispatcher.dispatch(_video(4000, rotation: 90), streamID: current);
      dispatcher.dispatch(_video(3500, rotation: 90), streamID: current);
      await _drain();
      expect(output, hasLength(3));
      expect(
        output.every(
          (frame) => frame.streamID == current && frame.isDiscontinuous,
        ),
        isTrue,
      );
      dispatcher.setStream(false);
      dispatcher.dispatch(_video(5000), streamID: current);
      await _drain();
      expect(output, hasLength(3));
    },
  );

  test('throwing observers do not prevent later frame delivery', () async {
    final dispatcher = RealtimeMediaFrameDispatcher();
    var calls = 0;
    dispatcher.setListener((_) {
      if (++calls == 1) throw StateError('app failed');
    });
    final token = dispatcher.setStream(true)!;
    dispatcher.dispatch(_video(1000), streamID: token);
    dispatcher.dispatch(_video(2000), streamID: token);
    await _drain();
    expect(calls, 2);
  });

  test(
    'native conversion copies padded I420 planes and filters other users',
    () {
      final output = <RealtimeMediaFrameContent>[];
      final observer = AgoraRemoteMediaObserver(
        channelID: 'room',
        uid: 7,
        listener: output.add,
      );
      final y = Uint8List.fromList([1, 2, 99, 3, 4]);
      final u = Uint8List.fromList([5]), v = Uint8List.fromList([6]);
      final frame = agora.VideoFrame(
        type: agora.VideoPixelFormat.videoPixelI420,
        width: 2,
        height: 2,
        yStride: 3,
        uStride: 1,
        vStride: 1,
        yBuffer: y,
        uBuffer: u,
        vBuffer: v,
        renderTimeMs: 1000,
        rotation: 90,
      );
      observer.video.onRenderVideoFrame!('other', 7, frame);
      observer.video.onRenderVideoFrame!('room', 8, frame);
      expect(output, isEmpty);
      observer.video.onRenderVideoFrame!('room', 7, frame);
      y.fillRange(0, y.length, 0);
      expect((output.single as RealtimeVideoFrame).data, [1, 2, 3, 4, 5, 6]);
      expect((output.single as RealtimeVideoFrame).rotation, 90);
      observer.active = false;
      observer.video.onRenderVideoFrame!('room', 7, frame);
      expect(output, hasLength(1));
    },
  );

  test(
    'native audio is copied before mixing without mixing other remote users',
    () {
      final output = <RealtimeMediaFrameContent>[];
      final observer = AgoraRemoteMediaObserver(
        channelID: 'room',
        uid: 7,
        listener: output.add,
      );
      final data = Uint8List(960)..[0] = 37;
      final frame = agora.AudioFrame(
        buffer: data,
        samplesPerChannel: 480,
        channels: 1,
        samplesPerSec: 48000,
        bytesPerSample: agora.BytesPerSample.twoBytesPerSample,
        renderTimeMs: 1000,
      );
      observer.audio.onPlaybackAudioFrameBeforeMixing!('room', 8, frame);
      expect(output, isEmpty);
      observer.audio.onPlaybackAudioFrameBeforeMixing!('room', 7, frame);
      data[0] = 0;
      expect((output.single as RealtimeAudioFrame).data[0], 37);
    },
  );
}
