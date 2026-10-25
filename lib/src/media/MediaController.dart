//
//  MediaController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../foundation/errors/XmaxError.dart';
import '../foundation/logging/XmaxLogger.dart';
import '../foundation/media/camera/CameraPosition.dart';
import '../foundation/rtc/RtcManaging.dart';
import '../service/realtime/RealtimeMediaStream.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import 'camera/CameraController.dart';
import 'camera/CameraControlling.dart';
import 'interaction/InteractionController.dart';
import 'interaction/InteractionFrame.dart';
import 'external/ExternalVideoController.dart';
import 'external/ExternalVideoControlling.dart';
import 'external/RealtimeExternalVideoSource.dart';
import 'MediaControlling.dart';

/// Coordinates local media ownership and the RTC engine lifecycle.
final class MediaController implements MediaControlling {

  /// Creates a local media controller and connects interaction samples to their handler.
  ///
  /// Parameters:
  /// - [rtcManager]: The capture and transport interface.
  /// - [cameraController]: The camera controller; defaults to one using the same RTC manager.
  /// - [interactionListener]: The handler receiving task identifiers and normalized interaction
  ///   points.
  /// - [externalController]: The external source lifecycle controller.
  /// - [externalErrorListener]: The receiver for unrecoverable external source failures.
  MediaController({
    required RtcManaging rtcManager,
    CameraControlling? cameraController,
    required InteractionListener interactionListener,
    ExternalVideoControlling? externalController,
    void Function(
      XmaxError error,
    )? externalErrorListener,
  }) : _rtcManager = rtcManager,
       _cameraController =
           cameraController ?? CameraController(rtcManager: rtcManager),
       _externalController = externalController ?? ExternalVideoController(
         rtcManager: rtcManager,
         errorListener: externalErrorListener ?? (
           _,
         ) {},
       ),
       _interactionController = InteractionController(
         listener: interactionListener,
       );

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// The controller for camera track creation, preview readiness, and camera switching.
  final CameraControlling _cameraController;

  /// The controller binding caller-owned video and optional audio.
  final ExternalVideoControlling _externalController;

  /// Whether the active or preparing local source is external rather than a camera.
  bool _isExternalSource = false;

  /// The controller that samples and maps interactions for the generation task.
  final InteractionController _interactionController;

  /// Whether a local media stream has been created.
  bool _hasActiveSource = false;

  /// Whether an exclusive local media operation is in progress.
  bool _operationInProgress = false;

  /// The completion notification for the current local media operation.
  Completer<void>? _operationCompletion;

  /// The local media stop operation in progress.
  Future<void>? _stopFuture;

  /// The active local video track; null before creation or after stopping.
  @override
  RealtimeVideoTrack? get currentTrack {
    if (!_hasActiveSource) {
      return null;
    }

    return _isExternalSource ? _externalController.currentTrack : _cameraController.currentTrack;
  }

  /// The current local track's video format; null before creation.
  @override
  RealtimeVideoFormat? get currentVideoFormat => currentTrack?.videoFormat;

  /// Whether the active source opts into microphone or external audio for realtime upload.
  @override
  bool get hasAudio => _hasActiveSource &&
      (_isExternalSource ? _externalController.hasAudio : _cameraController.useMicrophone);

  // Without a local file player, report the fixed preview volume.

  /// The local preview volume; fixed at 0.45 because camera sources have no audio player.
  @override
  Future<double> get localAudioVolume async => 0.45;

