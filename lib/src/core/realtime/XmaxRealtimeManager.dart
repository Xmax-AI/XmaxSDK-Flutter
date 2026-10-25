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
import 'dart:ui';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/media/camera/CameraPosition.dart';
import '../../foundation/rtc/VideoStatistics.dart';
import '../../render/RenderControlling.dart';
import '../../media/MediaControlling.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../service/media/MediaService.dart';
import '../../service/media/MediaServicing.dart';
import '../../service/network/ApiServicing.dart';
import '../../service/realtime/RealtimeCameraPreset.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeMediaFrame.dart';
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
import '../../media/external/RealtimeExternalVideoSource.dart';

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
      mediaService: MediaService(model: options.model),
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
       _lifecycleManager = components.lifecycleManager,
       _mediaService = components.mediaService,
       _renderController = components.renderController,
       _timing = components.timing;

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

  /// The shared rules resolving generation canvases independently of capture dimensions.
  final MediaServicing _mediaService;

  /// The controller for remote presentation, readiness, and owned media output.
  final RenderControlling _renderController;

  /// The current realtime lifecycle state.
  RealtimeState get _state => _lifecycleManager.currentState;

  /// The shared recorder for admitted startup attempts.
  final RealtimeTiming _timing;

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

  /// Applies a manual quality change inside the shared configuration operation.
  ///
  /// Parameters:
  /// - [level]: The requested transport quality level.
  /// - [downlink]: Whether to change returned dimensions rather than uplink encoding.
  Future<void> _setQualityLevel(
    RealtimeQualityLevel level, {
    required bool downlink,
  }) => _lifecycleManager.run(
    kind: RealtimeOperationKind.configuration,
    operation: (
      token,
    ) async {
      final taskID = _state.taskID;
      if (_state.connectionState != RealtimeConnectionState.generating || taskID == null) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Quality levels can only be changed while generating',
        );
      }
      await _connectionManager.applyQualityLevel(
        level,
        downlink: downlink,
        taskID: taskID,
        ensureCurrent: token.ensureCurrent,
      );
    },
  );

  /// Updates ready, disconnected capture while retaining the track and view.
  ///
  /// See [XmaxRealtimeManaging.updateCameraFormat] for the usage contract.
  @override
  Future<void> updateCameraFormat({
    RealtimeVideoFormat? videoFormat,
    RealtimeCameraPreset? preset,
  }) => _lifecycleManager.run(
    kind: RealtimeOperationKind.media,
    operation: (
      token,
    ) async {
      final current = _mediaController.currentVideoFormat;
      if ((videoFormat == null) == (preset == null) || current == null ||
          _mediaController.currentTrack?.position == null ||
          _state.connectionState != RealtimeConnectionState.ready ||
          _connectionManager.currentSessionID.isNotEmpty) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Provide exactly one camera format or preset while preview is ready and disconnected',
        );
      }
      final format = videoFormat ?? current.resized(
        width: preset!.size.width.toInt(),
        height: preset.size.height.toInt(),
      );
      await _mediaController.updateCameraFormat(format);
      token.ensureCurrent();
    },
  );

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

  /// Sets bounded remote audio and video output independently of playback.
  ///
  /// See [XmaxRealtimeManaging.setRemoteMediaFrameListener] for the delivery contract.
  @override
  Future<void> setRemoteMediaFrameListener(
    RealtimeMediaFrameListener? listener,
  ) => _renderController.setRemoteMediaFrameListener(listener);

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

  /// Creates a camera stream inside exclusive media admission.
  ///
  /// See [XmaxRealtimeManaging.createLocalCameraStream] for the usage contract.
  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    RealtimeVideoFormat? videoFormat,
    CameraPosition position = CameraPosition.front,
    RealtimeCameraPreset? preset,
    bool useMicrophone = false,
  }) => _lifecycleManager.run(
    kind: RealtimeOperationKind.media,
    operation: (
      token,
    ) async {
      if (_connectionManager.currentSessionID.isNotEmpty ||
          _state.connectionState == RealtimeConnectionState.preparing ||
          _state.connectionState == RealtimeConnectionState.connecting ||
          _state.connectionState == RealtimeConnectionState.disconnecting) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Local camera stream is unavailable during a realtime connection',
        );
      }
      if (_mediaController.currentTrack != null) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Stop the current local media stream before creating another one',
        );
      }
      final format = _resolveCameraVideoFormat(
        videoFormat: videoFormat,
        preset: preset,
      );
      _errorManager.invalidatePendingFailures();
      _lifecycleManager.commit(
        const RealtimeState(connectionState: RealtimeConnectionState.preparing),
        token: token,
      );
      token.ensureCurrent();

      final stream = await _mediaController.createLocalCameraStream(
        videoFormat: format,
        position: position,
        useMicrophone: useMicrophone,
        cancellation: token.cancellation,
      );
      token.ensureCurrent();
      await _streamController.setRemoteAudioVolume(0);
      token.ensureCurrent();
      return stream;
    },
  );

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

  /// Stops disconnected capture inside exclusive media admission.
  ///
  /// See [XmaxRealtimeManaging.stopLocalCameraStream] for the usage contract.
  @override
  Future<void> stopLocalCameraStream() => _lifecycleManager.run(
    kind: RealtimeOperationKind.media,
    operation: (
      token,
    ) async {
      if (_connectionManager.currentSessionID.isNotEmpty ||
          _state.connectionState == RealtimeConnectionState.connecting ||
          _state.connectionState == RealtimeConnectionState.disconnecting) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Disconnect realtime before stopping the local camera stream',
        );
      }
      _errorManager.invalidatePendingFailures();
      await _mediaController.stopLocalCameraStream();
      token.ensureCurrent();
      _lifecycleManager.complete(
        RealtimeState(
          connectionState: _mediaController.currentTrack == null
              ? RealtimeConnectionState.idle
              : RealtimeConnectionState.ready,
        ),
        token: token,
      );
    },
  );

  /// Binds an app-owned source inside exclusive local media admission.
  ///
  /// See [XmaxRealtimeManaging.createExternalVideoStream] for the usage contract.
  @override
  Future<RealtimeMediaStream> createExternalVideoStream({
    required RealtimeExternalVideoSource source,
  }) => _lifecycleManager.run(
    kind: RealtimeOperationKind.media,
    operation: (
      token,
    ) async {
      if (_connectionManager.currentSessionID.isNotEmpty ||
          _mediaController.currentTrack != null ||
          _state.connectionState == RealtimeConnectionState.connecting ||
          _state.connectionState == RealtimeConnectionState.disconnecting) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Stop local media and disconnect before binding an external source',
        );
      }
      source.videoFormat.validate();
      _errorManager.invalidatePendingFailures();
      _lifecycleManager.commit(
        const RealtimeState(connectionState: RealtimeConnectionState.preparing),
        token: token,
      );
      token.ensureCurrent();
      final stream = await _mediaController.createExternalVideoStream(
        source: source,
        cancellation: token.cancellation,
      );
      token.ensureCurrent();
      token.setFailureScope(RealtimeTerminationScope.all);
      await _streamController.setRemoteAudioVolume(0);
      token.ensureCurrent();
      _lifecycleManager.complete(
        const RealtimeState(connectionState: RealtimeConnectionState.ready),
        token: token,
      );
      return stream;
    },
  );

  /// Detaches an external source only after connection resources have been released.
  ///
  /// See [XmaxRealtimeManaging.stopExternalVideoStream] for the usage contract.
  @override
  Future<void> stopExternalVideoStream() => _lifecycleManager.run(
    kind: RealtimeOperationKind.media,
    operation: (
      token,
    ) async {
      if (_connectionManager.currentSessionID.isNotEmpty ||
          _state.connectionState == RealtimeConnectionState.connecting ||
          _state.connectionState == RealtimeConnectionState.disconnecting) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Disconnect realtime before stopping the external source',
        );
      }
      _errorManager.invalidatePendingFailures();
      await _mediaController.stopExternalVideoStream();
      token.ensureCurrent();
      _lifecycleManager.complete(
        RealtimeState(
          connectionState: _mediaController.currentTrack == null
              ? RealtimeConnectionState.idle
              : RealtimeConnectionState.ready,
        ),
        token: token,
      );
    },
  );

  /// Switches capture and restores generation using the same admitted operation.
  ///
  /// See [XmaxRealtimeManaging.switchCamera] for the usage contract.
  @override
  Future<RealtimeMediaStream> switchCamera() => _lifecycleManager.run(
    kind: RealtimeOperationKind.cameraSwitch,
    operation: (
      token,
    ) async {
      if (_mediaController.currentTrack?.position == null) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Camera switching requires an active camera source',
        );
      }
      if (_state.connectionState == RealtimeConnectionState.connecting ||
          _state.connectionState == RealtimeConnectionState.disconnecting ||
          (_state.connectionState != RealtimeConnectionState.generating &&
              _streamController.hasGenerationTask)) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Camera switching is unavailable while realtime is transitioning',
        );
      }
      final wasGenerating = _state.connectionState == RealtimeConnectionState.generating;
      if (wasGenerating) {
        token.setFailureScope(RealtimeTerminationScope.connection);
        _streamController.setAdaptiveQualityListener(null);
        await _generationManager.stop(taskID: _state.taskID ?? '');
        token.ensureCurrent();
        _lifecycleManager.commit(
          RealtimeState(
            connectionState: RealtimeConnectionState.connected,
            sessionID: _state.sessionID,
          ),
          token: token,
        );
      }

      final stream = await _mediaController.switchCamera();
      token.ensureCurrent();
      if (wasGenerating) {
        await token.wait(Future<void>.delayed(const Duration(milliseconds: 500)));
        await _performStartGeneration(
          context: null,
          faceRestoration: _generationManager.cachedFaceRestoration,
          token: token,
        );
      }
      return stream;
    },
  );

  /// Establishes a connection inside exclusive lifecycle admission.
  ///
  /// See [XmaxRealtimeManaging.connect] for the usage contract.
  @override
  Future<RealtimeMediaStream> connect({
    required RealtimeMediaStream localStream,
  }) => _lifecycleManager.run(
    kind: RealtimeOperationKind.connection,
    operation: (
      token,
    ) async {
      _timing.reset();
      return _performConnect(
        localStream: localStream,
        token: token,
        completesOperation: true,
      );
    },
  );

  /// Validates local ownership and establishes the session and transport.
  ///
  /// Parameters:
  /// - [localStream]: The manager-owned local stream.
  /// - [token]: The admitted connection or generation operation.
  /// - [completesOperation]: Whether connected is the operation's final state.
  ///
  /// Returns the connection's remote stream.
  Future<RealtimeMediaStream> _performConnect({
    required RealtimeMediaStream localStream,
    required RealtimeOperationToken token,
    bool completesOperation = false,
  }) async {
    if (_connectionManager.currentSessionID.isNotEmpty ||
        _state.connectionState == RealtimeConnectionState.connecting ||
        _state.connectionState == RealtimeConnectionState.disconnecting) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Realtime connection is already open',
      );
    }
    final videoFormat = localStream.videoTrack?.videoFormat;
    if (videoFormat == null || !_mediaController.owns(localStream)) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'The local stream must be created and started by this realtime manager',
      );
    }
    token.setFailureScope(RealtimeTerminationScope.connection);
    _errorManager.invalidatePendingFailures(scope: RealtimeFailureScope.connection);
    final isConnectionCurrent = _errorManager.captureValidity(RealtimeFailureScope.connection);
    await _generationManager.reset();
    token.ensureCurrent();
    _lifecycleManager.commit(
      const RealtimeState(connectionState: RealtimeConnectionState.connecting),
      token: token,
    );
    token.ensureCurrent();
    await _connectionManager.prepareQuality(
      baseline: videoFormat,
      options: options,
      ensureCurrent: token.ensureCurrent,
    );
    token.ensureCurrent();

    await _mediaController.startMicrophoneCapture();
    token.ensureCurrent();

    final remote = await _connectionManager.connect(
      model: options.model,
      videoFormat: videoFormat,
      cancellation: token.cancellation,
      isCurrent: () => token.isCurrent,
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
    token.ensureCurrent();
    final sessionID = _connectionManager.currentSessionID;
    if (sessionID.isEmpty) {
      throw XmaxRealtimeLifecycleManager.cancelledError();
    }
    final connected = RealtimeState(
      connectionState: RealtimeConnectionState.connected,
      sessionID: sessionID,
    );
    if (completesOperation) {
      _lifecycleManager.complete(
        connected,
        token: token,
      );
    } else {
      _lifecycleManager.commit(
        connected,
        token: token,
      );
    }
    return remote;
  }

  /// Disconnects while preserving the local camera preview.
  ///
  /// See [XmaxRealtimeManaging.disconnect] for the usage contract.
  @override
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  }) => _lifecycleManager.disconnect(reason: reason);

  /// Releases all resources after affected operations settle.
  ///
  /// See [XmaxRealtimeManaging.close] for the usage contract.
  @override
  Future<void> close() => _lifecycleManager.terminate(RealtimeTerminationScope.all);

  /// Starts generation or replaces an unfinished request through shared admission.
  ///
  /// See [XmaxRealtimeManaging.startGeneration] for the usage contract.
  @override
  Future<RealtimeMediaStream?> startGeneration({
    RealtimeMediaStream? localStream,
    RealtimeContext? context,
    bool faceRestoration = false,
  }) => _lifecycleManager.run(
    kind: RealtimeOperationKind.generation,
    operation: (
      token,
    ) async {
      if (_state.connectionState != RealtimeConnectionState.generating) {
        _timing.reset();
      }
      try {
        if (localStream != null && !_mediaController.owns(localStream)) {
          throw const XmaxError(
            code: XmaxErrorCode.invalidConfiguration,
            message: 'The local stream must be created and started by this realtime manager',
          );
        }
        RealtimeMediaStream? remote;
        if (localStream != null) {
          remote = _state.connectionState == RealtimeConnectionState.connected ||
              _state.connectionState == RealtimeConnectionState.generating
              ? _connectionManager.currentRemoteStream
              : await _performConnect(
                localStream: localStream,
                token: token,
              );
          token.ensureCurrent();
        }
        await _performStartGeneration(
          context: context,
          faceRestoration: faceRestoration,
          token: token,
        );
        return remote;
      } catch (error) {
        _timing.finishFailure(error);
        rethrow;
      }
    },
  );

  /// Starts a task or updates established generation without waiting for new video.
  ///
  /// Parameters:
  /// - [context]: The requested conditions, or null to reuse the successful context.
  /// - [faceRestoration]: Whether to restore the original face.
  /// - [token]: The admitted operation, retained through first-frame readiness.
  Future<void> _performStartGeneration({
    required RealtimeContext? context,
    required bool faceRestoration,
    required RealtimeOperationToken token,
  }) async {
    token.ensureCurrent();
    final sessionID = _connectionManager.currentSessionID;
    final videoFormat = _mediaController.currentVideoFormat;
    if (sessionID.isEmpty || videoFormat == null ||
        (_state.connectionState != RealtimeConnectionState.connected &&
            _state.connectionState != RealtimeConnectionState.generating)) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Realtime connection is not open',
      );
    }
    final canvas = _mediaService.resolveGenerationSize(
      Size(
        videoFormat.width.toDouble(),
        videoFormat.height.toDouble(),
      ),
    );
    final generationFormat = videoFormat.resized(
      width: canvas.width.toInt(),
      height: canvas.height.toInt(),
    );
    final paddingContain = videoFormat.width * generationFormat.height !=
        videoFormat.height * generationFormat.width;
    token.ensureCurrent();

    final activeTaskID = _state.taskID;
    if (_state.connectionState == RealtimeConnectionState.generating && activeTaskID != null) {
      await _generationManager.update(
        taskID: activeTaskID,
        videoFormat: videoFormat,
        context: context,
        faceRestoration: faceRestoration,
        generationVideoFormat: generationFormat,
        paddingContain: paddingContain,
        ensureCurrent: token.ensureCurrent,
      );
      return;
    }

    _generationManager.validateContext(context);
    token.setFailureScope(RealtimeTerminationScope.connection);
    final taskID = await _generationManager.start(
      videoFormat: videoFormat,
      targetSize: _connectionManager.currentTargetSize,
      context: context,
      faceRestoration: faceRestoration,
      generationVideoFormat: generationFormat,
      paddingContain: paddingContain,
      token: token,
    );
    token.ensureCurrent();
    if (_connectionManager.currentSessionID != sessionID) {
      throw XmaxRealtimeLifecycleManager.cancelledError();
    }
    await _connectionManager.completeInitialQuality(token.ensureCurrent);
    token.ensureCurrent();
    if (options.isAdaptiveQualityEnabled) {
      _streamController.setAdaptiveQualityListener((
        quality,
        sampledAt,
      ) => unawaited(
        _adaptQuality(
          quality,
          sampledAt: sampledAt,
          taskID: taskID,
        ),
      ));
    }
    _lifecycleManager.complete(
      RealtimeState(
        connectionState: RealtimeConnectionState.generating,
        sessionID: sessionID,
        taskID: taskID,
      ),
      token: token,
    );
    _timing.finish();
  }

  /// Applies independent automatic adjustments only while shared admission is idle.
  ///
  /// Parameters:
  /// - [quality]: The current network measurements.
  /// - [sampledAt]: The monotonic sample time, in seconds.
  /// - [taskID]: The task whose listener delivered this sample.
  Future<void> _adaptQuality(
    RealtimeNetworkQuality quality, {
    required double sampledAt,
    required String taskID,
  }) async {
    try {
      final accepted = await _lifecycleManager.runAdaptiveConfiguration((
        token,
      ) async {
        if (_state.taskID != taskID) {
          return;
        }
        final change = _streamController.proposeQuality(
          quality,
          sampledAt,
        );
        for (final downlink in [false, true]) {
          token.ensureCurrent();
          final level = downlink ? change.downlink : change.uplink;
          if (level == null) {
            continue;
          }
          try {
            await _connectionManager.applyQualityLevel(
              level,
              downlink: downlink,
              taskID: taskID,
              ensureCurrent: token.ensureCurrent,
            );
          } catch (error) {
            token.ensureCurrent();
            XmaxLogger.warn(
              category: XmaxLoggerCategory.realtime,
              message: '网络档位调整失败 (Quality Adjustment Failed)\n└─ $error',
            );
          }
        }
      });
      if (!accepted && _state.taskID == taskID) {
        _streamController.resetQualitySamples();
      }
    } catch (_) {
      if (_state.taskID == taskID) {
        _streamController.resetQualitySamples();
      }
    }
  }

  /// Stops only generation through scoped lifecycle cleanup.
  Future<void> stopGeneration() => _connectionManager.currentSessionID.isEmpty
      ? Future<void>.value()
      : _lifecycleManager.terminate(RealtimeTerminationScope.generation);

  /// Terminates only the session that reported a current heartbeat failure.
  ///
  /// Parameters:
  /// - [sessionID]: The failed session identifier.
  /// - [error]: The heartbeat failure.
  Future<void> _handleHeartbeatFailure(
    String sessionID,
    Object error,
  ) async {
    if (_connectionManager.currentSessionID != sessionID) {
      return;
    }
    await _lifecycleManager.handleFailure(
      XmaxError.from(error),
      RealtimeFailureScope.connection,
      () => _connectionManager.currentSessionID == sessionID,
    );
  }

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
