//
//  RemoteStream.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// A remote stream identity and the native bindings required for rendering.
final class RemoteStream {

  /// Creates a remote media stream binding.
  const RemoteStream({
    required this.roomID,
    required this.userID,
    required this.streamID,
    this.uid,
    this.localUid,
    this.engine,
  });

  /// The server-assigned RTC room identifier.
  final String roomID;

  /// The RTC user account, not a numeric UID.
  final String userID;

  /// The remote video stream identifier.
  final String streamID;

  /// The native-assigned remote UID; rendering requires it to be resolved.
  final int? uid;

  /// The local numeric UID identifying the RTC connection for remote rendering.
  final int? localUid;

  /// The RTC engine required to create a remote video texture.
  final RtcEngine? engine;

  /// The room and account identity used to match a user's media events.
  String get key => '$roomID:$userID';
}