  /// Sets the internal local camera first-frame callback.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setCameraPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  ) {
    _cameraController.setPreviewReadyListener(listener);
  }

  /// Creates a local camera stream, starts preview, and notifies the listener when ready.
  ///
  /// See [MediaControlling.createLocalCameraStream] for the usage contract.
  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
    bool useMicrophone = false,
    Future<void>? cancellation,
  }) => _createSource(
    isExternal: false,
    create: (
      _,
    ) => _cameraController.createLocalCameraStream(
      videoFormat: videoFormat,
      position: position,
      useMicrophone: useMicrophone,
    ),
    cancellation: cancellation,
  );

  /// Starts opted-in camera microphone capture without affecting external audio delivery.
  @override
  Future<void> startMicrophoneCapture() async {
    if (_hasActiveSource && !_isExternalSource) {
      await _cameraController.startMicrophoneCapture();
    }
  }

  /// Stops camera microphone capture while retaining the local source and preview.
  @override
  Future<void> stopMicrophoneCapture() async {
    if (_hasActiveSource && !_isExternalSource) {
      await _cameraController.stopMicrophoneCapture();
    }
  }

  /// Binds external capture with the same exclusive engine ownership as camera capture.
  ///
  /// See [MediaControlling.createExternalVideoStream] for the usage contract.
  @override
  Future<RealtimeMediaStream> createExternalVideoStream({
    required RealtimeExternalVideoSource source,
    Future<void>? cancellation,
  }) => _createSource(
    isExternal: true,
    create: (
      signal,
    ) => _externalController.createExternalVideoStream(
      source: source,
      cancellation: signal,
    ),
    cancellation: cancellation,
  );

  /// Acquires the engine for one source, cancelling queued ownership and cleaning failed startup.
  ///
  /// Parameters:
  /// - [isExternal]: Whether the new source supplies its own video frames.
  /// - [create]: The source-specific binding operation.
  /// - [cancellation]: The cancellation signal for engine acquisition and binding.
  ///
  /// Returns the admitted local stream.
  Future<RealtimeMediaStream> _createSource({
    required bool isExternal,
    required Future<RealtimeMediaStream> Function(
      Future<void>? cancellation,
    ) create,
    Future<void>? cancellation,
  }) async {
    if (_hasActiveSource) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Stop the current local media stream before creating another one',
      );
    }

    _ensureNoOperation();

    // Acquire the media operation guard before awaiting RTC initialization to prevent duplicate creation.
    _operationInProgress = true;

    final completion = _operationCompletion = Completer<void>();

    _hasActiveSource = true;
    _isExternalSource = isExternal;
    var isCancelled = false;
    final cancellationSignal = cancellation?.then<void>(
      (
        _,
      ) {
        isCancelled = true;
      },
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        isCancelled = true;
      },
    );

    try {
      await _rtcManager.initialize(cancellation: cancellationSignal);
      if (isCancelled) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Local media creation was cancelled',
        );
      }

      return await create(cancellationSignal);
    } catch (error) {
      _hasActiveSource = false;
      await _releaseEngine();
      throw XmaxError.from(error);
    } finally {
      _operationInProgress = false;
      completion.complete();
    }
  }

  /// Stops local camera capture and releases resources; the public manager requires a disconnected
  /// session.
  @override
  Future<void> stopLocalCameraStream() async {
    if (!_hasActiveSource || _isExternalSource) {
      return;
    }

    await _stopCurrentSource();
  }

  /// Stops the local media source and releases its ownership of the RTC engine.
  @override
  Future<void> stopLocalStream() => _hasActiveSource
      ? _stopCurrentSource()
      : Future<void>.value();

  /// Unbinds only an external source, leaving unrelated camera capture unchanged.
  @override
  Future<void> stopExternalVideoStream() => _hasActiveSource && _isExternalSource
      ? _stopCurrentSource()
      : Future<void>.value();

  /// Share an existing stop operation rather than starting duplicate cleanup.
  Future<void> _stopCurrentSource() {
    final active = _stopFuture;

    if (active != null) {
      return active;
    }

    final future = _performStopCurrentSource();

    _stopFuture = future;

    return future.whenComplete(() => _stopFuture = null);
  }

  /// Waits for the active media operation before stopping capture and releasing resources.
  Future<void> _performStopCurrentSource() async {
    // Wait for capture or camera switching to finish before releasing the shared RTC engine.
    await _operationCompletion?.future;
    _operationInProgress = true;

    try {
      try {
        if (_isExternalSource) {
          await _externalController.stopExternalVideoStream();
        } else {
          await _cameraController.stopLocalCameraStream();
        }
      } catch (error) {
        _logCleanupFailure(
          '停止本地媒体失败 (Failed to Stop Local Media)',
          error,
        );
      }

      await _releaseEngine();
    } finally {
      _hasActiveSource = false;
      _isExternalSource = false;
      _operationInProgress = false;
    }
  }

  /// Releases RTC engine resources owned by the current media source.
  Future<void> _releaseEngine() async {
    try {
      await _rtcManager.destroy();
    } catch (error) {
      _logCleanupFailure(
        '释放 RTC 引擎失败 (Failed to Release RTC Engine)',
        error,
      );
    }
  }

  /// Logs cleanup failures without replacing the operation error.
  ///
  /// Parameters:
  /// - [title]: The log group's title.
  /// - [error]: The operation error.
  void _logCleanupFailure(
    String title,
    Object error,
  ) {
    try {
      XmaxLogger.error(
        category: XmaxLoggerCategory.realtime,
        message: '$title\n└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
      );
    } catch (_) {
      // Logging failures must not interrupt resource cleanup.
    }
  }

  /// Switches between front and rear cameras and returns the updated local media stream.
  ///
  /// Returns the local camera stream after switching cameras.
  @override
  Future<RealtimeMediaStream> switchCamera() async {
    if (!_hasActiveSource || _isExternalSource) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Local camera preview is not started',
      );
    }

    _ensureNoOperation();
    _operationInProgress = true;

    final completion = _operationCompletion = Completer<void>();

    try {
      return await _cameraController.switchCamera();
    } finally {
      _operationInProgress = false;
      completion.complete();
    }
  }

  /// Updates the camera format in place, excluding concurrent local media operations.
  ///
  /// Parameters:
  /// - [videoFormat]: The capture format satisfying the current model's constraints.
  @override
  Future<void> updateCameraFormat(
    RealtimeVideoFormat videoFormat,
  ) async {
    if (_isExternalSource) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Camera format changes require a camera source',
      );
    }
    _ensureNoOperation();
    _operationInProgress = true;

    final completion = _operationCompletion = Completer<void>();

    try {
      await _cameraController.updateVideoFormat(videoFormat);
    } finally {
      _operationInProgress = false;
      completion.complete();
    }
  }

  /// Validates local volume; camera sources have no audio player and continue to report 0.45.
  ///
  /// Parameters:
  /// - [volume]: A finite volume value between 0 and 1.
  @override
  Future<void> setLocalAudioVolume(
    double volume,
  ) async {
    // Camera sources have no local player; validate the value without changing playback volume.
  }

  /// Checks whether a stream belongs to the current local media lifecycle.
  ///
  /// See [MediaControlling.owns] for the usage contract.
  @override
  bool owns(
    RealtimeMediaStream stream,
  ) {
    final track = stream.videoTrack;

    return track != null && identical(
      track,
      currentTrack,
    );
  }

  /// Enables interaction for the current task and clears pending samples from the previous task.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  @override
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  }) {
    _interactionController.startInteraction(
      taskID: taskID,
      videoFormat: videoFormat,
    );
  }

  /// Stops interaction input and invalidates pending samples.
  @override
  void stopInteraction() {
    _interactionController.stopInteraction();
  }

  /// Submits view interaction samples; ignored when no generation task is active.
  ///
  /// Parameters:
  /// - [frame]: A view interaction sample.
  @override
  void submitInteraction(
    InteractionFrame frame,
  ) {
    _interactionController.submitInteraction(frame);
  }

  /// Checks that no conflicting local media operation is active.
  void _ensureNoOperation() {
    if (_operationInProgress) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'A local media operation is already in progress',
      );
    }
  }
}
