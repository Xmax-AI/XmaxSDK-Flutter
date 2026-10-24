//
//  XmaxRealtimeConnectionManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:ui';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../media/interaction/InteractionControlling.dart';
import '../../render/RenderControlling.dart';
import '../../service/media/MediaService.dart';
import '../../service/media/MediaServicing.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeModel.dart';
import '../../service/realtime/RealtimeSession.dart';
import '../../service/realtime/RealtimeSessionServicing.dart';
import '../../service/realtime/RealtimeTiming.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../../stream/StreamControlling.dart';
import '../../stream/quality/QualityVideoFormat.dart';
import '../../stream/quality/RealtimeQualityLevel.dart';
import 'RealtimeConfiguration.dart';

/// An asynchronous handler for a realtime session heartbeat failure.
///
/// Parameters:
/// - [sessionID]: The server session identifier.
/// - [error]: The operation error.
typedef RealtimeConnectionHeartbeatFailureHandler =
    Future<void> Function(
      String sessionID,
      Object error,
    );

/// Owns the server session, RTC connection, and remote track lifecycle.
final class XmaxRealtimeConnectionManager {

  /// Creates a realtime connection manager.
  XmaxRealtimeConnectionManager({
    required RealtimeSessionServicing sessionService,
    required InteractionControlling interactionController,
    required RenderControlling renderController,
    required StreamControlling streamController,
    MediaServicing? mediaService,
    RealtimeTiming? timing,
  }) : _sessionService = sessionService,
       _interactionController = interactionController,
       _renderController = renderController,
       _streamController = streamController,
       _mediaService = mediaService ?? MediaService(),
       timing = timing ?? RealtimeTiming();

  /// The service that creates, maintains, and closes server sessions.
  final RealtimeSessionServicing _sessionService;

  /// The controller that samples and maps interactions for the generation task.
  final InteractionControlling _interactionController;

  /// The controller that owns remote track bindings and readiness.
  final RenderControlling _renderController;

  /// The controller that manages RTC publishing, subscriptions, and signaling.
  final StreamControlling _streamController;

  /// The model-aware sizing rules for transport output.
  final MediaServicing _mediaService;

  /// The shared startup duration recorder.
  final RealtimeTiming timing;

  /// The renderer shared with generation readiness and the public facade.
  RenderControlling get renderController => _renderController;

  /// The most recently committed result dimensions, in pixels.
  Size? _currentTargetSize;

  /// The committed result dimensions for this connection.
  Size? get currentTargetSize => _currentTargetSize;

  /// The remote video track owned by the current connection.
  RealtimeVideoTrack? _activeRemoteTrack;

  /// The active server session, or null when disconnected.
  RealtimeSession? _activeSession;

  /// The active session identifier, or an empty string when disconnected.
  String get currentSessionID => _activeSession?.id ?? '';

  /// Waits for mounted views to conceal remote video before releasing its rendering resources.
  Future<void> prepareForRemoteRemoval() async {
    try {
      await _renderController.prepareForRemoteRemoval();
    } catch (error) {
      _logCleanupFailure(
        '隐藏远端视频失败 (Failed to Conceal Remote Video)',
        error,
      );
    }
  }

  /// The connection's remote media stream, or null without an active session.
  RealtimeMediaStream? get currentRemoteStream {
    final track = _activeRemoteTrack;

    if (_activeSession == null || track == null) {
      return null;
    }

    return createRealtimeMediaStream(
      id: 'stream-remote',
      videoTrack: track,
    );
  }

