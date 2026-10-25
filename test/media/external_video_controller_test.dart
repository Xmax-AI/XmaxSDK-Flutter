import 'dart:async';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/src/media/external/ExternalVideoController.dart';
import 'package:xmax_sdk/src/media/external/ExternalVideoFrameSink.dart';
import 'package:xmax_sdk/src/media/MediaController.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderRegistry.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderBinding.dart';

const format = RealtimeVideoFormat(width: 640, height: 480, fps: 30);

RealtimeExternalVideoFrame pixels([int width = 640]) =>
    RealtimeExternalVideoFrame(
      data: Uint8List(width * 480 * 4),
      width: width,
      height: 480,
      pixelFormat: RealtimeExternalVideoPixelFormat.bgra,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'media owns one source and stops external input rather than camera capture',
    () async {
      final rtc = FakeExternalRtc();
      final media = MediaController(
        rtcManager: rtc,
        interactionListener: (_, _) async {},
      );
      final source = FakeExternalSource(audio: true);
      final stream = await media.createExternalVideoStream(source: source);
      expect(media.owns(stream), isTrue);
      expect(media.hasAudio, isTrue);
      await expectLater(
        media.createLocalCameraStream(
          videoFormat: format,
          position: CameraPosition.front,
        ),
        throwsA(isA<XmaxError>()),
      );
      await expectLater(media.switchCamera(), throwsA(isA<XmaxError>()));
      await media.stopLocalCameraStream();
      expect(media.currentTrack, same(stream.videoTrack));
      await media.stopLocalStream();
      expect(media.currentTrack, isNull);
      expect(source.stops, 1);
      expect(rtc.destroyed, 1);
    },
  );

  test(
    'NV12 accepts padded rows and rejects incomplete pixel planes',
    () async {
      final rtc = FakeExternalRtc();
      final errors = <XmaxError>[];
      final sink = ExternalVideoFrameSink(
        sourceVideoFormat: format,
        videoFormat: format,
        rtcManager: rtc,
        hasAudio: false,
        errorListener: errors.add,
      );
      await sink.pushVideo(
        RealtimeExternalVideoFrame(
          data: Uint8List(648 * 480 * 3 ~/ 2),
          width: 640,
          height: 480,
          pixelFormat: RealtimeExternalVideoPixelFormat.nv12,
          bytesPerRow: 648,
        ),
        timestamp: Duration.zero,
      );
      expect(rtc.videos.single.rowBytes, 648);
      await sink.pushVideo(
        RealtimeExternalVideoFrame(
          data: Uint8List(10),
          width: 640,
          height: 480,
          pixelFormat: RealtimeExternalVideoPixelFormat.nv12,
        ),
        timestamp: const Duration(milliseconds: 40),
      );
      expect(errors.length, 1);
      expect(sink.isRequestingFrames, isFalse);
    },
  );

  test(
    'binding is ready without frames, camera permission, or camera capture',
    () async {
      final rtc = FakeExternalRtc();
      final errors = <XmaxError>[];
      final controller = ExternalVideoController(
        rtcManager: rtc,
        errorListener: errors.add,
      );
      final source = FakeExternalSource();
      final stream = await controller.createExternalVideoStream(source: source);
      expect(stream.videoTrack, same(controller.currentTrack));
      expect(controller.currentTrack!.position, isNull);
      expect(controller.hasAudio, isFalse);
      expect(
        (VideoRenderRegistry.handleFor(stream.videoTrack!)!.value
                as LocalVideoRenderBinding)
            .sourceType,
        VideoSourceType.videoSourceCustom,
      );
      expect(source.sink!.isRequestingFrames, isTrue);
      expect(rtc.videos, isEmpty);
      await source.sink!.pushVideo(pixels(), timestamp: Duration.zero);
      expect(rtc.videos.length, 1);
      await controller.stopExternalVideoStream();
      expect(source.stops, 1);
      expect(source.sink!.isRequestingFrames, isFalse);
      expect(controller.currentTrack, isNull);
      expect(VideoRenderRegistry.handleFor(stream.videoTrack!), isNull);
      expect(errors, isEmpty);
    },
  );

  test(
    'external dimensions avoid camera buckets and retain source encoding settings',
    () async {
      final rtc = FakeExternalRtc();
      final controller = ExternalVideoController(
        rtcManager: rtc,
        errorListener: (_) {},
      );
      final source = FakeExternalSource(
        format: const RealtimeVideoFormat(
          width: 3840,
          height: 2160,
          fps: 24,
          minimumBitrate: 100,
          maximumBitrate: 1800,
          encoderPreference: RealtimeVideoEncoderPreference.maintainQuality,
        ),
        audio: true,
      );
      await controller.createExternalVideoStream(source: source);
      final resolved = source.sink!.videoFormat;
      expect(resolved.width % 4, 0);
      expect(resolved.height % 4, 0);
      expect(resolved.width * resolved.height, lessThanOrEqualTo(2100000));
      expect(resolved.fps, 24);
      expect(resolved.maximumBitrate, 1800);
      expect(
        rtc.encoding!.encoderPreference,
        RealtimeVideoEncoderPreference.maintainQuality,
      );
      expect(rtc.audioEnabled, isTrue);
      await controller.stopExternalVideoStream();
    },
  );

  test(
    'source startup failure stops delivery and removes the preview binding',
    () async {
      final rtc = FakeExternalRtc();
      final controller = ExternalVideoController(
        rtcManager: rtc,
        errorListener: (_) {},
      );
      final source = FakeExternalSource()
        ..startError = StateError('decoder failed');
      await expectLater(
        controller.createExternalVideoStream(source: source),
        throwsA(isA<XmaxError>()),
      );
      expect(source.stops, 1);
      expect(source.sink!.isRequestingFrames, isFalse);
      expect(controller.currentTrack, isNull);
      expect(rtc.stops, 1);
    },
  );

  test(
    'cancelled startup detaches the sink and ignores a late producer',
    () async {
      final rtc = FakeExternalRtc();
      final controller = ExternalVideoController(
        rtcManager: rtc,
        errorListener: (_) {},
      );
      final source = FakeExternalSource()..startGate = Completer<void>();
      final cancellation = Completer<void>();
      final result = controller.createExternalVideoStream(
        source: source,
        cancellation: cancellation.future,
      );
      final failed = expectLater(
        result,
        throwsA(
          isA<XmaxError>().having(
            (e) => e.code,
            'code',
            XmaxErrorCode.cancelled,
          ),
        ),
      );
      await source.started.future;
      cancellation.complete();
      await failed;
      source.startGate!.complete();
      await source.sink!.pushVideo(pixels(), timestamp: Duration.zero);
      expect(rtc.videos, isEmpty);
      expect(source.stops, 1);
    },
  );

  test(
    'duplicate source binding is rejected and repeated stop is harmless',
    () async {
      final controller = ExternalVideoController(
        rtcManager: FakeExternalRtc(),
        errorListener: (_) {},
      );
      final source = FakeExternalSource();
      await controller.createExternalVideoStream(source: source);
      await expectLater(
        controller.createExternalVideoStream(source: FakeExternalSource()),
        throwsA(isA<XmaxError>()),
      );
      await controller.stopExternalVideoStream();
      await controller.stopExternalVideoStream();
      expect(source.stops, 1);
    },
  );

  test(
    'sink copies bytes, filters timestamps, and bounds in-flight video',
    () async {
      final rtc = FakeExternalRtc()..videoGate = Completer<void>();
      final sink = ExternalVideoFrameSink(
        sourceVideoFormat: format,
        videoFormat: format,
        rtcManager: rtc,
        hasAudio: false,
        errorListener: (_) {},
      );
      final frame = pixels();
      frame.data[0] = 12;
      final first = sink.pushVideo(
        frame,
        timestamp: const Duration(microseconds: 20),
      );
      frame.data[0] = 99;
      expect(rtc.videos.single.data[0], 12);
      await sink.pushVideo(frame, timestamp: const Duration(microseconds: 30));
      expect(rtc.videos.length, 1);
      rtc.videoGate!.complete();
      await first;
      rtc.videoGate = null;
      for (final time in [-1, 19, 20]) {
        await sink.pushVideo(frame, timestamp: Duration(microseconds: time));
      }
      expect(rtc.videos.length, 1);
      await sink.pushVideo(frame, timestamp: const Duration(microseconds: 40));
      expect(rtc.videos.length, 2);
    },
  );

  test(
    'frame failure is fatal once; invalidated sinks reject video and errors',
    () async {
      final rtc = FakeExternalRtc();
      final errors = <XmaxError>[];
      final sink = ExternalVideoFrameSink(
        sourceVideoFormat: format,
        videoFormat: format,
        rtcManager: rtc,
        hasAudio: false,
        errorListener: errors.add,
      );
      await sink.pushVideo(pixels(644), timestamp: Duration.zero);
      expect(sink.isRequestingFrames, isFalse);
      sink.reportError(StateError('late'));
      await sink.pushVideo(pixels(), timestamp: const Duration(seconds: 1));
      expect(errors.length, 1);
      expect(errors.single.code, XmaxErrorCode.mediaError);
      expect(rtc.videos, isEmpty);
    },
  );

  test(
    'detachment waits for native video submission before releasing resources',
    () async {
      final rtc = FakeExternalRtc()..videoGate = Completer<void>();
      final controller = ExternalVideoController(
        rtcManager: rtc,
        errorListener: (_) {},
      );
      final source = FakeExternalSource();
      await controller.createExternalVideoStream(source: source);
      final submit = source.sink!.pushVideo(pixels(), timestamp: Duration.zero);
      var detached = false;
      final stop = controller.stopExternalVideoStream().then(
        (_) => detached = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(detached, isFalse);
      expect(source.sink!.isRequestingFrames, isFalse);
      expect(rtc.stops, 0);
      rtc.videoGate!.complete();
      await submit;
      await stop;
      expect(rtc.stops, 1);
    },
  );

  test(
    'audio is opt-in, copied, and packetized at 48 kHz without local playback',
    () async {
      final rtc = FakeExternalRtc();
      for (final enabled in [false, true]) {
        final sink = ExternalVideoFrameSink(
          sourceVideoFormat: format,
          videoFormat: format,
          rtcManager: rtc,
          hasAudio: enabled,
          errorListener: (_) {},
        );
        await sink.pushAudio(
          RealtimeExternalAudioFrame(
            data: Uint8List(1920),
            sampleRate: 48000,
            channels: 1,
          ),
          timestamp: const Duration(seconds: 2),
        );
        expect(rtc.audio.length, enabled ? 2 : 0);
      }
      expect(rtc.audio.first.$1.length, 960);
      expect(rtc.audio.first.$2, const Duration(seconds: 2));
      expect(rtc.audio.last.$2, const Duration(milliseconds: 2010));
    },
  );
}

