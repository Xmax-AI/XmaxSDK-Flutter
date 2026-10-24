//
//  RealtimeSession.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The server-assigned RTC credentials and expected result user account.
final class RealtimeSessionConnection {

  /// Creates server-assigned RTC connection parameters.
  const RealtimeSessionConnection({
    required this.roomID,
    required this.userID,
    required this.token,
    this.botName,
  });

  /// The server-assigned RTC room identifier.
  final String roomID;

  /// The RTC user account, not a numeric UID.
  final String userID;

  /// The RTC access token used to join the room.
  final String token;

  /// The expected result account; null or empty disables account-specific filtering.
  final String? botName;
}

/// A server session identifier, status, connection credentials, and close reason.
final class RealtimeSession {

  /// Creates a server session snapshot.
  const RealtimeSession({
    required this.id,
    this.userID,
    this.status,
    this.connection,
    this.closeReason,
  });

  /// The unique server session identifier.
  final String id;

  /// The server-side user identifier, not an RTC account; null when omitted by the server.
  final String? userID;

  /// The session status, when returned by the server.
  final String? status;

  /// The server-assigned RTC credentials, which heartbeat responses may omit.
  final RealtimeSessionConnection? connection;

  /// The session close reason, when provided.
  final String? closeReason;
}

/// An asynchronous handler for an invalid session or failed heartbeat.
///
/// Parameters:
/// - [sessionID]: The server session identifier.
/// - [error]: The operation error.
typedef RealtimeSessionHeartbeatFailureHandler =
    Future<void> Function(
      String sessionID,
      Object error,
    );
