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
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/media/camera/CameraPosition.dart';
import '../../foundation/rtc/RtcManager.dart';
import '../../foundation/rtc/VideoStatistics.dart';
import '../../media/MediaController.dart';
import '../../media/MediaControlling.dart';
import '../../media/camera/CameraController.dart';
import '../../render/RenderController.dart';
import '../../service/media/MediaService.dart';
import '../../service/network/ApiServicing.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeSessionService.dart';
import '../../service/realtime/RealtimeState.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../stream/StreamController.dart';
import '../../stream/StreamControlling.dart';
import 'RealtimeConfiguration.dart';
import 'RealtimeErrorHandler.dart';
import 'RealtimeTiming.dart';
import 'XmaxRealtimeConnectionManager.dart';
import 'XmaxRealtimeGenerationManager.dart';
import 'XmaxRealtimeManaging.dart';

/// 实时生成管理器，协调本地预览、连接、生成和资源生命周期。
final class XmaxRealtimeManager implements XmaxRealtimeManaging {

  /// 创建实时管理器，并组装模型对应的媒体、连接和生成组件。
  ///
  /// - [options]：模型及媒体规格配置。
  /// - [apiService]：云端实时会话使用的网络服务。
  ///
  /// 创建管理器不会立即申请权限、启动采集或建立网络连接。
  factory XmaxRealtimeManager({
    required RealtimeConfiguration options,
    required ApiServicing apiService,
  }) {
    final errorHandler = RealtimeErrorHandler();
    final rtcManager = RtcManager();
    final renderController = RenderController();

    late final StreamController streamController;

    streamController = StreamController(
      rtcManager: rtcManager,
      mediaService: MediaService(model: options.model),
      errorListener: errorHandler.forward,
      localMediaErrorListener: (error) =>
          errorHandler.forward(error, scope: RealtimeFailureScope.all),
      remoteStreamListener: renderController.setRemoteStream,
      remoteFrameRenderedListener: renderController.markRemoteFrameRendered,
      remoteFrameReadyListener: renderController.markRemoteFrameReady,
    );

    final mediaController = MediaController(
      rtcManager: rtcManager,
      cameraController: CameraController(
        rtcManager: rtcManager,
        mediaService: MediaService(model: options.model),
      ),
      interactionListener: (taskID, points) =>
          streamController.sendTracks(taskID: taskID, points: points),
    );

    final connectionManager = XmaxRealtimeConnectionManager(
      sessionService: RealtimeSessionService(apiService: apiService),
      interactionController: mediaController,
      renderController: renderController,
      streamController: streamController,
    );

    final generationManager = XmaxRealtimeGenerationManager(
      interactionController: mediaController,
      streamController: streamController,
    );

    return XmaxRealtimeManager.internal(
      options: options,
      mediaController: mediaController,
      streamController: streamController,
      connectionManager: connectionManager,
      generationManager: generationManager,
      errorHandler: errorHandler,
    );
  }

  /// 使用指定组件创建管理器，并注册预览就绪及运行失败处理。
  ///
  /// - [options]：模型及媒体规格配置。
  /// - [mediaController]：本地采集和触点输入组件。
  /// - [streamController]：RTC 传输与生成信令组件。
  /// - [connectionManager]：云端会话和房间连接组件。
  /// - [generationManager]：生成条件、任务与交互生命周期组件。
  /// - [errorHandler]：运行错误分发组件。
  XmaxRealtimeManager.internal({
    required this.options,
    required MediaControlling mediaController,
    required StreamControlling streamController,
    required XmaxRealtimeConnectionManager connectionManager,
    required XmaxRealtimeGenerationManager generationManager,
    required RealtimeErrorHandler errorHandler,
  }) : _mediaController = mediaController,
       _streamController = streamController,
       _connectionManager = connectionManager,
       _generationManager = generationManager,
       _errorHandler = errorHandler {
    _mediaController.setCameraPreviewReadyListener(
      _cameraPreviewDidBecomeReady,
    );
    _errorHandler.setFailureHandler(_handleStreamFailure);
  }

