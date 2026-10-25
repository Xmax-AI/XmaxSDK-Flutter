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
import 'RtcRoomEvent.dart';

/// A vendor-independent room serving one connection and its media and signaling.
abstract interface class RtcRoom {

  /// Whether the room has been closed.
  bool get isClosed;

  /// Sets publication, first-frame, quality, and failure delivery for this room.
  ///
  /// [listener] receives normalized events; null removes delivery.
  void setEventListener(
    void Function(
      RtcRoomEvent event,
    )? listener,
  );

  /// Joins RTC and prepares signaling without automatically publishing or subscribing to media.
  ///
  /// [configuration] contains the room identifier, local account, and access token.
  Future<void> join(
    RoomJoinConfiguration configuration,
  );

  /// Closes signaling and awaits native leave without stopping local capture or preview.
  Future<void> destroy();

  /// Publishes the current camera or external input and its enabled audio source.
  ///
  /// [publish] controls local video and opted-in microphone or external audio.
  Future<void> publishLocalVideo(
    bool publish,
  );

  /// Changes a remote user's video subscription.
  ///
  /// Parameters:
  /// - [userID]: The remote RTC account.
  /// - [subscribe]: Whether to receive video.
  Future<void> subscribeRemoteVideo({
    required String userID,
    required bool subscribe,
  });

  /// Changes a remote user's audio subscription.
  ///
  /// Parameters:
  /// - [userID]: The remote RTC account.
  /// - [subscribe]: Whether to receive audio.
  Future<void> subscribeRemoteAudio({
    required String userID,
    required bool subscribe,
  });

  /// Sets a remote user's playback volume.
  ///
  /// Parameters:
  /// - [volume]: The playback volume percentage, from 0 to 100.
  /// - [userID]: The remote RTC account.
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String userID,
  });

  /// Enqueues ordered signaling, replacing pending trajectories when conditions change.
  ///
  /// [message] is the complete JSON message. Adaptive configuration failures are returned
  /// to the caller without failing the room connection.
  Future<void> sendMessage(
    String message,
  );
}
