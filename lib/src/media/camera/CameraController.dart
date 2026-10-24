//
//  CameraController.dart
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
import '../../foundation/permissions/PermissionManager.dart';
import '../../foundation/permissions/PermissionManaging.dart';
import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/RtcManager.dart';
import '../../core/realtime/RealtimeMediaSource.dart';
import '../../render/video/VideoRenderBinding.dart';
import '../../render/video/VideoRenderRegistry.dart';
import '../../service/media/MediaService.dart';
import '../../service/media/MediaServicing.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../../foundation/media/camera/CameraPosition.dart';

/// Requests camera permission and creates a capture track, reporting readiness after the first
/// frame and preview mount.
final class CameraController {

  /// Creates a camera controller.
  ///
  /// Parameters:
  /// - [rtcManager]: The capture and local preview interface.
  /// - [permissionManager]: The permission checker; defaults to system permission checks.
  /// - [mediaService]: The dimension resolver; defaults to the model configuration in
  ///   [MediaService].
  CameraController({
    required RtcManaging rtcManager,
    PermissionManaging permissionManager = const PermissionManager(),
    MediaServicing? mediaService,
  }) : _rtcManager = rtcManager,
       _permissionManager = permissionManager,
       _mediaService = mediaService ?? MediaService();

  /// The internal identifier of the local camera video track.
  static const localVideoTrackID = 'video0';

  /// The internal identifier of the local camera media stream.
  static const localStreamID = 'stream-local';

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// The media capture permission checker.
  final PermissionManaging _permissionManager;

  /// The service that resolves capture, generation, and result dimensions.
  final MediaServicing _mediaService;

  /// The video track owned by the current camera stream.
  RealtimeVideoTrack? _activeTrack;

  /// The video track being created but not yet activated.
  RealtimeVideoTrack? _preparingTrack;

  /// The callback invoked after both camera first-frame capture and preview mounting.
  RealtimeCameraPreviewReadyListener? _previewReadyListener;

  /// Whether the local track has captured a valid first frame.
  bool _hasCapturedFrame = false;

  /// Whether the native local video preview is mounted.
  bool _isPreviewAttached = false;

  /// Whether preview readiness has been reported for the current local track.
  bool _didNotifyPreviewReady = false;

  /// The active local video track; null before creation or after stopping.
  RealtimeVideoTrack? get currentTrack => _activeTrack;

