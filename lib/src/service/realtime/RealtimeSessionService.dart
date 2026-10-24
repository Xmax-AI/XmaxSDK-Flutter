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

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/rtc/RtcEngineManager.dart';
import '../network/ApiServicing.dart';
import 'RealtimeModel.dart';
import 'RealtimeSession.dart';
import 'RealtimeSessionConnection.dart';
import 'RealtimeSessionServicing.dart';

/// Creates and closes server sessions while maintaining heartbeats and rejecting stale responses.
final class RealtimeSessionService implements RealtimeSessionServicing {

  /// Creates a session service with heartbeat scheduling.
  ///
  /// Parameters:
  /// - [apiService]: The API service for session creation, renewal, and closure.
  /// - [heartbeatInterval]: The heartbeat interval; defaults to 10 seconds.
  RealtimeSessionService({
    required ApiServicing apiService,
    Duration heartbeatInterval = const Duration(seconds: 10),
  }) : _apiService = apiService,
       _heartbeatInterval = heartbeatInterval;

  /// The service used for API requests.
  final ApiServicing _apiService;

  /// The server session heartbeat interval.
  final Duration _heartbeatInterval;

  /// The heartbeat revision used to reject earlier responses.
  int _heartbeatVersion = 0;

  /// The timer for the next session heartbeat.
  Timer? _heartbeatTimer;

  /// The signal aborting the current cycle's in-flight HTTP heartbeat.
  Completer<void>? _heartbeatCancellation;

  /// Creates a model session and validates its RTC connection credentials.
  ///
  /// See [RealtimeSessionServicing.createSession] for the usage contract.
  @override
  Future<RealtimeSession> createSession({
    required RealtimeModel model,
    Future<void>? cancellation,
  }) async {
    final payload = await _apiService.post<Map<String, dynamic>>(
      '/session',
      _map,
      body: <String, Object?>{'model': model.value},
      cancellation: cancellation,
    );

    return _makeSession(
      payload,
      requiresConnection: true,
    );
  }

  /// Starts heartbeats for a session, replacing the previous heartbeat cycle.
  ///
  /// See [RealtimeSessionServicing.startHeartbeat] for the usage contract.
  @override
  void startHeartbeat({
    required String sessionID,
    required RealtimeSessionHeartbeatFailureHandler onFailure,
  }) {
    stopHeartbeat();

    // Invalidates cancelled timers and requests so stale completions cannot restart heartbeats.
    final version = ++_heartbeatVersion;

    _heartbeatCancellation = Completer<void>();
    _heartbeatTimer = Timer(
      _heartbeatInterval,
      () {
      unawaited(_heartbeat(
        sessionID,
        version,
        onFailure,
      ));
    },
    );
  }

  /// Stops heartbeats and invalidates responses from earlier requests.
  @override
  void stopHeartbeat() {
    _heartbeatVersion += 1;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final cancellation = _heartbeatCancellation;

    _heartbeatCancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  /// Closes the specified server session.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  @override
  Future<void> closeSession({
    required String sessionID,
  }) async {
    await _apiService.delete<Map<String, dynamic>>(
      '/session/$sessionID',
      _map,
    );
  }

  /// Renews the session and notifies the current cycle's failure handler if it becomes invalid.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  /// - [version]: The asynchronous operation revision.
  /// - [onFailure]: The operation failure handler.
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
        cancellation: _heartbeatCancellation?.future,
      );

      if (version != _heartbeatVersion) {
        return;
      }

      final session = _makeSession(
        payload,
        requiresConnection: false,
      );

      if (session.status != null && session.status != 'ACTIVE') {
        throw XmaxError(
          code: XmaxErrorCode.sessionError,
          message:
              session.closeReason ??
              'Session is no longer active: ${session.status}',
        );
      }

      _heartbeatTimer = Timer(
        _heartbeatInterval,
        () {
        unawaited(_heartbeat(
          sessionID,
          version,
          onFailure,
        ));
      },
      );
    } catch (error) {
      if (version != _heartbeatVersion) {
        return;
      }

      _heartbeatVersion += 1;
      _heartbeatTimer = null;
      await onFailure(
        sessionID,
        error,
      );
    }
  }

  /// Decodes a session response and validates connection information when required.
  ///
  /// Parameters:
  /// - [payload]: The API response payload to decode.
  /// - [requiresConnection]: Whether complete RTC credentials are required in the response.
  ///
  /// Returns the decoded server session.
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

  /// Decodes RTC credentials from an object or JSON string and validates required fields and app
  /// identity.
  ///
  /// Parameters:
  /// - [modelExtra]: The server's RTC credentials as an object or JSON string.
  ///
  /// Returns complete RTC credentials, or null for missing fields or an app identifier mismatch.
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

  /// Validates a response as a JSON object with string keys.
  ///
  /// Parameters:
  /// - [json]: The JSON value to decode.
  ///
  /// Returns the validated JSON object.
  static Map<String, dynamic> _map(
    Object? json,
  ) => Map<String, dynamic>.from(json! as Map);

  /// Reads a nonempty string with surrounding whitespace removed.
  ///
  /// Parameters:
  /// - [value]: The response field; nonstrings and whitespace-only strings resolve to null.
  static String? _nonEmpty(
    Object? value,
  ) {
    final normalized = value is String ? value.trim() : null;

    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
