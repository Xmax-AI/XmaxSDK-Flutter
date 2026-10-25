import 'dart:async';

import 'package:flutter/services.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

/// App-owned file decoding demonstrates the SDK's external video and PCM input.
final class RealtimeFileVideoSource extends RealtimeExternalVideoSource {
  RealtimeFileVideoSource._({
    required this.path,
    required this.videoFormat,
    required this.hasAudio,
    required this.duration,
  });

  static const channel = MethodChannel('ai.xmax.xlab/external_video');

  final String path;
  @override
  final RealtimeVideoFormat videoFormat;
  @override
  final bool hasAudio;
  final Duration duration;

  int _version = 0;
  int? _decoder;
  Future<void>? _playback;
  Completer<void>? _cancellation;
  Timer? _wakeUpTimer;

  static Future<RealtimeFileVideoSource> make({
    required String path,
    required int frameRate,
    MediaServicing? mediaService,
  }) async {
    final info = await channel.invokeMapMethod<String, Object?>('probe', {
      'path': path,
    });
    if (info == null) throw StateError('Missing external video metadata');
    final original = Size(
      (info['width'] as num).toDouble(),
      (info['height'] as num).toDouble(),
    );
    final size =
        mediaService?.resolveMediaSize(
          original,
          source: RealtimeMediaSource.external,
        ) ??
        original;
    final format = RealtimeVideoFormat(
      width: size.width.toInt(),
      height: size.height.toInt(),
      fps: frameRate,
    );
    format.validate();
    final duration = Duration(
      microseconds: (info['durationUs'] as num).toInt(),
    );
    if (duration <= Duration.zero) throw StateError('Invalid video duration');
    return RealtimeFileVideoSource._(
      path: path,
      videoFormat: format,
      hasAudio: info['hasAudio'] == true,
      duration: duration,
    );
  }

  @override
  Future<void> start({required RealtimeExternalFrameSink sink}) async {
    if (_cancellation != null) {
      throw StateError('The source is already running');
    }
    final version = ++_version;
    final cancellation = _cancellation = Completer<void>();
    final decoder = await channel.invokeMethod<int>('open', {
      'path': path,
      'fps': videoFormat.fps,
      'width': videoFormat.width,
      'height': videoFormat.height,
    });
    if (decoder == null) throw StateError('Could not create the video decoder');
    if (version != _version || !sink.isRequestingFrames) {
      await channel.invokeMethod<void>('close', {'id': decoder});
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Source startup cancelled',
      );
    }
    _decoder = decoder;
    _playback = _play(decoder, sink, cancellation.future).catchError((
      Object error,
    ) {
      if (version == _version && sink.isRequestingFrames) {
        sink.reportError(error);
      }
    });
  }

  Future<void> _play(
    int decoder,
    RealtimeExternalFrameSink sink,
    Future<void> cancellation,
  ) async {
    final clock = Stopwatch()..start();
    final version = _version;
    var loopStartUs = 20000;
    var lastVideoUs = -1000000;
    while (version == _version && sink.isRequestingFrames) {
      final frame = await channel.invokeMapMethod<String, Object?>('read', {
        'id': decoder,
      });
      if (version != _version || !sink.isRequestingFrames) return;
      if (frame == null) {
        await channel.invokeMethod<void>('rewind', {'id': decoder});
        final next = loopStartUs + duration.inMicroseconds;
        loopStartUs = next > clock.elapsedMicroseconds + 20000
            ? next
            : clock.elapsedMicroseconds + 20000;
        continue;
      }
      final sourceTimeUs = (frame['timestampUs'] as num).toInt();
      if (sourceTimeUs < 0) continue;
      final targetUs = loopStartUs + sourceTimeUs;
      final audio = frame['audio'] == true;
      final lateness = clock.elapsedMicroseconds - targetUs;
      if (lateness > (audio ? 100000 : 1000000 ~/ videoFormat.fps) ||
          targetUs < 0) {
        continue;
      }
      if (!audio && targetUs - lastVideoUs < 1000000 ~/ videoFormat.fps) {
        continue;
      }
      final waitUs = targetUs - clock.elapsedMicroseconds;
      if (waitUs > 0) {
        final wakeUp = Completer<void>();
        _wakeUpTimer = Timer(
          Duration(microseconds: waitUs),
          () => wakeUp.complete(),
        );
        await Future.any<void>([wakeUp.future, cancellation]);
        _wakeUpTimer?.cancel();
        _wakeUpTimer = null;
      }
      if (version != _version || !sink.isRequestingFrames) return;
      final data = frame['data'] as Uint8List;
      final timestamp = Duration(microseconds: targetUs);
      if (audio) {
        await sink.pushAudio(
          RealtimeExternalAudioFrame(
            data: data,
            sampleRate: (frame['sampleRate'] as num).toInt(),
            channels: (frame['channels'] as num).toInt(),
            sampleFormat: frame['float32'] == true
                ? RealtimeExternalAudioSampleFormat.float32
                : RealtimeExternalAudioSampleFormat.pcm16,
          ),
          timestamp: timestamp,
        );
      } else {
        lastVideoUs = targetUs;
        await sink.pushVideo(
          RealtimeExternalVideoFrame(
            data: data,
            width: videoFormat.width,
            height: videoFormat.height,
            pixelFormat: frame['bgra'] == true
                ? RealtimeExternalVideoPixelFormat.bgra
                : RealtimeExternalVideoPixelFormat.nv12,
          ),
          timestamp: timestamp,
        );
      }
    }
  }

  @override
  Future<void> stop() async {
    _version += 1;
    _wakeUpTimer?.cancel();
    _wakeUpTimer = null;
    final cancellation = _cancellation;
    _cancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final playback = _playback;
    _playback = null;
    await playback;
    final decoder = _decoder;
    _decoder = null;
    if (decoder != null) {
      await channel.invokeMethod<void>('close', {'id': decoder});
    }
  }
}
