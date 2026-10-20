//
//  RealtimeSessionService.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:convert';

import '../../core/realtime/RealtimeModel.dart';
import '../../foundation/errors/XmaxError.dart';
import '../../foundation/rtc/RtcEngineManager.dart';
import '../network/ApiServicing.dart';
import 'RealtimeSession.dart';
import 'RealtimeSessionServicing.dart';

/// 创建和关闭云端实时会话，定期维持会话并隔离过期心跳结果。
final class RealtimeSessionService implements RealtimeSessionServicing {

  /// 创建会话服务及心跳调度配置。
  ///
  /// - [apiService]：会话创建、续期和关闭的网络服务。
  /// - [heartbeatInterval]：会话续期间隔，默认 10 秒。
  RealtimeSessionService({
    required ApiServicing apiService,
    Duration heartbeatInterval = const Duration(seconds: 10),
  }) : _apiService = apiService,
       _heartbeatInterval = heartbeatInterval;

  /// 云端 API 请求服务。
  final ApiServicing _apiService;

  /// 云端会话心跳的发送间隔。
  final Duration _heartbeatInterval;

  /// 当前会话心跳的版本号，用于忽略旧请求的响应。
  int _heartbeatVersion = 0;

  /// 当前云端会话的下一次心跳计时器。
  Timer? _heartbeatTimer;

  /// 为指定模型创建云端实时会话，并校验完整 RTC 连接凭证。
  ///
  /// 详细说明见 [RealtimeSessionServicing.createSession]。
  @override
  Future<RealtimeSession> createSession({
    required RealtimeModel model,
  }) async {
    final payload = await _apiService.post<Map<String, dynamic>>(
      '/session',
      _map,
      body: <String, Object?>{'model': model.value},
    );

    return _makeSession(payload, requiresConnection: true);
  }

  /// 启动当前会话的心跳，替换先前心跳周期。
  ///
  /// 详细说明见 [RealtimeSessionServicing.startHeartbeat]。
  @override
  void startHeartbeat({
    required String sessionID,
    required RealtimeSessionHeartbeatFailureHandler onFailure,
  }) {
    stopHeartbeat();

    // 用版本号使已取消的定时器和请求失效，防止旧请求完成后重新启动心跳。
    final version = ++_heartbeatVersion;

    _heartbeatTimer = Timer(_heartbeatInterval, () {
      unawaited(_heartbeat(sessionID, version, onFailure));
    });
  }

  /// 停止会话心跳，并使旧心跳请求的响应失效。
  @override
  void stopHeartbeat() {
    _heartbeatVersion += 1;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 关闭指定云端实时会话。
  ///
  /// - [sessionID]：云端实时会话标识。
  @override
  Future<void> closeSession({
    required String sessionID,
  }) async {
    await _apiService.delete<Map<String, dynamic>>('/session/$sessionID', _map);
  }

  /// 维持指定会话，发现会话失效时通知当前周期的失败处理器。
  ///
  /// - [sessionID]：云端实时会话标识。
  /// - [version]：当前异步操作的版本号。
  /// - [onFailure]：操作失败时的处理回调。
  Future<void> _heartbeat(
    String sessionID,
    int version,
    RealtimeSessionHeartbeatFailureHandler onFailure,
  ) async {
    if (version != _heartbeatVersion) {
      return;
    }

    try {
      final payload = await _apiService.put<Map<String, dynamic>>(
        '/session/$sessionID/heartbeat',
        _map,
      );

      if (version != _heartbeatVersion) {
        return;
      }

      final session = _makeSession(payload, requiresConnection: false);

      if (session.status != null && session.status != 'ACTIVE') {
        throw XmaxError(
          code: XmaxErrorCode.sessionError,
          message:
              session.closeReason ??
              'Session is no longer active: ${session.status}',
        );
      }

      _heartbeatTimer = Timer(_heartbeatInterval, () {
        unawaited(_heartbeat(sessionID, version, onFailure));
      });
    } catch (error) {
      if (version != _heartbeatVersion) {
        return;
      }

      _heartbeatVersion += 1;
      _heartbeatTimer = null;
      await onFailure(sessionID, error);
    }
  }

  /// 解析云端会话响应，并按调用要求校验连接信息。
  ///
  /// - [payload]：待解析的业务响应对象。
  /// - [requiresConnection]：是否要求响应包含完整 RTC 连接凭证。
  ///
  /// 返回解析后的云端实时会话。
  RealtimeSession _makeSession(
    Map<String, dynamic> payload, {
    required bool requiresConnection,
  }) {
    final sessionID = _nonEmpty(payload['sessionUid']);

    if (sessionID == null) {
      throw const XmaxError(
        code: XmaxErrorCode.sessionError,
        message: 'Invalid session response',
      );
    }

    final userID = _nonEmpty(payload['userUid']);
    final connection = _makeConnection(payload['modelExtra']);

    if (requiresConnection && connection == null) {
      throw const XmaxError(
        code: XmaxErrorCode.sessionError,
        message: 'Session does not contain complete RTC join information',
      );
    }

    return RealtimeSession(
      id: sessionID,
      userID: userID,
      status: _nonEmpty(payload['status']),
      connection: connection,
      closeReason: _nonEmpty(payload['closeReason']),
    );
  }

  /// 解析 RTC 凭证对象或 JSON 字符串，校验必需字段及应用标识。
  ///
  /// - [modelExtra]：服务端返回的 RTC 凭证对象或 JSON 字符串。
  ///
  /// 返回完整 RTC 连接凭证；字段缺失或应用标识不匹配时返回 null。
  RealtimeSessionConnection? _makeConnection(
    Object? modelExtra,
  ) {
    Object? value = modelExtra;

    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }

    if (value is! Map) {
      return null;
    }

    final roomID = _nonEmpty(value['room_id']);
    final token = _nonEmpty(value['room_token']);
    final userID = _nonEmpty(value['rtc_user_id']);
    final botName = _nonEmpty(value['rtc_bot_id']);
    final appID = _nonEmpty(value['rtc_app_id']);

    if (roomID == null ||
        token == null ||
        userID == null ||
        botName == null ||
        appID != RtcEngineManager.defaultAppID) {
      return null;
    }

    return RealtimeSessionConnection(
      roomID: roomID,
      userID: userID,
      token: token,
      botName: botName,
    );
  }

  /// 将响应校验为字符串键的 JSON 对象。
  ///
  /// - [json]：待解析的 JSON 数据。
  ///
  /// 返回经过校验的 JSON 对象。
  static Map<String, dynamic> _map(
    Object? json,
  ) => Map<String, dynamic>.from(json! as Map);

  /// 读取非空字符串，去除首尾空白。
  ///
  /// - [value]：响应字段；不是字符串或内容为空白时返回 null。
  static String? _nonEmpty(
    Object? value,
  ) {
    final normalized = value is String ? value.trim() : null;

    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