  /// Creates a server session, joins RTC, and publishes local video.
  ///
  /// Parameters:
  /// - [model]: The realtime generation model defining the supported media formats.
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [isCurrent]: A check that the operation still belongs to the current lifecycle.
  /// - [onHeartbeatFailure]: The handler for heartbeat failures in the current session.
  ///
  /// Returns the remote media stream associated with this session.
  Future<RealtimeMediaStream> connect({
    required RealtimeModel model,
    required RealtimeVideoFormat videoFormat,
    required bool Function() isCurrent,
    required RealtimeConnectionHeartbeatFailureHandler onHeartbeatFailure,
  }) async {
    RealtimeSession? session;
    var activated = false;

    try {
      timing.beginConnection();
      // Create the cloud session before joining RTC with its credentials.
      timing.beginSessionCreation();
      session = await _sessionService.createSession(model: model);
      timing.finishSessionCreation();
      _ensureCurrent(isCurrent);

      final connection = session.connection;

      if (connection == null) {
        throw const XmaxError(
          code: XmaxErrorCode.sessionError,
          message: 'Session does not contain complete RTC join information',
        );
      }

      timing.beginRoomJoin();
      await _streamController.connect(
        connection: connection,
        ensureActive: () => _ensureCurrent(isCurrent),
      );
      timing.finishRoomJoin();
      _ensureCurrent(isCurrent);

      // Start the session heartbeat only after RTC connects.
      _sessionService.startHeartbeat(
        sessionID: session.id,
        onFailure: onHeartbeatFailure,
      );

      final track = createRealtimeVideoTrack(
        id: connection.botName ?? 'video-remote',
        videoFormat: _remoteVideoFormat(videoFormat),
      );

      _renderController.registerRemoteTrack(
        track,
        interactionListener: _interactionController.submitInteraction,
      );

      _activeSession = session;
      _activeRemoteTrack = track;
      activated = true;

      _ensureCurrent(isCurrent);
      timing.finishConnection();

      return createRealtimeMediaStream(
        id: 'stream-remote',
        videoTrack: track,
      );
    } catch (error) {
      if (isCurrent()) {
        timing.finishFailure(error);
      }
      // Release local RTC and rendering state before closing the cloud session.
      if (isCurrent() || activated) {
        await _rollbackConnection();
      }

      if (session != null) {
        await _closeSessionAfterFailedConnection(session.id);
      }

      if (!isCurrent()) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime connection was cancelled',
        );
      }

