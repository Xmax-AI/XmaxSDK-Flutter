//
//  RtcModels.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

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

/// The dimensions, frame rate, bitrate, and degradation preference submitted to RTC encoding.
final class VideoEncodingConfiguration {

  /// Creates a video encoder configuration.
  const VideoEncodingConfiguration({
    required this.width,
    required this.height,
    required this.frameRate,
    this.minimumBitrate = 0,
    this.maximumBitrate = -1,
    this.encoderPreference = RealtimeVideoEncoderPreference.maintainFramerate,
  });

  /// The encoded width, in pixels.
  final int width;

  /// The encoded height, in pixels.
  final int height;

  /// The video frame rate, in fps.
  final int frameRate;

  /// The minimum encoding bitrate, in kbps; 0 uses RTC's minimum bitrate policy.
  final int minimumBitrate;

  /// The encoding target bitrate, in kbps; -1 uses RTC's compatibility bitrate mode.
  final int maximumBitrate;

  /// The bandwidth degradation preference; defaults to frame-rate priority.
  final RealtimeVideoEncoderPreference encoderPreference;
}

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
