//
//  RtcManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../media/camera/CameraPosition.dart';
import 'RoomJoinConfiguration.dart';
import 'RtcEventListener.dart';
import 'VideoEncodingConfiguration.dart';

/// An interface for RTC capture, encoding, rooms, publication, subscriptions, and volume.
abstract interface class RtcManaging {

  /// Acquires and initializes the RTC engine for this lifecycle.
  ///
  /// Parameters:
  /// - [cancellation]: Completes to cancel engine acquisition. Queued requests are removed without
  ///   interrupting another owner's engine; native creation already in progress settles and releases
  ///   its resources before cancellation completes.
  Future<void> initialize({
    Future<void>? cancellation,
  });

  /// Releases RTC resources and invalidates subsequent native callbacks.
  Future<void> destroy();

  /// Applies video dimensions, frame rate, bitrate, and encoding preference to RTC.
  ///
  /// Parameters:
  /// - [configuration]: The encoding dimensions, frame rate, minimum and target bitrate, and
  ///   degradation preference.
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  );

  /// Starts camera capture and preview with the specified format, leaving the microphone disabled.
  ///
  /// Parameters:
  /// - [width]: The video width, in pixels.
  /// - [height]: The video height, in pixels.
  /// - [frameRate]: The video frame rate, in fps.
  Future<void> startVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  });

  /// Stops local preview and camera capture.
  Future<void> stopVideoCapture();

  /// Updates camera capture settings without stopping capture or remounting preview.
  ///
  /// Parameters:
  /// - [width]: The capture width, in pixels.
  /// - [height]: The capture height, in pixels.
  /// - [frameRate]: The capture frame rate, in fps.
  Future<void> updateVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  });

  /// Switches native capture to the specified camera.
  ///
  /// Parameters:
  /// - [position]: The camera position to select.
  Future<void> switchCamera({
    required CameraPosition position,
  });

  /// Joins an RTC room and releases its resources if joining fails.
  ///
  /// Parameters:
  /// - [configuration]: The room identifier, local account, and access token for this join.
  Future<void> joinRoom({
    required RoomJoinConfiguration configuration,
  });

  /// Leaves RTC and cancels pending signaling while preserving an active local camera preview.
  Future<void> leaveRoom();

  /// Sets camera publication for the current room without publishing microphone audio.
  ///
  /// Parameters:
  /// - [publish]: Whether to publish local camera video.
  Future<void> publishLocalVideo({
    required bool publish,
  });

  /// Sets video subscription for a remote user.
  ///
  /// Parameters:
  /// - [streamID]: The remote video stream identifier used to resolve its numeric UID.
  /// - [subscribe]: Whether to subscribe to the remote user's media.
  Future<void> subscribeRemoteVideo({
    required String streamID,
    required bool subscribe,
  });

  /// Sets audio subscription for a remote user.
  ///
  /// Parameters:
  /// - [streamID]: The remote audio stream identifier used to resolve its numeric UID.
  /// - [subscribe]: Whether to subscribe to the remote user's media.
  Future<void> subscribeRemoteAudio({
    required String streamID,
    required bool subscribe,
  });

  /// Applies a remote user's playback volume percentage to RTC.
  ///
  /// Parameters:
  /// - [volume]: The remote playback volume percentage, from 0 to 100.
  /// - [streamID]: The remote audio stream whose volume is updated.
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String streamID,
  });

  /// Sends ordered room signaling with fragmentation and rate limiting when needed.
  ///
  /// Parameters:
  /// - [message]: The complete message text.
  Future<void> sendRoomMessage(
    String message,
  );

  /// Replaces the internal RTC event listener.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setEventListener(
    RtcEventListener? listener,
  );

  /// Sets the internal local camera first-frame callback.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setCameraPreviewReadyListener(
    void Function()? listener,
  );
}