      throw XmaxError.from(error);
    }
  }

  /// Prepares the initial encoder and returned dimensions without changing capture.
  ///
  /// Parameters:
  /// - [baseline]: The resolved local format, unchanged by quality adaptation.
  /// - [options]: The model and adaptive quality settings.
  /// - [ensureCurrent]: The validity check for the admitted connection operation.
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required RealtimeConfiguration options,
    required void Function() ensureCurrent,
  }) async {
    ensureCurrent();
    await _streamController.prepareQuality(
      baseline: baseline,
      model: options.model.value,
      minimumInputPixels: options.model.minimumInputPixels,
      isAdaptiveQualityEnabled: options.isAdaptiveQualityEnabled,
    );
    ensureCurrent();

    final configuration = _streamController.qualityConfiguration;
    if (configuration == null) {
      throw const XmaxError(
        code: XmaxErrorCode.internalError,
        message: 'Transport quality configuration is unavailable',
      );
    }
    await _streamController.setVideoEncoderConfig(configuration.uplink);
    ensureCurrent();
    _currentTargetSize = _resolveTargetSize(
      configuration.baseline,
      configuration.downlinkLevel,
    );
  }

  /// Records initial levels after generation and audio startup succeed.
  ///
  /// Parameters:
  /// - [ensureCurrent]: The validity check before each history commit.
  Future<void> completeInitialQuality(
    void Function() ensureCurrent,
  ) async {
    final configuration = _streamController.qualityConfiguration;
    if (configuration == null) {
      return;
    }
    for (final downlink in [false, true]) {
      ensureCurrent();
      await _streamController.completeQuality(
        downlink ? configuration.downlinkLevel : configuration.uplinkLevel,
        downlink: downlink,
        success: true,
      );
    }
    ensureCurrent();
  }

  /// Applies an uplink level or returned dimensions within an admitted operation.
  ///
  /// Parameters:
  /// - [level]: The requested transport level.
  /// - [downlink]: Whether to update returned dimensions rather than uplink encoding.
  /// - [taskID]: The active generation task.
  /// - [ensureCurrent]: The validity check across asynchronous boundaries.
  Future<void> applyQualityLevel(
    RealtimeQualityLevel level, {
    required bool downlink,
    required String taskID,
    required void Function() ensureCurrent,
  }) async {
    final configuration = _streamController.qualityConfiguration;
    if (configuration == null) {
      return;
    }
    try {
      ensureCurrent();
      if (downlink) {
        final target = _resolveTargetSize(
          configuration.baseline,
          level,
        );
        if (target != _currentTargetSize) {
          await _streamController.changeTargetSize(
            taskID: taskID,
            targetSize: target,
            ensureActive: ensureCurrent,
          );
          ensureCurrent();
          _currentTargetSize = target;
          final track = _activeRemoteTrack;
          if (track != null) {
            updateRealtimeVideoTrack(
              track: track,
              videoFormat: _remoteVideoFormat(configuration.baseline),
            );
          }
        }
      } else {
        await _streamController.setVideoEncoderConfig(
          QualityVideoFormat.resolve(
            configuration.baseline,
            level,
            downlink: false,
            minimumInputPixels: configuration.minimumInputPixels,
          ),
        );
      }

      ensureCurrent();
      await _streamController.completeQuality(
        level,
        downlink: downlink,
        success: true,
      );
      ensureCurrent();
    } catch (error) {
      ensureCurrent();
      await _streamController.completeQuality(
        level,
        downlink: downlink,
        success: false,
      );
      rethrow;
    }
  }

  /// Resolves aspect-preserving returned dimensions within a downlink level.
  ///
  /// Parameters:
  /// - [baseline]: The resolved local media format.
  /// - [level]: The downlink quality level.
  ///
  /// Returns dimensions aligned to 4 without imposing the uplink area floor.
  Size _resolveTargetSize(
    RealtimeVideoFormat baseline,
    RealtimeQualityLevel level,
  ) => _mediaService.resolveTargetSize(
    Size(
      baseline.width.toDouble(),
      baseline.height.toDouble(),
    ),
    maximumSize: QualityVideoFormat.downlinkMaximumSize(
      baseline,
      level,
    ),
  );

  /// Applies the current returned dimensions while retaining media encoding metadata.
  ///
  /// Parameters:
  /// - [mediaFormat]: The resolved local media baseline.
  ///
  /// Returns the remote track's format without changing the local capture format.
  RealtimeVideoFormat _remoteVideoFormat(
    RealtimeVideoFormat mediaFormat,
  ) {
    final target = _currentTargetSize;
    return target == null ? mediaFormat : mediaFormat.resized(
      width: target.width.toInt(),
      height: target.height.toInt(),
    );
  }

  /// Ends generation and disconnects realtime while retaining the local camera preview.
  ///
  /// Returns the closed session identifier, or null if no session was active.
  Future<String?> disconnect() async {
    final session = _activeSession;
    final track = _activeRemoteTrack;

    // Clear resource ownership before cleanup to prevent reentrant use of expired state.
    _activeSession = null;
    _activeRemoteTrack = null;

    _currentTargetSize = null;
    _streamController.setAdaptiveQualityListener(null);
    _sessionService.stopHeartbeat();
    await prepareForRemoteRemoval();
    _resetRemoteRendering(track);
    await _disconnectStreamSafely();

    if (session != null) {
      await _sessionService.closeSession(sessionID: session.id);
    }

    return session?.id;
  }

  /// Rolls back connection state and releases remote bindings.
  Future<void> _rollbackConnection() async {
    final track = _activeRemoteTrack;

    _activeSession = null;
    _activeRemoteTrack = null;

    _sessionService.stopHeartbeat();
    await prepareForRemoteRemoval();
    _resetRemoteRendering(track);
    await _disconnectStreamSafely();
  }

  /// Releases RTC resources and continues session cleanup even if RTC cleanup fails.
  Future<void> _disconnectStreamSafely() async {
    try {
      await _streamController.disconnect();
    } catch (error) {
      // Close the cloud session even if RTC cleanup fails, preserving the original connection error.
      _logCleanupFailure(
        '清理 RTC 连接失败 (Failed to Clean Up RTC Connection)',
        error,
      );
    }
  }

  /// Clears rendering and interaction bindings for a remote track.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  void _resetRemoteRendering(
    RealtimeVideoTrack? track,
  ) {
    try {
      _renderController.resetRemoteTrack(track);
    } catch (error) {
      _logCleanupFailure(
        '重置远端视频渲染失败 (Failed to Reset Remote Video Rendering)',
        error,
      );
    }
  }

  /// Closes a session created by a failed connection without replacing the original error.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  Future<void> _closeSessionAfterFailedConnection(
    String sessionID,
  ) async {
    try {
      await _sessionService.closeSession(sessionID: sessionID);
    } catch (error) {
      _logCleanupFailure(
        '连接回滚关闭会话失败 '
        '(Failed to Close Session During Connection Rollback)',
        error,
      );
    }
  }

  /// Logs cleanup failures without replacing the operation error.
  ///
  /// Parameters:
  /// - [title]: The log group's title.
  /// - [error]: The operation error.
  static void _logCleanupFailure(
    String title,
    Object error,
  ) {
    XmaxLogger.error(
      category: XmaxLoggerCategory.realtime,
      message: '$title\n└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
    );
  }

  /// Rejects an operation that no longer belongs to the current lifecycle.
  ///
  /// Parameters:
  /// - [isCurrent]: A check that the operation still belongs to the current lifecycle.
  static void _ensureCurrent(
    bool Function() isCurrent,
  ) {
    if (!isCurrent()) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime connection was cancelled',
      );
    }
  }
}
