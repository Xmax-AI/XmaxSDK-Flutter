//
//  RtcRoom.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RoomJoinConfiguration.dart';

/// One RTC room connection and its publication, subscription, and signaling resources.
abstract interface class RtcRoom {

  /// Whether the room has been closed.
  bool get isClosed;

  /// Joins RTC and prepares signaling without automatically publishing or subscribing to media.
  ///
  /// Parameters:
  /// - [configuration]: The room identifier, local account, and access token for this join.
  Future<void> join(
    RoomJoinConfiguration configuration,
  );

  /// Closes the room and waits for native leave without changing local camera capture.
  Future<void> destroy();

  /// Submits room signaling, discarding pending trajectories on condition changes; adaptive
  /// configuration failures retain the connection.
  ///
  /// Parameters:
  /// - [message]: The complete message text.
  Future<void> sendMessage(
    String message,
  );
}
