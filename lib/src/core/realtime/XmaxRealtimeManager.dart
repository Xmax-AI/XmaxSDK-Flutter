//
//  XmaxRealtimeManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/media/camera/CameraPosition.dart';
import '../../foundation/rtc/VideoStatistics.dart';
import '../../media/MediaControlling.dart';
import '../../service/network/ApiServicing.dart';
import '../../service/realtime/RealtimeCameraPreset.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeState.dart';
import '../../service/realtime/RealtimeTiming.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../stream/StreamControlling.dart';
import '../../stream/quality/RealtimeQualityLevel.dart';
import 'RealtimeConfiguration.dart';
import 'XmaxRealtimeConnectionManager.dart';
import 'XmaxRealtimeErrorManager.dart';
import 'XmaxRealtimeFactory.dart';
import 'XmaxRealtimeGenerationManager.dart';
import 'XmaxRealtimeLifecycleManager.dart';
import 'XmaxRealtimeManaging.dart';

/// Implements the public realtime API and sequences media, connection, and generation workflows.
final class XmaxRealtimeManager implements XmaxRealtimeManaging {

  /// Creates and wires the realtime components for the selected model.
  ///
  /// Creation does not request permissions, start capture, or open a network connection.
  ///
  /// Parameters:
  /// - [options]: The model and media configuration.
  /// - [apiService]: The API service used for server sessions.
  factory XmaxRealtimeManager({
    required RealtimeConfiguration options,
    required ApiServicing apiService,
  }) => XmaxRealtimeManager._(
    options: options,
    components: XmaxRealtimeFactory.make(
      options: options,
      apiService: apiService,
    ),
  );

  /// Creates a manager with injected components and shared lifecycle coordination.
  ///
  /// Parameters:
  /// - [options]: The realtime model configuration.
  /// - [mediaController]: The local capture and interaction controller.
  /// - [streamController]: The RTC transport and signaling controller.
  /// - [connectionManager]: The server session and RTC connection manager.
  /// - [generationManager]: The generation conditions and task manager.
  /// - [errorManager]: The shared runtime failure manager.
  factory XmaxRealtimeManager.internal({
    required RealtimeConfiguration options,
    required MediaControlling mediaController,
    required StreamControlling streamController,
    required XmaxRealtimeConnectionManager connectionManager,
    required XmaxRealtimeGenerationManager generationManager,
    required XmaxRealtimeErrorManager errorManager,
  }) => XmaxRealtimeManager._(
    options: options,
    components: XmaxRealtimeFactory.assemble(
      mediaController: mediaController,
      streamController: streamController,
      connectionManager: connectionManager,
      generationManager: generationManager,
      errorManager: errorManager,
    ),
  );

  /// Creates the public facade over an assembled realtime component bundle.
  ///
  /// Parameters:
  /// - [options]: The realtime model configuration.
  /// - [components]: The components sharing lifecycle state and failure handling.
  XmaxRealtimeManager._({
    required this.options,
    required XmaxRealtimeComponents components,
  }) : _mediaController = components.mediaController,
       _streamController = components.streamController,
       _connectionManager = components.connectionManager,
       _generationManager = components.generationManager,
       _errorManager = components.errorManager,
       _lifecycleManager = components.lifecycleManager;

  /// The realtime model configuration used by this manager.
  @override
  final RealtimeConfiguration options;

  /// The controller that owns local camera streams and their resources.
  final MediaControlling _mediaController;

  /// The controller that manages RTC publishing, subscriptions, and signaling.
  final StreamControlling _streamController;

  /// The manager that owns the server session and RTC connection.
  final XmaxRealtimeConnectionManager _connectionManager;

  /// The manager that owns task identifiers, conditions, and interaction lifecycle.
  final XmaxRealtimeGenerationManager _generationManager;

  /// The failure handler that isolates expired operations from current connections and media.
  final XmaxRealtimeErrorManager _errorManager;

  /// The coordinator owning state, operation revisions, and resource termination.
  final XmaxRealtimeLifecycleManager _lifecycleManager;

  /// The current realtime lifecycle state.
  RealtimeState get _state => _lifecycleManager.currentState;