  /// 当前管理器的实时模型配置。
  @override
  final RealtimeConfiguration options;

  /// 管理本地摄像头流及其资源所有权的组件。
  final MediaControlling _mediaController;

  /// 管理 RTC 连接、发布订阅和生成信令的组件。
  final StreamControlling _streamController;

  /// 协调云端会话与 RTC 连接的组件。
  final XmaxRealtimeConnectionManager _connectionManager;

  /// 管理任务标识、生成条件和交互生命周期的组件。
  final XmaxRealtimeGenerationManager _generationManager;

  /// 统一处理错误，防止旧操作的错误影响新的连接或媒体流。
  final RealtimeErrorHandler _errorHandler;

  /// 当前实时生命周期状态。
  RealtimeState _state = const RealtimeState(
    connectionState: RealtimeConnectionState.idle,
  );

  /// 当前实时状态监听器；为空时不通知。
  RealtimeStateListener? _stateListener;

  /// 连接或本地媒体操作的版本号。
  int _operationVersion = 0;

  /// 生成请求的版本号，用于识别已被新请求替代的操作。
  int _generationRequestVersion = 0;

  /// 生成取消操作的版本号，用于使旧生成请求失效。
  int _generationCancellationVersion = 0;

  /// 串行执行的生成控制任务。
  Future<void> _generationOperation = Future<void>.value();

  /// 正在等待就绪的生成任务标识。
  String? _startingGenerationTaskID;

  /// 用于通知当前生成请求已就绪或失败的完成器。
  Completer<void>? _startingGenerationCompleter;

  /// 正在进行的资源关闭任务。
  Future<void>? _closeFuture;

  /// 正在进行的断开连接任务。
  Future<void>? _disconnectFuture;

  /// 正在进行的摄像头流创建任务。
  Future<RealtimeMediaStream>? _cameraCreationFuture;

  /// 当前实时连接与生成状态。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.currentState]。
  @override
  Future<RealtimeState> get currentState async => _state;

  /// 当前本地媒体预览音量，范围为 0～1。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.localAudioVolume]。
  @override
  Future<double> get localAudioVolume => _mediaController.localAudioVolume;

  /// 当前远端音频播放音量，范围为 0～1，精度为 0.01。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.remoteAudioVolume]。
  @override
  Future<double> get remoteAudioVolume async =>
      _streamController.remoteAudioVolume;

  /// 设置状态回调，并立即通知当前状态。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setStateListener]。
  @override
  Future<void> setStateListener(
    RealtimeStateListener? listener,
  ) async {
    _stateListener = listener;
    listener?.call(_state);
  }

