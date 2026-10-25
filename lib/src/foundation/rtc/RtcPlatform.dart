//
//  RtcPlatform.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';
import '../../service/realtime/RealtimeMediaFrame.dart';
import 'RemoteStream.dart';

import '../media/camera/CameraPosition.dart';
import '../media/video/RealtimeExternalVideoFrame.dart';
import 'RtcEventListener.dart';
import 'LocalStream.dart';
import 'RtcRoom.dart';
import 'VideoEncodingConfiguration.dart';

/// An engine interface separate from connection waits, timeouts, and leases.
abstract interface class RtcPlatform {

  /// Configures owned remote frame output without changing media subscriptions or volume.
  ///
  /// Parameters:
  /// - [stream]: The selected result binding, or null to detach.
  /// - [listener]: The frame receiver, or null to disable observation.
  Future<void> setRemoteMediaFrameListener({
    required RemoteStream? stream,
    required void Function(
      RealtimeMediaFrameContent content,
    )? listener,
  });

  /// Applies video dimensions, frame rate, bitrate, and encoding preference to RTC.
  ///
  /// Parameters:
  /// - [configuration]: The encoding dimensions, frame rate, minimum and target bitrate, and
  ///   degradation preference.
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  );

  /// Starts camera capture and preview without changing microphone capture.
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

  /// Starts built-in microphone capture without local audio playback.
  Future<void> startAudioCapture();

  /// Stops built-in microphone capture without stopping camera preview or remote playback.
  Future<void> stopAudioCapture();

  /// Selects external video and optional custom audio without starting camera or microphone capture.
  ///
  /// [hasAudio] enables a custom audio track without local playback.
  Future<void> startExternalVideoSource({
    required bool hasAudio,
  });

  /// Stops external preview and releases its custom audio track.
  Future<void> stopExternalVideoSource();

  /// Supplies an owned external frame to preview and the active custom video publication.
  ///
  /// Parameters:
  /// - [frame]: Upright BGRA or video-range NV12 pixels, including any row padding.
  /// - [timestamp]: The monotonic presentation time.
  Future<void> pushExternalVideoFrame(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  });

  /// Uploads a 10 ms audio packet only while external media is published.
  ///
  /// Parameters:
  /// - [data]: 48 kHz mono PCM16 samples in little-endian byte order.
  /// - [timestamp]: The first sample's monotonic presentation time.
  Future<void> pushExternalAudioFrame(
    Uint8List data, {
    required Duration timestamp,
  });

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

  /// Sets engine-wide failure delivery.
  ///
  /// [listener] receives failures while the adapter remains active.
  void setEventListener(
    RtcEventListener? listener,
  );

  /// Sets local capture first-frame delivery.
  ///
  /// [listener] receives valid local frames until removed or the adapter is destroyed.
  void setCameraPreviewReadyListener(
    void Function()? listener,
  );

  /// Creates an unjoined room without changing local capture.
  ///
  /// Parameters:
  /// - [roomID]: The server-assigned RTC room identifier.
  /// - [leaveTimeout]: The deadline for native leave confirmation.
  RtcRoom createRoom({
    required String roomID,
    required Duration leaveTimeout,
  });

  /// The current native input binding, without a dependency on video views.
  LocalStream get localStream;

  /// Closes callbacks and releases native resources.
  Future<void> destroy();
}