  /// Whether an in-place camera format update is active.
  bool _isUpdatingCameraFormat = false;

  /// The camera capture format, unchanged by transport quality levels.
  @override
  Future<RealtimeVideoFormat?> get currentCameraVideoFormat async =>
      _mediaController.currentTrack?.position == null
      ? null
      : _mediaController.currentVideoFormat;

  /// The preset matching the current camera dimensions.
  @override
  Future<RealtimeCameraPreset?> get currentCameraPreset async {
    final format = await currentCameraVideoFormat;

    if (format == null) {
      return null;
    }

    for (final preset in RealtimeCameraPreset.values) {
      if (preset.size.width == format.width &&
          preset.size.height == format.height) {
        return preset;
      }
    }

    return null;
  }

  /// Whether the connected or generating state exposes connection quality levels.
  bool get _hasConnectedQuality =>
      _state.connectionState == RealtimeConnectionState.connected ||
      _state.connectionState == RealtimeConnectionState.generating;

  /// The applied uplink quality level for the current connection.
  @override
  Future<RealtimeQualityLevel?> get uplinkQualityLevel async =>
      _hasConnectedQuality
      ? _streamController.qualityConfiguration?.uplinkLevel
      : null;

  /// The submitted downlink target level for the current connection.
  @override
  Future<RealtimeQualityLevel?> get downlinkQualityLevel async =>
      _hasConnectedQuality
      ? _streamController.qualityConfiguration?.downlinkLevel
      : null;

  /// Changes the uplink level during generation.
  ///
  /// See [XmaxRealtimeManaging.setUplinkQualityLevel] for the usage contract.
  @override
  Future<void> setUplinkQualityLevel(
    RealtimeQualityLevel level,
  ) => _setQualityLevel(
    level,
    downlink: false,
  );

  /// Changes the downlink target level during generation.
  ///
  /// See [XmaxRealtimeManaging.setDownlinkQualityLevel] for the usage contract.
  @override
  Future<void> setDownlinkQualityLevel(
    RealtimeQualityLevel level,
  ) => _setQualityLevel(
    level,
    downlink: true,
  );