  /// Sets the callback for first-frame capture and native preview readiness.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  ) {
    _previewReadyListener = listener;
    if (_didNotifyPreviewReady) {
      listener?.call();
    }
  }

  /// Creates a camera stream and starts preview, notifying readiness after first-frame capture and
  /// view mounting.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [position]: The camera position, initially front-facing when a stream is created.
  ///
  /// Returns the new local camera stream; the future fails on invalid arguments or denied
  /// permission.
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
  }) async {
    if (_activeTrack != null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Stop the current local camera stream before creating another one',
      );
    }

    final format = _resolveVideoFormat(videoFormat);
    final track = createRealtimeVideoTrack(
      id: localVideoTrackID,
      videoFormat: format,
      position: position,
    );

    _preparingTrack = track;
    _hasCapturedFrame = false;
    _isPreviewAttached = false;
    _didNotifyPreviewReady = false;

    try {
      await _permissionManager.ensureCameraPermission();

      // RtcManager.destroy() clears native callbacks.
      // Retain the preview listener and register it again when recreating the camera stream.
      _rtcManager.setCameraPreviewReadyListener(() => _capturedFrame(track));
      await _rtcManager.switchCamera(position: position);
      await _rtcManager.startVideoCapture(
        width: format.width,
        height: format.height,
        frameRate: format.fps,
      );

      // Register preview rendering only after camera capture starts successfully.
      VideoRenderRegistry.register(
        track,
        LocalVideoRenderBinding(
          onPreviewAttached: () => _previewAttached(track),
          engine: _rtcManager is RtcManager ? _rtcManager.renderEngine : null,
        ),
      );
      _activeTrack = track;
      _notifyPreviewReady(track);

      return createRealtimeMediaStream(
        id: localStreamID,
        videoTrack: track,
      );
    } catch (error) {
      if (identical(
        _preparingTrack,
        track,
      )) {
        _preparingTrack = null;
      }
      // If creation fails, unregister rendering and stop capture together.
      VideoRenderRegistry.unregister(track);

      try {
        await _rtcManager.stopVideoCapture();
      } catch (cleanupError) {
        XmaxLogger.error(
          category: XmaxLoggerCategory.realtime,
          message:
              '回滚 RTC 相机采集失败 (Failed to Roll Back RTC Camera Capture)\n'
              '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$cleanupError',
        );
      }

      throw XmaxError.from(error);
    }
  }

  /// Stops local camera capture and releases resources; the public manager requires a disconnected
  /// session.
  Future<void> stopLocalCameraStream() async {
    final track = _activeTrack;

    _activeTrack = null;
    _preparingTrack = null;
    _hasCapturedFrame = false;
    _isPreviewAttached = false;
    _didNotifyPreviewReady = false;

    if (track != null) {
      VideoRenderRegistry.unregister(track);
    }

    await _rtcManager.stopVideoCapture();
  }

  /// Records first-frame capture for the local track and checks preview readiness.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  void _capturedFrame(
    RealtimeVideoTrack track,
  ) {
    if (!identical(
      _preparingTrack,
      track,
    )) {
      return;
    }

    _hasCapturedFrame = true;
    _notifyPreviewReady(track);
  }

  /// Records that the local track's native preview is mounted.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  void _previewAttached(
    RealtimeVideoTrack track,
  ) {
    if (!identical(
      _preparingTrack,
      track,
    )) {
      return;
    }

    _isPreviewAttached = true;
    _notifyPreviewReady(track);
  }

  /// Reports preview readiness once per track after both first-frame capture and view mounting.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  void _notifyPreviewReady(
    RealtimeVideoTrack track,
  ) {
    if (_didNotifyPreviewReady ||
        !_hasCapturedFrame ||
        !_isPreviewAttached ||
        !identical(
          _activeTrack,
          track,
        )) {
      return;
    }

    _didNotifyPreviewReady = true;
    _previewReadyListener?.call();
  }

  /// Switches between front and rear cameras and returns the updated local media stream.
  ///
  /// Returns the local camera stream after switching cameras.
  Future<RealtimeMediaStream> switchCamera() async {
    final track = _activeTrack;
    final position = track?.position;

    if (track == null || track.videoFormat == null || position == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Local camera preview is not started',
      );
    }

    final next = position == CameraPosition.front
        ? CameraPosition.back
        : CameraPosition.front;

    try {
      await _rtcManager.switchCamera(position: next);
      updateRealtimeVideoTrack(
        track: track,
        position: next,
      );

      return createRealtimeMediaStream(
        id: localStreamID,
        videoTrack: track,
      );
    } catch (error) {
      throw XmaxError.from(error);
    }
  }

  /// Validates and updates capture in place, updating track metadata only after native success.
  ///
  /// Parameters:
  /// - [videoFormat]: The capture format satisfying the current model's constraints.
  Future<void> updateVideoFormat(
    RealtimeVideoFormat videoFormat,
  ) async {
    final track = _activeTrack;

    if (track == null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Camera preview is not started',
      );
    }

    final format = _resolveVideoFormat(videoFormat);

    if (format == track.videoFormat) {
      return;
    }

    await _rtcManager.updateVideoCapture(
      width: format.width,
      height: format.height,
      frameRate: format.fps,
    );
    updateRealtimeVideoTrack(
      track: track,
      videoFormat: format,
    );
  }

  /// Validates and resolves camera capture settings for the current model.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  ///
  /// Returns a validated video format with dimensions, frame rate, and encoding settings.
  RealtimeVideoFormat _resolveVideoFormat(
    RealtimeVideoFormat videoFormat,
  ) {
    videoFormat.validate();

    final size = _mediaService.resolveMediaSize(
      Size(
        videoFormat.width.toDouble(),
        videoFormat.height.toDouble(),
      ),
      source: RealtimeMediaSource.camera,
    );
    final format = videoFormat.resized(
      width: size.width.toInt(),
      height: size.height.toInt(),
    );

    format.validate();

    return format;
  }
}
