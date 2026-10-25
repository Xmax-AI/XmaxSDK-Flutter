import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_file_video_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  setUp(() => calls.clear());
  tearDown(
    () => messenger.setMockMethodCallHandler(
      RealtimeFileVideoSource.channel,
      null,
    ),
  );

  const metadata = {
    'width': 640,
    'height': 480,
    'hasAudio': true,
    'durationUs': 50000,
  };

  test(
    'decoder output dimensions are resolved by the public SDK media service',
    () async {
      Map<Object?, Object?>? opened;
      messenger.setMockMethodCallHandler(RealtimeFileVideoSource.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'probe':
            return {
              'width': 3840,
              'height': 2160,
              'hasAudio': false,
              'durationUs': 1000000,
            };
          case 'open':
            opened = call.arguments as Map<Object?, Object?>;
            return 1;
          case 'read':
            throw PlatformException(code: 'test_end');
          default:
            return null;
        }
      });
      final media = XmaxClient(
        configuration: XmaxConfiguration(apiKey: 'test'),
      ).createMediaService();
      final source = await RealtimeFileVideoSource.make(
        path: '/test/4k.mp4',
        frameRate: 30,
        mediaService: media,
      );
      final sink = _Sink();
      await source.start(sink: sink);
      await sink.failed.future;
      await source.stop();
      expect(
        source.videoFormat.width * source.videoFormat.height,
        lessThanOrEqualTo(2100000),
      );
      expect(source.videoFormat.width % 4, 0);
      expect(source.videoFormat.height % 4, 0);
      expect(opened!['width'], source.videoFormat.width);
      expect(opened!['height'], source.videoFormat.height);
    },
  );

  test(
    'decoded file video and PCM loop on one strictly increasing timeline',
    () async {
      var next = 0;
      messenger.setMockMethodCallHandler(RealtimeFileVideoSource.channel, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'probe':
            return metadata;
          case 'open':
            return 1;
          case 'read':
            switch (next++) {
              case 0:
                return {
                  'timestampUs': 0,
                  'data': Uint8List(640 * 480 * 4),
                  'bgra': true,
                };
              case 1:
                return {
                  'timestampUs': 0,
                  'data': Uint8List(960),
                  'audio': true,
                  'sampleRate': 48000,
                  'channels': 1,
                };
              case 2:
                return {
                  'timestampUs': 33334,
                  'data': Uint8List(640 * 480 * 4),
                  'bgra': true,
                };
              default:
                return null;
            }
          case 'rewind':
            next = 0;
            return null;
          case 'close':
            return null;
        }
        return null;
      });
      final source = await RealtimeFileVideoSource.make(
        path: '/test/video.mp4',
        frameRate: 30,
      );
      final sink = _Sink();
      await source.start(sink: sink);
      await sink.looped.future.timeout(const Duration(seconds: 2));
      await source.stop();
      expect(source.hasAudio, isTrue);
      expect(sink.videos.length, greaterThanOrEqualTo(3));
      for (var index = 1; index < sink.videos.length; index++) {
        expect(sink.videos[index], greaterThan(sink.videos[index - 1]));
      }
      expect(sink.audio.first, sink.videos.first);
      expect(calls, contains('rewind'));
      expect(calls.where((call) => call == 'close').length, 1);
      expect(sink.error, isNull);
      await source.stop();
      expect(calls.where((call) => call == 'close').length, 1);
    },
  );

  test(
    'stopping during native open closes a late decoder without delivering frames',
    () async {
      final opening = Completer<int>();
      final started = Completer<void>();
      messenger.setMockMethodCallHandler(RealtimeFileVideoSource.channel, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'probe':
            return metadata;
          case 'open':
            started.complete();
            return opening.future;
          default:
            return null;
        }
      });
      final source = await RealtimeFileVideoSource.make(
        path: '/test/video.mp4',
        frameRate: 30,
      );
      final sink = _Sink();
      final start = source.start(sink: sink);
      final rejected = expectLater(
        start,
        throwsA(
          isA<XmaxError>().having(
            (e) => e.code,
            'code',
            XmaxErrorCode.cancelled,
          ),
        ),
      );
      await started.future;
      await source.stop();
      opening.complete(4);
      await rejected;
      expect(calls.where((call) => call == 'close').length, 1);
      expect(calls, isNot(contains('read')));
      expect(sink.videos, isEmpty);
    },
  );

  test(
    'decoder failure is reported through the external sink and cleanup still runs',
    () async {
      messenger.setMockMethodCallHandler(RealtimeFileVideoSource.channel, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'probe':
            return metadata;
          case 'open':
            return 1;
          case 'read':
            throw PlatformException(
              code: 'external_video',
              message: 'Decoding failed',
            );
          default:
            return null;
        }
      });
      final source = await RealtimeFileVideoSource.make(
        path: '/test/video.mp4',
        frameRate: 30,
      );
      final sink = _Sink();
      await source.start(sink: sink);
      await sink.failed.future.timeout(const Duration(seconds: 1));
      await source.stop();
      expect(sink.error, isA<PlatformException>());
      expect(calls.last, 'close');
    },
  );
}

class _Sink implements RealtimeExternalFrameSink {
  final videos = <Duration>[];
  final audio = <Duration>[];
  final looped = Completer<void>();
  final failed = Completer<void>();
  Object? error;
  @override
  bool get isRequestingFrames => error == null;
  @override
  RealtimeVideoFormat get videoFormat =>
      const RealtimeVideoFormat(width: 640, height: 480, fps: 30);
  @override
  Future<void> pushVideo(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  }) async {
    expect(frame.pixelFormat, RealtimeExternalVideoPixelFormat.bgra);
    videos.add(timestamp);
    if (videos.length == 3 && !looped.isCompleted) looped.complete();
  }

  @override
  Future<void> pushAudio(
    RealtimeExternalAudioFrame frame, {
    required Duration timestamp,
  }) async {
    expect(frame.sampleRate, 48000);
    audio.add(timestamp);
  }

  @override
  void reportError(Object error) {
    this.error = error;
    if (!failed.isCompleted) failed.complete();
  }
}