  /// Validates generation state and delegates manual quality changes to transport.
  ///
  /// Parameters:
  /// - [level]: The requested transport quality level.
  /// - [downlink]: Whether to update downlink rather than uplink.
  Future<void> _setQualityLevel(
    RealtimeQualityLevel level, {
    required bool downlink,
  }) async {
    if (_state.connectionState != RealtimeConnectionState.generating) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Quality levels can only be changed while generating',
      );
    }

    await _streamController.setQualityLevel(
      level,
      downlink: downlink,
    );
  }

  /// Updates capture settings while retaining the local track and preview bindings.
  ///
  /// See [XmaxRealtimeManaging.updateCameraFormat] for the usage contract.
  @override
  Future<void> updateCameraFormat({
    RealtimeVideoFormat? videoFormat,
    RealtimeCameraPreset? preset,
  }) async {
    final current = _mediaController.currentVideoFormat;

    if ((videoFormat == null) == (preset == null) ||
        _isUpdatingCameraFormat ||
        current == null ||
        _state.connectionState != RealtimeConnectionState.ready ||
        _connectionManager.currentSessionID.isNotEmpty ||
        _lifecycleManager.isClosing ||
        _lifecycleManager.isDisconnecting) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Provide exactly one camera format or preset '
            'while preview is ready and disconnected',
      );
    }

    final format = videoFormat ??
        current.resized(
          width: preset!.size.width.toInt(),
          height: preset.size.height.toInt(),
        );
    final version = _lifecycleManager.operationVersion;

    _isUpdatingCameraFormat = true;

    try {
      await _mediaController.updateCameraFormat(format);
      _lifecycleManager.ensureCurrent(version);
    } catch (error) {
      throw XmaxError.from(error);
    } finally {
      _isUpdatingCameraFormat = false;
    }
  }

  /// The current connection and generation state.
  ///
  /// See [XmaxRealtimeManaging.currentState] for the usage contract.
  @override
  Future<RealtimeState> get currentState async => _state;

  /// The local media preview volume, from 0 to 1.
  ///
  /// See [XmaxRealtimeManaging.localAudioVolume] for the usage contract.
  @override
  Future<double> get localAudioVolume => _mediaController.localAudioVolume;

  /// The remote audio playback volume, from 0 to 1 in increments of 0.01.
  ///
  /// See [XmaxRealtimeManaging.remoteAudioVolume] for the usage contract.
  @override
  Future<double> get remoteAudioVolume async =>
      _streamController.remoteAudioVolume;

  /// Sets the state listener and immediately delivers the current state.
  ///
  /// See [XmaxRealtimeManaging.setStateListener] for the usage contract.
  @override
  Future<void> setStateListener(
    RealtimeStateListener? listener,
  ) async {
    _lifecycleManager.setStateListener(listener);
  }

  /// Sets the uplink video statistics listener.
  ///
  /// See [XmaxRealtimeManaging.setUplinkVideoStatisticsListener] for the usage contract.
  @override
  Future<void> setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  ) async => _streamController.setUplinkVideoStatisticsListener(listener);

  /// Sets the downlink video statistics listener for the current result stream.
  ///
  /// See [XmaxRealtimeManaging.setDownlinkVideoStatisticsListener] for the usage contract.
  @override
  Future<void> setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  ) async => _streamController.setDownlinkVideoStatisticsListener(listener);

  /// Sets the network quality listener independently of automatic adaptation.
  ///
  /// See [XmaxRealtimeManaging.setNetworkQualityListener] for the usage contract.
  @override
  Future<void> setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  ) async {
    _streamController.setNetworkQualityListener(listener);
  }

  /// Sets the device performance alarm listener.
  ///
  /// See [XmaxRealtimeManaging.setPerformanceAlarmListener] for the usage contract.
  @override
  Future<void> setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  ) async {
    _streamController.setPerformanceAlarmListener(listener);
  }

  /// Sets the local media preview volume.
  ///
  /// See [XmaxRealtimeManaging.setLocalAudioVolume] for the usage contract.
  @override
  Future<void> setLocalAudioVolume(
    double volume,
  ) async {
    try {
      _validateAudioVolume(volume);
      await _mediaController.setLocalAudioVolume(volume);
    } catch (error) {
      throw _errorManager.report(error);
    }
  }

  /// Sets remote audio playback volume in increments of 0.01.
  ///
  /// See [XmaxRealtimeManaging.setRemoteAudioVolume] for the usage contract.
  @override
  Future<void> setRemoteAudioVolume(
    double volume,
  ) async {
    try {
      _validateAudioVolume(volume);
      await _streamController.setRemoteAudioVolume(volume);
    } catch (error) {
      throw _errorManager.report(error);
    }
  }

  /// Creates a local camera stream and starts its preview.
  ///
  /// See [XmaxRealtimeManaging.createLocalCameraStream] for the usage contract.
  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    RealtimeVideoFormat? videoFormat,
    CameraPosition position = CameraPosition.front,
    RealtimeCameraPreset? preset,
  }) async {
    if (_connectionManager.currentSessionID.isNotEmpty ||
        _state.connectionState == RealtimeConnectionState.preparing ||
        _state.connectionState == RealtimeConnectionState.connecting ||
        _state.connectionState == RealtimeConnectionState.disconnecting) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'Local camera stream is unavailable during a realtime connection',
        ),
      );
    }

    if (_mediaController.currentTrack != null) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'Stop the current local media stream before creating another one',
        ),
      );
    }

    late final RealtimeVideoFormat format;

    try {
      format = _resolveCameraVideoFormat(
        videoFormat: videoFormat,
        preset: preset,
      );
    } catch (error) {
      throw _report(error);
    }

    _errorManager.invalidatePendingFailures();

    final version = _lifecycleManager.beginOperation();

    _lifecycleManager.emit(
      const RealtimeState(connectionState: RealtimeConnectionState.preparing),
    );

    final creation = _mediaController.createLocalCameraStream(
      videoFormat: format,
      position: position,
    );

    _lifecycleManager.trackCameraCreation(creation);

    try {
      final stream = await creation;

      _lifecycleManager.ensureCurrent(version);
      // Apply defaults only after the media stream is created successfully.
      // A stale creation request must not overwrite settings for a newer media stream.
      await _streamController.setRemoteAudioVolume(0);
      _lifecycleManager.ensureCurrent(version);

      return stream;
    } catch (error) {
      if (version != _lifecycleManager.operationVersion) {
        throw XmaxError.from(error);
      }

      final xmaxError = _report(error);

      _lifecycleManager.emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.idle,
          reason: RealtimeReason.failure(xmaxError),
        ),
      );
      throw xmaxError;
    } finally {
      _lifecycleManager.finishCameraCreation(creation);
    }
  }

  /// Resolves a camera creation format without allocating capture resources.
  ///
  /// Defaults to the model's camera format. Throws for conflicting inputs or unsupported presets.
  ///
  /// Parameters:
  /// - [videoFormat]: The complete capture format; cannot be combined with [preset].
  /// - [preset]: The resolution preset to resolve against the model's supported formats.
  RealtimeVideoFormat _resolveCameraVideoFormat({
    RealtimeVideoFormat? videoFormat,
    RealtimeCameraPreset? preset,
  }) {
    if (videoFormat != null && preset != null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Provide either a camera video format or a preset, not both',
      );
    }

    if (videoFormat != null) {
      return videoFormat;
    }
    if (preset == null) {
      return options.model.defaultCameraVideoFormat;
    }

    for (final format in options.model.supportedVideoFormats) {
      if (format.width == preset.size.width &&
          format.height == preset.size.height) {
        return format;
      }
    }

    throw const XmaxError(
      code: XmaxErrorCode.invalidConfiguration,
      message: 'Model does not support the requested camera preset',
    );
  }

  /// Stops the camera and releases capture resources. Disconnect realtime before calling.
  ///
  /// See [XmaxRealtimeManaging.stopLocalCameraStream] for the usage contract.
  @override
  Future<void> stopLocalCameraStream() async {
    if (_isUpdatingCameraFormat ||
        _connectionManager.currentSessionID.isNotEmpty ||
        _state.connectionState == RealtimeConnectionState.connecting ||
        _state.connectionState == RealtimeConnectionState.disconnecting) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'Disconnect realtime before stopping the local camera stream',
        ),
      );
    }

    try {
      _errorManager.invalidatePendingFailures();
      await _mediaController.stopLocalCameraStream();
      _lifecycleManager.emit(
        const RealtimeState(connectionState: RealtimeConnectionState.idle),
      );
    } catch (error) {
      throw _report(error);
    }
  }

  /// Switches between the front and rear cameras.
  ///
  /// See [XmaxRealtimeManaging.switchCamera] for the usage contract.
  @override
  Future<RealtimeMediaStream> switchCamera() async {
    if (_isUpdatingCameraFormat ||
        _state.connectionState == RealtimeConnectionState.connecting ||
        _state.connectionState == RealtimeConnectionState.disconnecting) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'Camera switching is unavailable while realtime is transitioning',
        ),
      );
    }

    final wasGenerating =
        _state.connectionState == RealtimeConnectionState.generating;

    if (!wasGenerating && _streamController.hasGenerationTask) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'Camera switching is unavailable while realtime generation is starting',
        ),
      );
    }

    if (wasGenerating) {
      await stopGeneration();
    }

    late final RealtimeMediaStream stream;

    try {
      stream = await _mediaController.switchCamera();
    } catch (error) {
      throw _report(error);
    }

    // Wait for the new camera to publish frames before resuming generation.
    // Let startGeneration handle generation failures to avoid duplicate camera error notifications.
    if (wasGenerating) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await startGeneration(
        faceRestoration: _generationManager.cachedFaceRestoration,
      );
    }

    return stream;
  }

  /// Creates a server session, joins RTC, and publishes local video.
  ///
  /// See [XmaxRealtimeManaging.connect] for the usage contract.
  @override
  Future<RealtimeMediaStream> connect({
    required RealtimeMediaStream localStream,
  }) => _connect(localStream: localStream);

  /// Creates a session and joins RTC while checking operation validity.
  ///
  /// Parameters:
  /// - [localStream]: The local stream created by this manager.
  /// - [timing]: The startup duration recorder, or null to omit timing.
  ///
  /// Returns the remote media stream for this connection.
  Future<RealtimeMediaStream> _connect({
    required RealtimeMediaStream localStream,
    RealtimeTiming? timing,
  }) async {
    if (_isUpdatingCameraFormat ||
        _connectionManager.currentSessionID.isNotEmpty ||
        _state.connectionState == RealtimeConnectionState.connecting ||
        _state.connectionState == RealtimeConnectionState.disconnecting) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Realtime connection is already open',
        ),
      );
    }

    final videoFormat = localStream.videoTrack?.videoFormat;

    if (videoFormat == null || !_mediaController.owns(localStream)) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'The local stream must be created and started by this realtime manager',
        ),
      );
    }

    // Advance the version to invalidate callbacks from older connection requests.
    _errorManager.invalidatePendingFailures(
      scope: RealtimeFailureScope.connection,
    );

    final isConnectionCurrent = _errorManager.captureValidity(
      RealtimeFailureScope.connection,
    );

    await _generationManager.reset();

    final version = _lifecycleManager.beginOperation();

    _lifecycleManager.emit(
      const RealtimeState(connectionState: RealtimeConnectionState.connecting),
    );

    try {
      timing?.beginConnection();
      await _streamController.prepareQuality(
        baseline: videoFormat,
        model: options.model.value,
      );

      final remoteStream = await _connectionManager.connect(
        timing: timing,
        model: options.model,
        videoFormat: videoFormat,
        isCurrent: () => version == _lifecycleManager.operationVersion,
        onHeartbeatFailure: (
          sessionID,
          error,
        ) async {
          if (isConnectionCurrent()) {
            await _handleHeartbeatFailure(
              sessionID,
              error,
            );
          }
        },
      );

      _lifecycleManager.ensureCurrent(version);

      final sessionID = _connectionManager.currentSessionID;

      if (sessionID.isEmpty) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      _lifecycleManager.emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.connected,
          sessionID: sessionID,
        ),
      );

      timing?.finishConnection();

      return remoteStream;
    } catch (error) {
      // After invalidation, the pending disconnect or close operation owns state updates.
      if (version != _lifecycleManager.operationVersion) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      final xmaxError = _report(error);

      _lifecycleManager.emit(
        RealtimeState(
          connectionState: _mediaController.currentTrack == null
              ? RealtimeConnectionState.idle
              : RealtimeConnectionState.ready,
          reason: RealtimeReason.failure(xmaxError),
        ),
      );
      throw xmaxError;
    }
  }

  /// Disconnects realtime while preserving the local camera preview.
  ///
  /// See [XmaxRealtimeManaging.disconnect] for the usage contract.
  @override
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  }) => _lifecycleManager.disconnect(reason: reason);

  /// Closes realtime and releases connection and local capture resources.
  ///
  /// See [XmaxRealtimeManaging.close] for the usage contract.
  @override
  Future<void> close() => _lifecycleManager.close();

  /// Starts generation, or updates active conditions without repeating first-frame readiness.
  ///
  /// See [XmaxRealtimeManaging.startGeneration] for the usage contract.
  @override
  Future<RealtimeMediaStream?> startGeneration({
    RealtimeMediaStream? localStream,
    RealtimeContext? context,
    bool faceRestoration = false,
  }) async {
    final timing =
        _state.connectionState != RealtimeConnectionState.generating &&
            _lifecycleManager.startingGenerationTaskID == null
        ? RealtimeTiming()
        : null;
    // A newer request supersedes one that is still connecting or awaiting a result stream.
    final requestVersion = _lifecycleManager.beginGenerationRequest();

    try {
      final prepared = await _lifecycleManager.enqueueGenerationOperation(
        () => _prepareGeneration(
          localStream: localStream,
          context: context,
          faceRestoration: faceRestoration,
          requestVersion: requestVersion,
          timing: timing,
        ),
      );

      // Keep first-frame waiting outside the operation queue so conditions can change during decoder startup.
      await prepared.readiness;

      return prepared.remoteStream;
    } catch (error) {
      timing?.finishFailure(error);
      rethrow;
    }
  }

  /// Prepares connection and generation without holding the operation queue during first-frame
  /// waiting.
  ///
  /// Parameters:
  /// - [localStream]: The local stream created by this manager.
  /// - [context]: The requested conditions; null reuses cached conditions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false.
  /// - [requestVersion]: The revision of this generation request.
  /// - [timing]: The startup duration recorder, or null to omit timing.
  ///
  /// Returns the remote stream and its independent readiness operation.
  Future<_PreparedGeneration> _prepareGeneration({
    required RealtimeMediaStream? localStream,
    required RealtimeContext? context,
    required bool faceRestoration,
    required int requestVersion,
    RealtimeTiming? timing,
  }) async {
    // New generation requests wait for pending disconnect cleanup to finish.
    await _lifecycleManager.disconnection;
    _lifecycleManager.ensureGenerationRequestCurrent(requestVersion);

    if (localStream != null && !_mediaController.owns(localStream)) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message:
              'The local stream must be created and started by this realtime manager',
        ),
      );
    }

    RealtimeMediaStream? remoteStream;

    if (localStream != null) {
      if (_state.connectionState == RealtimeConnectionState.connected ||
          _state.connectionState == RealtimeConnectionState.generating) {
        remoteStream = _connectionManager.currentRemoteStream;
      } else {
        remoteStream = await _connect(
          localStream: localStream,
          timing: timing,
        );
        _lifecycleManager.ensureGenerationRequestCurrent(requestVersion);
      }
    }

    final task = await _prepareGenerationTask(
      context,
      faceRestoration: faceRestoration,
      requestVersion: requestVersion,
      timing: timing,
    );

    return _PreparedGeneration(
      remoteStream: remoteStream,
      readiness: task.readiness,
    );
  }

  /// Starts generation or updates conditions according to connection state.
  ///
  /// Parameters:
  /// - [context]: The requested conditions; null lets the generation manager reuse cached
  ///   conditions.
  /// - [requestVersion]: The generation request revision.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  /// - [timing]: The startup duration recorder, or null to omit timing.
  ///
  /// Returns the independent readiness operation for this generation.
  Future<_PreparedGenerationTask> _prepareGenerationTask(
    RealtimeContext? context, {
    required int requestVersion,
    required bool faceRestoration,
    RealtimeTiming? timing,
  }) async {
    final sessionID = _connectionManager.currentSessionID;
    final videoFormat = _mediaController.currentVideoFormat;

    if (sessionID.isEmpty ||
        videoFormat == null ||
        (_state.connectionState != RealtimeConnectionState.connected &&
            _state.connectionState != RealtimeConnectionState.generating)) {
      throw _report(
        const XmaxError(
          code: XmaxErrorCode.rtcError,
          message: 'Realtime connection is not open',
        ),
      );
    }

    final activeTaskID =
        _state.taskID ?? _lifecycleManager.startingGenerationTaskID;

    if (activeTaskID != null) {
      try {
        await _generationManager.update(
          taskID: activeTaskID,
          videoFormat: videoFormat,
          context: context,
          faceRestoration: faceRestoration,
        );

        return _PreparedGenerationTask(
          readiness:
              _lifecycleManager.generationReadiness ?? Future<void>.value(),
        );
      } catch (error) {
        if (requestVersion != _lifecycleManager.generationRequestVersion) {
          throw XmaxError.from(error);
        }

        throw _report(error);
      }
    }

    // Reject invalid arguments without disconnecting; runtime failures after remote startup require cleanup.
    try {
      _generationManager.validateContext(context);
    } catch (error) {
      throw _report(error);
    }

    final version = _lifecycleManager.operationVersion;

    try {
      final taskID = await _generationManager.start(
        timing: timing,
        videoFormat: videoFormat,
        context: context,
        faceRestoration: faceRestoration,
        ensureCurrent: () => _lifecycleManager.ensureCurrent(version),
      );

      final completer = _lifecycleManager.beginGenerationWait(taskID);
      unawaited(
        _completeGenerationStart(
          sessionID: sessionID,
          taskID: taskID,
          operationVersion: version,
          completer: completer,
          timing: timing,
        ),
      );

      return _PreparedGenerationTask(readiness: completer.future);
    } catch (error) {
      // Superseding a request is normal cancellation, not a runtime error.
      if (requestVersion != _lifecycleManager.generationRequestVersion ||
          version != _lifecycleManager.operationVersion) {
        throw XmaxError.from(error);
      }

      final xmaxError = _report(error);

      timing?.finishFailure(xmaxError);
      await disconnect(reason: RealtimeReason.failure(xmaxError));
      throw xmaxError;
    }
  }

  /// Waits for stream confirmation, first-frame decoding, and audio activation before committing
  /// generating.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  /// - [taskID]: The current generation task identifier.
  /// - [operationVersion]: The revision of this connection or local media operation.
  /// - [completer]: The completer receiving startup readiness or failure.
  /// - [timing]: The startup duration recorder, or null to omit timing.
  Future<void> _completeGenerationStart({
    required String sessionID,
    required String taskID,
    required int operationVersion,
    required Completer<void> completer,
    RealtimeTiming? timing,
  }) async {
    try {
      await _connectionManager.waitUntilRemoteFrameReady();
      _lifecycleManager.ensureCurrent(operationVersion);
      await _streamController.activateRemoteAudio();
      _lifecycleManager.ensureCurrent(operationVersion);
      if (_connectionManager.currentSessionID != sessionID) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      _lifecycleManager.emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.generating,
          sessionID: sessionID,
          taskID: taskID,
        ),
      );

      if (!completer.isCompleted) {
        timing?.finish();
        completer.complete();
      }
    } catch (error) {
      if (!completer.isCompleted &&
          operationVersion == _lifecycleManager.operationVersion) {
        final xmaxError = _report(error);

        timing?.finishFailure(xmaxError);
        // Remove the failed wait before disconnecting so cancellation cannot replace its original error.
        // Complete the caller's future only after session cleanup finishes.
        _lifecycleManager.detachGenerationWait(completer);

        await disconnect(reason: RealtimeReason.failure(xmaxError));
        completer.completeError(xmaxError);
      }
    } finally {
      _lifecycleManager.finishGenerationWait(completer);
    }
  }

  /// Stops generation and interactions while retaining the RTC connection.
  Future<void> stopGeneration() => _lifecycleManager.stopGeneration();

  /// Cleans up and reports a failed connection only while its session remains current.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  /// - [error]: The operation error.
  Future<void> _handleHeartbeatFailure(
    String sessionID,
    Object error,
  ) async {
    if (_connectionManager.currentSessionID != sessionID) {
      return;
    }

    final xmaxError = _report(error);

    await disconnect(reason: RealtimeReason.failure(xmaxError));
  }

  /// Normalizes and logs the current operation error.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns the normalized SDK error.
  XmaxError _report(
    Object error,
  ) => _errorManager.report(error);

  /// Validates a finite volume from 0 to 1, throwing for invalid values.
  ///
  /// Parameters:
  /// - [volume]: A finite volume from 0 to 1; out-of-range values, NaN, and infinity are invalid.
  static void _validateAudioVolume(
    double volume,
  ) {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Audio volume must be between 0 and 1',
      );
    }
  }
}

/// A prepared remote stream and its generation readiness operation.
final class _PreparedGeneration {

  /// Creates a prepared generation result.
  const _PreparedGeneration({
    required this.remoteStream,
    required this.readiness,
  });

  /// The remote media stream for this generation result.
  final RealtimeMediaStream? remoteStream;

  /// The readiness future, which completes with an error on failure or cancellation.
  final Future<void> readiness;
}

/// A generation startup readiness operation.
final class _PreparedGenerationTask {

  /// Creates a generation startup readiness result.
  const _PreparedGenerationTask({
    required this.readiness,
  });

  /// The readiness future, which completes with an error on failure or cancellation.
  final Future<void> readiness;
}
