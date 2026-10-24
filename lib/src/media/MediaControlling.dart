//
//  MediaControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../foundation/media/camera/CameraPosition.dart';
import '../service/realtime/RealtimeMediaStream.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import 'interaction/InteractionControlling.dart';

/// The media layer interface used by Core.
abstract interface class MediaControlling implements InteractionControlling {

  /// The active local video track; null before creation or after stopping.
  RealtimeVideoTrack? get currentTrack;

  /// The current local track's video format; null before creation.
  RealtimeVideoFormat? get currentVideoFormat;

  /// Whether local media has playable audio; false for camera sources.
  bool get hasAudio;

  /// The local preview volume; fixed at 0.45 because camera sources have no audio player.
  Future<double> get localAudioVolume;

  /// Sets the internal local camera first-frame callback.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setCameraPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  );

  /// Creates a local camera stream, starts preview, and notifies the listener when ready.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [position]: The camera position to use.
  /// - [cancellation]: Completes to cancel pending engine acquisition before capture starts.
  ///
  /// Returns the new local camera stream; the future fails on invalid arguments or denied
  /// permission.
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
    Future<void>? cancellation,
  });

  /// Stops the local camera stream and releases capture resources.
  Future<void> stopLocalCameraStream();

  /// Stops the local media source and releases its ownership of the RTC engine.
  Future<void> stopLocalStream();

  /// Switches between the front and rear cameras.
  ///
  /// Returns the local camera stream after switching cameras.
  Future<RealtimeMediaStream> switchCamera();

  /// Updates the camera format in place, preserving the local track and preview binding.
  ///
  /// Parameters:
  /// - [videoFormat]: The capture format satisfying the current model's constraints.
  Future<void> updateCameraFormat(
    RealtimeVideoFormat videoFormat,
  );

  /// Validates local volume; camera sources have no audio player and continue to report 0.45.
  ///
  /// Parameters:
  /// - [volume]: A finite volume value between 0 and 1.
  Future<void> setLocalAudioVolume(
    double volume,
  );

  /// Checks whether a stream belongs to the current local media lifecycle.
  ///
  /// Parameters:
  /// - [stream]: The local media stream to check.
  ///
  /// Returns whether the stream belongs to the current local media lifecycle.
  bool owns(
    RealtimeMediaStream stream,
  );
}
