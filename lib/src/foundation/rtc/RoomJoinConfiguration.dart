//
//  RoomJoinConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The room identifier, user account, and token required to join RTC.
final class RoomJoinConfiguration {

  /// Creates RTC room credentials.
  const RoomJoinConfiguration({
    required this.roomID,
    required this.userID,
    required this.token,
  });

  /// The server-assigned RTC room identifier.
  final String roomID;

  /// The RTC user account, not a numeric UID.
  final String userID;

  /// The RTC access token used to join the room.
  final String token;
}
