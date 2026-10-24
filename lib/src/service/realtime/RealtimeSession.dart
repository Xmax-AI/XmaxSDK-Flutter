//
//  RealtimeSession.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeSessionConnection.dart';

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
