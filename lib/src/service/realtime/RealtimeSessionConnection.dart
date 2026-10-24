//
//  RealtimeSessionConnection.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The RTC credentials for a realtime session.
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
