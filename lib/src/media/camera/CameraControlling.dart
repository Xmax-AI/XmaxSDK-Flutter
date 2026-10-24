//
//  CameraControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/media/camera/CameraPosition.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';

/// An interface for camera streams and preview resources.
abstract interface class CameraControlling {

  /// The current camera track, or null before creation or after stopping.
  RealtimeVideoTrack? get currentTrack;

  /// Sets a one-shot readiness listener requiring a valid frame and an attached preview.
  ///
  /// Parameters:
  /// - [listener]: The readiness listener, or null to remove it.
  void setPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  );

  /// Creates and starts a local camera stream.
  ///
  /// Parameters:
  /// - [videoFormat]: The capture and encoding settings, subject to the model's dimension rules.
  /// - [position]: The camera position to use initially.
  ///
  /// Returns the local camera stream.
  ///
  /// The returned future completes with an error if a stream exists, permission is denied,
  /// configuration is invalid, or capture fails.
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
  });

  /// Stops camera capture and releases preview resources.
  Future<void> stopLocalCameraStream();

  /// Switches cameras while retaining the video track.
  ///
  /// Returns the local camera stream with updated camera position metadata.
  ///
  /// The returned future completes with an error if capture is inactive or switching fails.
  Future<RealtimeMediaStream> switchCamera();

  /// Updates dimensions and frame rate while retaining the camera and preview track.
  ///
  /// Parameters:
  /// - [videoFormat]: The capture format satisfying the current model's constraints.
  ///
  /// The returned future completes with an error if capture is inactive, the format is unsupported,
  /// or native configuration fails. Failed updates preserve the last successful track metadata.
  Future<void> updateVideoFormat(
    RealtimeVideoFormat videoFormat,
  );
}
