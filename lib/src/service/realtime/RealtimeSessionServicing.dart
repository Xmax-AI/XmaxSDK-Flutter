//
//  RealtimeSessionServicing.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeModel.dart';
import 'RealtimeSession.dart';
import 'RealtimeSessionConnection.dart';

/// An interface for server session creation, heartbeats, and closure.
abstract interface class RealtimeSessionServicing {

  /// Creates a model session and validates its RTC connection credentials.
  ///
  /// Parameters:
  /// - [model]: The realtime generation model defining the supported media formats.
  ///
  /// Returns the decoded server session.
  Future<RealtimeSession> createSession({
    required RealtimeModel model,
  });

  /// Starts heartbeats for a session, replacing the previous heartbeat cycle.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  /// - [onFailure]: The operation failure handler.
  void startHeartbeat({
    required String sessionID,
    required RealtimeSessionHeartbeatFailureHandler onFailure,
  });

  /// Stops heartbeats and invalidates responses from earlier requests.
  void stopHeartbeat();

  /// Closes the specified server session.
  ///
  /// Parameters:
  /// - [sessionID]: The server session identifier.
  Future<void> closeSession({
    required String sessionID,
  });
}
