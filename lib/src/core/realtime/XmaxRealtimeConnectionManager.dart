//
//  XmaxRealtimeConnectionManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../media/interaction/InteractionControlling.dart';
import '../../render/RenderControlling.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeModel.dart';
import '../../service/realtime/RealtimeSession.dart';
import '../../service/realtime/RealtimeSessionServicing.dart';
import '../../service/realtime/RealtimeTiming.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../../stream/StreamControlling.dart';

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
  }) : _sessionService = sessionService,
       _interactionController = interactionController,
       _renderController = renderController,
       _streamController = streamController;

  /// The service that creates, maintains, and closes server sessions.
  final RealtimeSessionServicing _sessionService;

  /// The controller that samples and maps interactions for the generation task.
  final InteractionControlling _interactionController;

  /// The controller that owns remote track bindings and readiness.
  final RenderControlling _renderController;

  /// The controller that manages RTC publishing, subscriptions, and signaling.
  final StreamControlling _streamController;

  /// The remote video track owned by the current connection.
  RealtimeVideoTrack? _activeRemoteTrack;

  /// The active server session, or null when disconnected.
  RealtimeSession? _activeSession;

  /// The active session identifier, or an empty string when disconnected.
  String get currentSessionID => _activeSession?.id ?? '';

  /// Waits for the first decoded result frame without requiring a mounted remote view.
  Future<void> waitUntilRemoteFrameReady() =>
      _renderController.waitUntilRemoteFrameReady();

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
  /// - [timing]: The startup duration recorder, or null to omit timing.
  ///
  /// Returns the remote media stream associated with this session.
  Future<RealtimeMediaStream> connect({
    required RealtimeModel model,
    required RealtimeVideoFormat videoFormat,
    required bool Function() isCurrent,
    required RealtimeConnectionHeartbeatFailureHandler onHeartbeatFailure,
    RealtimeTiming? timing,
  }) async {
    RealtimeSession? session;
    var activated = false;

    try {
      // Create the cloud session before joining RTC with its credentials.
      timing?.beginSessionCreation();
      session = await _sessionService.createSession(model: model);
      timing?.finishSessionCreation();
      _ensureCurrent(isCurrent);

      final connection = session.connection;

      if (connection == null) {
        throw const XmaxError(
          code: XmaxErrorCode.sessionError,
          message: 'Session does not contain complete RTC join information',
        );
      }

      timing?.beginRoomJoin();
      await _streamController.connect(
        connection: connection,
        ensureActive: () => _ensureCurrent(isCurrent),
      );
      timing?.finishRoomJoin();
      _ensureCurrent(isCurrent);

      // Start the session heartbeat only after RTC connects.
      _sessionService.startHeartbeat(
        sessionID: session.id,
        onFailure: onHeartbeatFailure,
      );

      final track = createRealtimeVideoTrack(
        id: connection.botName ?? 'video-remote',
        videoFormat: videoFormat,
      );

      _renderController.registerRemoteTrack(
        track,
        interactionListener: _interactionController.submitInteraction,
      );

      _activeSession = session;
      _activeRemoteTrack = track;
      activated = true;

      _ensureCurrent(isCurrent);

      return createRealtimeMediaStream(
        id: 'stream-remote',
        videoTrack: track,
      );
    } catch (error) {
      if (isCurrent()) {
        timing?.finishFailure(error);
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

  /// Ends generation and disconnects realtime while retaining the local camera preview.
  ///
  /// Returns the closed session identifier, or null if no session was active.
  Future<String?> disconnect() async {
    final session = _activeSession;
    final track = _activeRemoteTrack;

    // Clear resource ownership before cleanup to prevent reentrant use of expired state.
    _activeSession = null;
    _activeRemoteTrack = null;

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