class FakeExternalSource extends RealtimeExternalVideoSource {
  FakeExternalSource({
    this.format = const RealtimeVideoFormat(width: 640, height: 480, fps: 30),
    this.audio = false,
  });
  final RealtimeVideoFormat format;
  final bool audio;
  RealtimeExternalFrameSink? sink;
  Object? startError;
  Completer<void>? startGate;
  final started = Completer<void>();
  int stops = 0;
  @override
  RealtimeVideoFormat get videoFormat => format;
  @override
  bool get hasAudio => audio;
  @override
  Future<void> start({required RealtimeExternalFrameSink sink}) async {
    this.sink = sink;
    started.complete();
    if (startError != null) throw startError!;
    await startGate?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class FakeExternalRtc implements RtcManaging {
  int destroyed = 0;
  bool? audioEnabled;
  int stops = 0;
  VideoEncodingConfiguration? encoding;
  Completer<void>? videoGate;
  final videos = <RealtimeExternalVideoFrame>[];
  final audio = <(Uint8List, Duration)>[];
  @override
  Future<void> initialize({Future<void>? cancellation}) async {}
  @override
  Future<void> destroy() async {
    destroyed++;
  }

  @override
  Future<void> startExternalVideoSource({required bool hasAudio}) async {
    audioEnabled = hasAudio;
  }

  @override
  Future<void> stopExternalVideoSource() async {
    stops++;
  }

  @override
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  ) async {
    encoding = configuration;
  }

  @override
  Future<void> pushExternalVideoFrame(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  }) async {
    videos.add(frame);
    await videoGate?.future;
  }

  @override
  Future<void> pushExternalAudioFrame(
    Uint8List data, {
    required Duration timestamp,
  }) async {
    audio.add((data, timestamp));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RTC call: ${invocation.memberName}');
}
