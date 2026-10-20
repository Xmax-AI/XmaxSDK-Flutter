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
import '../../service/realtime/RealtimeSession.dart';
import '../../service/realtime/RealtimeSessionServicing.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../../stream/StreamControlling.dart';
import 'RealtimeModel.dart';
import 'RealtimeTiming.dart';

/// 接收指定实时会话心跳失败的异步回调。
///
/// - [sessionID]：云端实时会话标识。
/// - [error]：本次操作的错误。
typedef RealtimeConnectionHeartbeatFailureHandler =
    Future<void> Function(
      String sessionID,
      Object error,
    );

/// 协调云端会话、RTC 房间和远端视频轨道的连接与释放。
final class XmaxRealtimeConnectionManager {

  /// 创建会话与 RTC 连接协调器。
  XmaxRealtimeConnectionManager({
    required RealtimeSessionServicing sessionService,
    required InteractionControlling interactionController,
    required RenderControlling renderController,
    required StreamControlling streamController,
  }) : _sessionService = sessionService,
       _interactionController = interactionController,
       _renderController = renderController,
       _streamController = streamController;

  /// 创建、维持和关闭云端实时会话的服务。
  final RealtimeSessionServicing _sessionService;

  /// 当前生成任务的触点采样和坐标处理组件。
  final InteractionControlling _interactionController;

  /// 管理远端轨道绑定及视频就绪的组件。
  final RenderControlling _renderController;

  /// 管理 RTC 连接、发布订阅和生成信令的组件。
  final StreamControlling _streamController;

  /// 当前连接持有的远端视频轨道。
  RealtimeVideoTrack? _activeRemoteTrack;

  /// 当前有效的云端会话；未连接时为空。
  RealtimeSession? _activeSession;

  /// 当前云端会话标识；未连接时为空字符串。
  String get currentSessionID => _activeSession?.id ?? '';

  /// 等待当前结果流首帧解码就绪，不要求预先挂载远端视图。
  Future<void> waitUntilRemoteFrameReady() =>
      _renderController.waitUntilRemoteFrameReady();

  /// 等待已挂载视图隐藏远端视频，再释放对应渲染资源。
  Future<void> prepareForRemoteRemoval() async {
    try {
      await _renderController.prepareForRemoteRemoval();
    } catch (error) {
      _logCleanupFailure('隐藏远端视频失败 (Failed to Conceal Remote Video)', error);
    }
  }

  /// 当前连接的远端媒体流；没有活动会话时为空。
  RealtimeMediaStream? get currentRemoteStream {
    final track = _activeRemoteTrack;

    if (_activeSession == null || track == null) {
      return null;
    }

    return createRealtimeMediaStream(id: 'stream-remote', videoTrack: track);
  }

  /// 创建云端会话并建立 RTC 连接，随后发布本地视频。
  ///
  /// - [model]：实时模型；用于确定会话路由及媒体规格约束。
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [isCurrent]：检查操作是否仍属于当前生命周期的函数。
  /// - [onHeartbeatFailure]：当前云端会话心跳失败时的处理函数。
  /// - [timing]：当前生成启动的耗时记录；为空时不记录。
  ///
  /// 返回本次会话关联的远端媒体流。
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
      // 先创建云端会话，再使用返回的凭证加入 RTC 房间。
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

      // RTC 连接成功后再启动会话心跳。
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

      return createRealtimeMediaStream(id: 'stream-remote', videoTrack: track);
    } catch (error) {
      if (isCurrent()) timing?.finishFailure(error);
      // 先清理本地 RTC 和渲染状态，再关闭云端会话。
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

  /// 结束当前生成并断开远端连接，保留本地摄像头预览。
  ///
  /// 返回刚关闭的会话标识；没有活动会话时为 null。
  Future<String?> disconnect() async {
    final session = _activeSession;
    final track = _activeRemoteTrack;

    // 先清除当前资源归属，避免重入回调继续使用已失效的状态。
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

  /// 撤销已建立的本地连接状态并安全释放远端绑定。
  Future<void> _rollbackConnection() async {
    final track = _activeRemoteTrack;

    _activeSession = null;
    _activeRemoteTrack = null;

    _sessionService.stopHeartbeat();
    await prepareForRemoteRemoval();
    _resetRemoteRendering(track);
    await _disconnectStreamSafely();
  }

  /// 释放 RTC 连接；清理失败只记录日志，仍继续关闭云端会话。
  Future<void> _disconnectStreamSafely() async {
    try {
      await _streamController.disconnect();
    } catch (error) {
      // 即使 RTC 清理失败，也要关闭云端会话，并保留最初的连接错误。
      _logCleanupFailure(
        '清理 RTC 连接失败 (Failed to Clean Up RTC Connection)',
        error,
      );
    }
  }

  /// 解除指定远端轨道的渲染和交互绑定。
  ///
  /// - [track]：目标视频轨道。
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

  /// 关闭连接失败时已创建的云端会话，保留原始连接错误。
  ///
  /// - [sessionID]：云端实时会话标识。
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

  /// 记录资源释放错误，不替换当前业务错误。
  ///
  /// - [title]：日志组的标题。
  /// - [error]：本次操作的错误。
  static void _logCleanupFailure(
    String title,
    Object error,
  ) {
    XmaxLogger.error(
      category: XmaxLoggerCategory.realtime,
      message: '$title\n└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
    );
  }

  /// 校验操作仍属于当前生命周期，否则抛出取消错误。
  ///
  /// - [isCurrent]：检查操作是否仍属于当前生命周期的函数。
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