  /// 设置上行视频统计回调。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setUplinkVideoStatisticsListener]。
  @override
  Future<void> setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  ) async => _streamController.setUplinkVideoStatisticsListener(listener);

  /// 设置当前生成结果流的下行视频统计回调。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setDownlinkVideoStatisticsListener]。
  @override
  Future<void> setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  ) async => _streamController.setDownlinkVideoStatisticsListener(listener);

  /// 设置上下行网络质量回调，不影响 SDK 内部的自适应调节。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setNetworkQualityListener]。
  @override
  Future<void> setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  ) async {
    _streamController.setNetworkQualityListener(listener);
  }

  /// 设置性能受限或恢复时的回调。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setPerformanceAlarmListener]。
  @override
  Future<void> setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  ) async {
    _streamController.setPerformanceAlarmListener(listener);
  }

  /// 设置本地预览音量。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setLocalAudioVolume]。
  @override
  Future<void> setLocalAudioVolume(
    double volume,
  ) async {
    try {
      _validateAudioVolume(volume);
      await _mediaController.setLocalAudioVolume(volume);
    } catch (error) {
      throw _errorHandler.report(error);
    }
  }

  /// 设置远端音频播放音量，精度为 0.01。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.setRemoteAudioVolume]。
  @override
  Future<void> setRemoteAudioVolume(
    double volume,
  ) async {
    try {
      _validateAudioVolume(volume);
      await _streamController.setRemoteAudioVolume(volume);
    } catch (error) {
      throw _errorHandler.report(error);
    }
  }

  /// 创建本地摄像头流并开始预览。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.createLocalCameraStream]。
  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    CameraPosition position = CameraPosition.front,
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

    _errorHandler.invalidatePendingFailures();

    final version = ++_operationVersion;

    _emit(
      const RealtimeState(connectionState: RealtimeConnectionState.preparing),
    );

    final creation = _mediaController.createLocalCameraStream(
      videoFormat: videoFormat,
      position: position,
    );

    _cameraCreationFuture = creation;

    try {
      final stream = await creation;

      _ensureCurrent(version);
      // 每次成功创建媒体流后才应用默认设置。
      // 旧创建请求即使晚于关闭操作结束，也不能覆盖新媒体流的设置。
      await _streamController.setRemoteAudioVolume(0);
      _ensureCurrent(version);

      return stream;
    } catch (error) {
      if (version != _operationVersion) throw XmaxError.from(error);

      final xmaxError = _report(error);

      _emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.idle,
          reason: RealtimeReason.failure(xmaxError),
        ),
      );
      throw xmaxError;
    } finally {
      if (identical(_cameraCreationFuture, creation)) {
        _cameraCreationFuture = null;
      }
    }
  }

  /// 停止摄像头并释放采集资源。调用前须先断开实时连接。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.stopLocalCameraStream]。
  @override
  Future<void> stopLocalCameraStream() async {
    if (_connectionManager.currentSessionID.isNotEmpty ||
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
      _errorHandler.invalidatePendingFailures();
      await _mediaController.stopLocalCameraStream();
      _emit(const RealtimeState(connectionState: RealtimeConnectionState.idle));
    } catch (error) {
      throw _report(error);
    }
  }

  /// 切换前后置摄像头。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.switchCamera]。
  @override
  Future<RealtimeMediaStream> switchCamera() async {
    if (_state.connectionState == RealtimeConnectionState.connecting ||
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

    // 等待新摄像头开始发布画面后再恢复生成。
    // 生成失败由 startGeneration 处理，不纳入摄像头错误处理，避免重复通知。
    if (wasGenerating) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await startGeneration(
        faceRestoration: _generationManager.cachedFaceRestoration,
      );
    }

    return stream;
  }

  /// 创建云端会话，连接 RTC 房间并发布本地视频。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.connect]。
  @override
  Future<RealtimeMediaStream> connect({
    required RealtimeMediaStream localStream,
  }) => _connect(localStream: localStream);

  /// 创建云端会话并连接 RTC，过程中持续检查本次操作是否已被取消。
  ///
  /// - [localStream]：当前管理器创建的本地媒体流。
  /// - [timing]：启动耗时记录器；未提供时不记录。
  ///
  /// 返回本次连接对应的远端媒体流。
  Future<RealtimeMediaStream> _connect({
    required RealtimeMediaStream localStream,
    RealtimeTiming? timing,
  }) async {
    if (_connectionManager.currentSessionID.isNotEmpty ||
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

    // 递增版本号，使旧连接请求的回调失效。
    _errorHandler.invalidatePendingFailures(
      scope: RealtimeFailureScope.connection,
    );

    final isConnectionCurrent = _errorHandler.captureValidity(
      RealtimeFailureScope.connection,
    );

    await _generationManager.reset();

    final version = ++_operationVersion;

    _emit(
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
        isCurrent: () => version == _operationVersion,
        onHeartbeatFailure: (sessionID, error) async {
          if (isConnectionCurrent()) {
            await _handleHeartbeatFailure(sessionID, error);
          }
        },
      );

      _ensureCurrent(version);

      final sessionID = _connectionManager.currentSessionID;

      if (sessionID.isEmpty) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      _emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.connected,
          sessionID: sessionID,
        ),
      );

      timing?.finishConnection();

      return remoteStream;
    } catch (error) {
      // 版本号变化后，由后续的断开或关闭操作更新状态。
      if (version != _operationVersion) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      final xmaxError = _report(error);

      _emit(
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

  /// 停止生成并断开远端连接，保留本地摄像头预览。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.disconnect]。
  @override
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  }) {
    final active = _disconnectFuture;

    if (active != null) {
      return active;
    }

    if (_state.connectionState == RealtimeConnectionState.idle ||
        _state.connectionState == RealtimeConnectionState.preparing ||
        _state.connectionState == RealtimeConnectionState.ready) {
      // 生成请求可能仍在排队，尚未开始连接，也需要取消。
      _generationRequestVersion += 1;
      _generationCancellationVersion += 1;
      _generationManager.cancelPendingStart();

      return Future<void>.value();
    }

    final future = _performDisconnect(reason: reason);

    _disconnectFuture = future;

    return future.whenComplete(() => _disconnectFuture = null);
  }

  /// 结束生成并清理远端连接，保留本地摄像头预览。
  ///
  /// - [reason]：本次生命周期结束或状态变化的原因。
  Future<void> _performDisconnect({
    required RealtimeReason reason,
  }) async {
    // 清理资源前，先使尚未结束的连接和生成回调失效。
    _errorHandler.invalidatePendingFailures(
      scope: RealtimeFailureScope.connection,
    );
    _operationVersion += 1;
    _generationRequestVersion += 1;
    _generationCancellationVersion += 1;

    final taskID = _state.taskID ?? _startingGenerationTaskID ?? '';

    _cancelStartingGeneration();

    _emit(
      const RealtimeState(
        connectionState: RealtimeConnectionState.disconnecting,
      ),
    );

    // 逐项清理资源，某一项失败也要继续释放其他资源。
    try {
      await _connectionManager.prepareForRemoteRemoval();
    } catch (error) {
      _report(error);
    }

    try {
      await _generationManager.reset(taskID: taskID);
    } catch (error) {
      _report(error);
    }

    final activeSessionID = _connectionManager.currentSessionID;
    String? sessionID = activeSessionID.isEmpty ? null : activeSessionID;

    try {
      sessionID = await _connectionManager.disconnect() ?? sessionID;
    } catch (error) {
      _report(error);
    }

    _emit(
      RealtimeState(
        connectionState: _mediaController.currentTrack == null
            ? RealtimeConnectionState.idle
            : RealtimeConnectionState.ready,
        sessionID: sessionID,
        reason: reason,
      ),
    );
  }

  /// 停止生成、断开连接并释放本地采集资源。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.close]。
  @override
  Future<void> close() => _closeWithReason(RealtimeReason.normal);

  /// 按指定结束原因关闭实时生命周期，并共享正在进行的关闭任务。
  ///
  /// - [reason]：本次生命周期结束或状态变化的原因。
  Future<void> _closeWithReason(
    RealtimeReason reason,
  ) {
    final active = _closeFuture;

    if (active != null) {
      return active;
    }

    final future = _performClose(reason);

    _closeFuture = future;

    return future.whenComplete(() => _closeFuture = null);
  }

  /// 依次清理生成、远端连接和本地媒体资源。
  ///
  /// - [reason]：本次生命周期结束或状态变化的原因。
  Future<void> _performClose(
    RealtimeReason reason,
  ) async {
    _errorHandler.invalidatePendingFailures();
    _operationVersion += 1;
    await disconnect(reason: reason);

    // 先等待摄像头创建结束，再由 MediaController 停止采集，
    // 避免创建过程中的并发保护阻止清理。
    try {
      await _cameraCreationFuture;
    } catch (_) {
      // 创建请求自行报告失败，关闭操作继续负责资源清理。
    }

    try {
      await _mediaController.stopLocalStream();
      _emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.idle,
          reason: reason,
        ),
      );
    } catch (error) {
      _report(error);
    }
  }

  /// 开始生成；已在生成时，改为更新生成条件，不重新等待首帧。
  ///
  /// 详细说明见 [XmaxRealtimeManaging.startGeneration]。
  @override
  Future<RealtimeMediaStream?> startGeneration({
    RealtimeMediaStream? localStream,
    RealtimeContext? context,
    bool faceRestoration = false,
  }) async {
    final timing =
        _state.connectionState != RealtimeConnectionState.generating &&
            _startingGenerationTaskID == null
        ? RealtimeTiming()
        : null;
    // 新请求会替代仍在连接或等待结果流的旧请求。
    final requestVersion = ++_generationRequestVersion;

    _generationManager.cancelPendingStart();

    try {
      final prepared = await _enqueueGenerationOperation(
        () => _prepareGeneration(
          localStream: localStream,
          context: context,
          faceRestoration: faceRestoration,
          requestVersion: requestVersion,
          timing: timing,
        ),
      );

      // 首帧等待不占用生成操作队列，解码启动期间仍可更新条件或停止生成。
      await prepared.readiness;

      return prepared.remoteStream;
    } catch (error) {
      timing?.finishFailure(error);
      rethrow;
    }
  }

  /// 准备连接和生成任务，不在生成操作队列中等待首帧。
  ///
  /// - [localStream]：当前管理器创建的本地媒体流。
  /// - [context]：本次生成条件；null 时读取缓存条件。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭。
  /// - [requestVersion]：本次生成请求的版本号。
  /// - [timing]：启动耗时记录器；未提供时不记录。
  ///
  /// 返回远端媒体流，以及用于等待生成就绪的独立任务。
  Future<_PreparedGeneration> _prepareGeneration({
    required RealtimeMediaStream? localStream,
    required RealtimeContext? context,
    required bool faceRestoration,
    required int requestVersion,
    RealtimeTiming? timing,
  }) async {
    // 断开连接期间收到的新生成请求，等待清理完成后再启动。
    await _disconnectFuture;
    _ensureGenerationRequestCurrent(requestVersion);

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
        remoteStream = await _connect(localStream: localStream, timing: timing);
        _ensureGenerationRequestCurrent(requestVersion);
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

  /// 依据当前连接状态启动生成或更新生成条件。
  ///
  /// - [context]：本次生成条件；null 时由生成协调器解析缓存条件。
  /// - [requestVersion]：生成请求的版本号。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  /// - [timing]：当前生成启动的耗时记录；为空时不记录。
  ///
  /// 返回当前生成的独立就绪任务。
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

    final activeTaskID = _state.taskID ?? _startingGenerationTaskID;

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
              _startingGenerationCompleter?.future ?? Future<void>.value(),
        );
      } catch (error) {
        if (requestVersion != _generationRequestVersion) {
          throw XmaxError.from(error);
        }

        throw _report(error);
      }
    }

    // 参数错误只使本次调用失败；远端任务启动后的运行错误才需要清理连接。
    try {
      _generationManager.validateContext(context);
    } catch (error) {
      throw _report(error);
    }

    final version = _operationVersion;

    try {
      final taskID = await _generationManager.start(
        timing: timing,
        videoFormat: videoFormat,
        context: context,
        faceRestoration: faceRestoration,
        ensureCurrent: () => _ensureCurrent(version),
      );

      final completer = Completer<void>();
      // 立即接收等待任务的异常，避免调用方尚未开始等待时出现未处理的异步错误。
      completer.future.ignore();

      _startingGenerationTaskID = taskID;
      _startingGenerationCompleter = completer;
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
      // 请求被新请求替代是正常的内部流程，不作为运行错误上报。
      if (requestVersion != _generationRequestVersion ||
          version != _operationVersion) {
        throw XmaxError.from(error);
      }

      final xmaxError = _report(error);

      timing?.finishFailure(xmaxError);
      await disconnect(reason: RealtimeReason.failure(xmaxError));
      throw xmaxError;
    }
  }

  /// 等待结果流确认、首帧解码和音频激活，再将状态更新为 generating。
  ///
  /// - [sessionID]：云端实时会话标识。
  /// - [taskID]：当前生成任务标识。
  /// - [operationVersion]：本次连接或本地媒体操作的版本号。
  /// - [completer]：接收启动结果或异常的完成器。
  /// - [timing]：启动耗时记录器；未提供时不记录。
  Future<void> _completeGenerationStart({
    required String sessionID,
    required String taskID,
    required int operationVersion,
    required Completer<void> completer,
    RealtimeTiming? timing,
  }) async {
    try {
      await _connectionManager.waitUntilRemoteFrameReady();
      _ensureCurrent(operationVersion);
      await _streamController.activateRemoteAudio();
      _ensureCurrent(operationVersion);
      if (_connectionManager.currentSessionID != sessionID) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      _emit(
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
      if (!completer.isCompleted && operationVersion == _operationVersion) {
        final xmaxError = _report(error);

        timing?.finishFailure(xmaxError);
        // 先移除失败的等待任务，避免断开连接时用取消错误覆盖原始错误。
        // 面向接入方的异步调用在会话清理完成后结束。
        if (identical(_startingGenerationCompleter, completer)) {
          _startingGenerationCompleter = null;
        }

        await disconnect(reason: RealtimeReason.failure(xmaxError));
        completer.completeError(xmaxError);
      }
    } finally {
      if (identical(_startingGenerationCompleter, completer)) {
        _startingGenerationTaskID = null;
        _startingGenerationCompleter = null;
      }
    }
  }

  /// 停止当前生成任务和交互输入，保留 RTC 连接。
  Future<void> stopGeneration() {
    _generationRequestVersion += 1;
    _generationManager.cancelPendingStart();

    return _enqueueGenerationOperation(_performStopGeneration);
  }

  /// 停止当前任务及交互输入，保留 RTC 房间连接。
  Future<void> _performStopGeneration() async {
    final sessionID = _connectionManager.currentSessionID;

    if (sessionID.isEmpty ||
        (_state.connectionState != RealtimeConnectionState.connected &&
            _state.connectionState != RealtimeConnectionState.generating)) {
      return;
    }

    final taskID = _state.taskID ?? _startingGenerationTaskID ?? '';
    final wasGenerating =
        _state.connectionState == RealtimeConnectionState.generating ||
        _startingGenerationTaskID != null;

    // 先取消仍在等待结果流的请求，避免停止后又切回 generating 状态。
    _operationVersion += 1;
    _generationRequestVersion += 1;
    _cancelStartingGeneration();

    try {
      await _connectionManager.prepareForRemoteRemoval();
      await _generationManager.stop(taskID: taskID);
    } catch (error) {
      _report(error);
    }

    if (wasGenerating) {
      _emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.connected,
          sessionID: sessionID,
        ),
      );
    }
  }

  /// 按顺序执行生成操作，前一次失败不阻止后续操作。
  ///
  /// - [operation]：要执行的异步操作。
  ///
  /// 返回 [operation] 的执行结果；该操作失败时保留原异常。
  Future<T> _enqueueGenerationOperation<T>(
    Future<T> Function() operation,
  ) {
    // Dart 的 Future 无法直接取消，因此生成操作按请求顺序执行，
    // 断开连接时再通过版本号使未完成的操作失效。
    final cancellationVersion = _generationCancellationVersion;
    final previousOperation = _generationOperation;
    final completion = Completer<void>();

    _generationOperation = completion.future;

    return () async {
      await previousOperation;

      try {
        _ensureGenerationOperationCurrent(cancellationVersion);

        final result = await operation();

        _ensureGenerationOperationCurrent(cancellationVersion);

        return result;
      } finally {
        completion.complete();
      }
    }();
  }

  /// 使正在启动的生成请求失效并结束其就绪等待。
  void _cancelStartingGeneration() {
    final completer = _startingGenerationCompleter;

    _startingGenerationTaskID = null;
    _startingGenerationCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime generation was cancelled',
        ),
      );
    }
  }

  /// 仅在失败会话仍有效时清理远端连接并通知失败状态。
  ///
  /// - [sessionID]：云端实时会话标识。
  /// - [error]：本次操作的错误。
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

  /// 按错误范围关闭当前媒体或远端连接，并隔离过期错误。
  ///
  /// - [error]：本次操作的错误。
  /// - [scope]：错误影响的资源范围。
  /// - [isCurrent]：检查操作是否仍属于当前生命周期的函数。
  Future<void> _handleStreamFailure(
    XmaxError error,
    RealtimeFailureScope scope,
    bool Function() isCurrent,
  ) async {
    // 方法调用失败通过对应的 Future 返回；
    // 这里只处理 RTC 主动上报的错误，并清理受影响的资源。
    if (!isCurrent() ||
        _closeFuture != null ||
        _state.connectionState == RealtimeConnectionState.idle) {
      return;
    }

    final reason = RealtimeReason.failure(error);

    if (scope == RealtimeFailureScope.all) {
      // 本地媒体出错时，先等待正在进行的远端清理完成，再释放本地媒体。
      await _closeWithReason(reason);
    } else if (_state.connectionState !=
        RealtimeConnectionState.disconnecting) {
      await disconnect(reason: reason);
    }
  }

  /// 本地预览首帧就绪后，将状态更新为 ready。
  void _cameraPreviewDidBecomeReady() {
    if (_mediaController.currentTrack == null) return;

    if (_state.connectionState == RealtimeConnectionState.preparing) {
      _emit(
        const RealtimeState(connectionState: RealtimeConnectionState.ready),
      );
    }
  }

  /// 保存并通知当前实时状态。
  ///
  /// - [state]：当前实时生命周期状态。
  void _emit(
    RealtimeState state,
  ) {
    final previous = _state.connectionState;

    _state = state;
    if (previous != state.connectionState) {
      XmaxLogger.debug(
        category: XmaxLoggerCategory.realtime,
        message:
            '实时状态 (Realtime State)\n'
            '└─ ${previous.name} → ${state.connectionState.name}',
      );
    }

    _stateListener?.call(state);
  }

  /// 转换并记录当前操作错误。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回统一 SDK 错误。
  XmaxError _report(
    Object error,
  ) => _errorHandler.report(error);

  /// 校验操作仍属于当前生命周期，否则抛出取消错误。
  ///
  /// - [version]：当前异步操作的版本号。
  void _ensureCurrent(
    int version,
  ) {
    if (version != _operationVersion) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime connection was cancelled',
      );
    }
  }

  /// 校验生成操作未被停止或新的生命周期取消。
  ///
  /// - [version]：当前异步操作的版本号。
  void _ensureGenerationOperationCurrent(
    int version,
  ) {
    if (version != _generationCancellationVersion) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime generation operation was cancelled',
      );
    }
  }

  /// 校验生成请求仍为当前有效请求。
  ///
  /// - [version]：当前异步操作的版本号。
  void _ensureGenerationRequestCurrent(
    int version,
  ) {
    if (version != _generationRequestVersion) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime generation request was superseded',
      );
    }
  }

  /// 校验音量为 0～1 内的有限数值，否则抛出配置错误。
  ///
  /// - [volume]：音量，范围为 0～1；超出范围、NaN 或无穷大时抛出 invalidConfiguration 错误。
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

/// 已准备的远端媒体流及其生成就绪任务。
final class _PreparedGeneration {

  /// 保存已准备的远端流及其就绪任务。
  const _PreparedGeneration({
    required this.remoteStream,
    required this.readiness,
  });

  /// 当前生成结果的远端媒体流。
  final RealtimeMediaStream? remoteStream;

  /// 等待生成就绪的异步任务；失败或取消时抛出异常。
  final Future<void> readiness;
}

/// 生成启动阶段的就绪任务。
final class _PreparedGenerationTask {

  /// 保存生成启动的就绪任务。
  const _PreparedGenerationTask({
    required this.readiness,
  });

  /// 等待生成就绪的异步任务；失败或取消时抛出异常。
  final Future<void> readiness;
}
