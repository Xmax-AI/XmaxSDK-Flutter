//
//  ExternalVideoFrameSink.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/media/audio/RealtimeExternalAudioFrame.dart';
import '../../foundation/media/video/RealtimeExternalVideoFrame.dart';
import '../../foundation/rtc/RtcManaging.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'ExternalAudioFrameConverter.dart';
import 'RealtimeExternalVideoSource.dart';

/// Validates source frames and bounds in-flight native submissions for one attachment.
final class ExternalVideoFrameSink implements RealtimeExternalFrameSink {

  /// Creates a sink for one external source attachment.
  ExternalVideoFrameSink({
    required this.sourceVideoFormat,
    required this.videoFormat,
    required RtcManaging rtcManager,
    required bool hasAudio,
    required this.errorListener,
  }) : _rtcManager = rtcManager,
       _audioConverter = hasAudio ? ExternalAudioFrameConverter() : null;

  /// The fixed input dimensions and source pacing.
  final RealtimeVideoFormat sourceVideoFormat;

  /// The model-bounded encoding format.
  @override
  final RealtimeVideoFormat videoFormat;

  /// The native preview and upload receiver.
  final RtcManaging _rtcManager;

  /// The optional streaming PCM converter for this binding.
  final ExternalAudioFrameConverter? _audioConverter;

  /// The handler ending the failed local media lifecycle.
  final void Function(
    XmaxError error,
  ) errorListener;

  /// Whether frames and failures are still accepted.
  bool _active = true;

  /// The last accepted video timestamp, in microseconds.
  int _lastTimestamp = -1;

  /// The native video submission retained through detachment.
  Future<void>? _videoTask;

  /// The native audio submission retained through detachment.
  Future<void>? _audioTask;

  /// Whether this attachment accepts source frames.
  @override
  bool get isRequestingFrames => _active;

  /// Copies and submits valid video, dropping input while native delivery is busy.
  ///
  /// See [RealtimeExternalFrameSink.pushVideo] for the usage contract.
  @override
  Future<void> pushVideo(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  }) {
    if (!_active || timestamp.isNegative || timestamp.inMicroseconds <= _lastTimestamp ||
        _videoTask != null) {
      return Future<void>.value();
    }
    try {
      final bgra = frame.pixelFormat == RealtimeExternalVideoPixelFormat.bgra;
      final minimumRowBytes = frame.width * (bgra ? 4 : 1);
      final requiredBytes = frame.rowBytes * frame.height * (bgra ? 2 : 3) ~/ 2;
      if (frame.width != sourceVideoFormat.width || frame.height != sourceVideoFormat.height ||
          frame.rowBytes < minimumRowBytes || frame.rowBytes % (bgra ? 4 : 2) != 0 ||
          frame.data.length < requiredBytes) {
        throw const XmaxError(
          code: XmaxErrorCode.mediaError,
          message: 'External pixels must match the source dimensions and declared row layout',
        );
      }
      final owned = RealtimeExternalVideoFrame(
        data: Uint8List.fromList(frame.data),
        width: frame.width,
        height: frame.height,
        pixelFormat: frame.pixelFormat,
        bytesPerRow: frame.rowBytes,
      );
      _lastTimestamp = timestamp.inMicroseconds;
      final task = _submitVideo(
        owned,
        timestamp,
      );
      _videoTask = task;
      return task.whenComplete(() => _videoTask = null);
    } catch (error) {
      reportError(error);
      return Future<void>.value();
    }
  }

  /// Delivers one owned frame and converts native submission errors into source failure.
  ///
  /// Parameters:
  /// - [frame]: The copied source pixels.
  /// - [timestamp]: The accepted monotonic time.
  Future<void> _submitVideo(
    RealtimeExternalVideoFrame frame,
    Duration timestamp,
  ) async {
    try {
      await _rtcManager.pushExternalVideoFrame(
        frame,
        timestamp: timestamp,
      );
    } catch (error) {
      reportError(error);
    }
  }

  /// Copies and converts opted-in PCM, ignoring concurrent submissions rather than queuing them.
  ///
  /// See [RealtimeExternalFrameSink.pushAudio] for the usage contract.
  @override
  Future<void> pushAudio(
    RealtimeExternalAudioFrame frame, {
    required Duration timestamp,
  }) {
    if (!_active || _audioConverter == null || _audioTask != null) {
      return Future<void>.value();
    }
    try {
      final packets = <(Uint8List, Duration)>[];
      _audioConverter.append(
        RealtimeExternalAudioFrame(
          data: Uint8List.fromList(frame.data),
          sampleRate: frame.sampleRate,
          channels: frame.channels,
          sampleFormat: frame.sampleFormat,
        ),
        timestamp: timestamp,
        emit: (
          data,
          time,
        ) => packets.add((data, time)),
      );
      final task = _submitAudio(packets);
      _audioTask = task;
      return task.whenComplete(() => _audioTask = null);
    } catch (error) {
      reportError(error);
      return Future<void>.value();
    }
  }

  /// Delivers normalized audio packets without sending after attachment invalidation.
  ///
  /// [packets] contains 10 ms PCM16 buffers and their presentation times.
  Future<void> _submitAudio(
    List<(Uint8List, Duration)> packets,
  ) async {
    try {
      for (final packet in packets) {
        if (!_active) {
          return;
        }
        await _rtcManager.pushExternalAudioFrame(
          packet.$1,
          timestamp: packet.$2,
        );
      }
    } catch (error) {
      reportError(error);
    }
  }

  /// Reports only the first source failure and rejects all subsequent input.
  ///
  /// [error] describes a source or frame-processing failure.
  @override
  void reportError(
    Object error,
  ) {
    if (!_active) {
      return;
    }
    _active = false;
    errorListener(
      XmaxError(
        code: XmaxErrorCode.mediaError,
        message: 'External video source failed: ${XmaxError.from(error).message}',
      ),
    );
  }

  /// Rejects input synchronously before native submission cleanup begins.
  void invalidate() {
    _active = false;
  }

  /// Waits for owned native submissions before the RTC engine can be released.
  Future<void> drain() async {
    await _videoTask;
    await _audioTask;
  }
}
