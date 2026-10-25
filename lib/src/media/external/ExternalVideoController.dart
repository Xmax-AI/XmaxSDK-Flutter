//
//  ExternalVideoController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/rtc/RtcManager.dart';
import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/VideoEncodingConfiguration.dart';
import '../../foundation/tasks/OperationCancellation.dart';
import '../../render/video/VideoRenderBinding.dart';
import '../../render/video/VideoRenderRegistry.dart';
import '../../service/media/MediaService.dart';
import '../../service/media/MediaServicing.dart';
import '../../service/media/RealtimeMediaSource.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import 'ExternalVideoControlling.dart';
import 'ExternalVideoFrameSink.dart';
import 'RealtimeExternalVideoSource.dart';

/// Binds external video to native preview and RTC without owning app capture resources.
final class ExternalVideoController implements ExternalVideoControlling {

  /// Creates an external media lifecycle controller.
  ExternalVideoController({
    required RtcManaging rtcManager,
    required this.errorListener,
    MediaServicing? mediaService,
  }) : _rtcManager = rtcManager,
       _mediaService = mediaService ?? MediaService();

  /// The shared native media and RTC adapter.
  final RtcManaging _rtcManager;

  /// The model-aware dimension resolver.
  final MediaServicing _mediaService;

  /// The handler terminating a failed local media lifecycle.
  final void Function(
    XmaxError error,
  ) errorListener;

  /// The currently bound caller-owned source.
  RealtimeExternalVideoSource? _source;

  /// The sink accepting frames for this attachment.
  ExternalVideoFrameSink? _sink;

  /// The track displaying the external source.
  RealtimeVideoTrack? _track;

  /// Whether the current source declared audio before binding.
  bool _hasAudio = false;

  /// The coalesced source-detachment operation.
  Future<void>? _stopping;

  /// The current external video track.
  @override
  RealtimeVideoTrack? get currentTrack => _track;

  /// Whether custom audio upload is enabled.
  @override
  bool get hasAudio => _hasAudio;

  /// Binds a source, becoming ready without waiting for a frame or a mounted view.
  ///
  /// See [ExternalVideoControlling.createExternalVideoStream] for the usage contract.
  @override
  Future<RealtimeMediaStream> createExternalVideoStream({
    required RealtimeExternalVideoSource source,
    Future<void>? cancellation,
  }) async {
    if (_source != null || _stopping != null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Stop the current external video stream before creating another one',
      );
    }

    final requested = source.videoFormat;
    requested.validate();
    final size = _mediaService.resolveMediaSize(
      Size(
        requested.width.toDouble(),
        requested.height.toDouble(),
      ),
      source: RealtimeMediaSource.external,
    );
    final format = requested.resized(
      width: size.width.toInt(),
      height: size.height.toInt(),
    );
    final operation = OperationCancellation(cancellation: cancellation);
    final track = createRealtimeVideoTrack(
      id: 'external0',
      videoFormat: format,
    );
    final sink = ExternalVideoFrameSink(
      sourceVideoFormat: requested,
      videoFormat: format,
      rtcManager: _rtcManager,
      hasAudio: source.hasAudio,
      errorListener: errorListener,
    );
    _source = source;
    _sink = sink;
    _track = track;
    _hasAudio = source.hasAudio;

    try {
      operation.check();
      await _rtcManager.startExternalVideoSource(hasAudio: _hasAudio);
      operation.check();
      await _rtcManager.configureVideoEncoding(
        VideoEncodingConfiguration(
          width: format.width,
          height: format.height,
          frameRate: format.fps,
          minimumBitrate: format.minimumBitrate ?? 0,
          maximumBitrate: format.maximumBitrate ?? -1,
          encoderPreference: format.encoderPreference,
        ),
      );
      operation.check();
      VideoRenderRegistry.register(
        track,
        _rtcManager is RtcManager
            ? LocalVideoRenderBinding.fromStream(_rtcManager.localStream)
            : const LocalVideoRenderBinding.external(),
      );
      await operation.wait(source.start(sink: sink));
      operation.check();
      if (!sink.isRequestingFrames) {
        throw const XmaxError(
          code: XmaxErrorCode.mediaError,
          message: 'External video source failed during setup',
        );
      }
      return createRealtimeMediaStream(
        id: 'stream-local',
        videoTrack: track,
      );
    } catch (error) {
      try {
        await stopExternalVideoStream();
      } catch (cleanup) {
        try {
          XmaxLogger.error(
            category: XmaxLoggerCategory.media,
            message: '解除外部视频源失败 (Failed to Detach External Video Source)\n'
                '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$cleanup',
          );
        } catch (_) {
          // Preserve the startup failure even if cleanup logging fails.
        }
      }
      throw XmaxError.from(error);
    } finally {
      operation.finish();
    }
  }

  /// Invalidates the sink, stops caller frame delivery, and drains native work before release.
  @override
  Future<void> stopExternalVideoStream() {
    final pending = _stopping;
    if (pending != null) {
      return pending;
    }

    final operation = _stop();
    _stopping = operation;
    return operation.whenComplete(() => _stopping = null);
  }

  /// Stops one attachment while preserving the caller's capture and playback ownership.
  Future<void> _stop() async {
    final source = _source;
    final sink = _sink;
    final track = _track;
    if (source == null && sink == null && track == null) {
      return;
    }

    sink?.invalidate();
    _source = null;
    _sink = null;
    _track = null;
    _hasAudio = false;

    try {
      await source?.stop();
    } finally {
      try {
        await sink?.drain();
      } finally {
        if (track != null) {
          VideoRenderRegistry.unregister(track);
        }
        await _rtcManager.stopExternalVideoSource();
      }
    }
  }
}
