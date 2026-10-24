//
//  XmaxRealtimeManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/media/camera/CameraPosition.dart';
import '../../foundation/rtc/VideoStatistics.dart';
import '../../service/realtime/RealtimeCameraPreset.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeState.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../stream/quality/RealtimeQualityLevel.dart';
import 'RealtimeConfiguration.dart';

/// An interface for local media, realtime connections, and video generation.
abstract interface class XmaxRealtimeManaging {

  /// The realtime configuration used by this manager.
  RealtimeConfiguration get options;

  /// The current connection and generation state.
  Future<RealtimeState> get currentState;

  /// The camera capture format, or null without a camera stream; transport adaptation does not
  /// change it.
  Future<RealtimeVideoFormat?> get currentCameraVideoFormat;

  /// The preset matching the camera dimensions, or null without a camera or matching preset.
  Future<RealtimeCameraPreset?> get currentCameraPreset;

  /// The applied uplink level, or null before connection completes or after disconnection begins.
  Future<RealtimeQualityLevel?> get uplinkQualityLevel;

  /// The submitted downlink level; the corresponding video dimensions may change later.
  /// Null before connection completes or after disconnection begins.
  Future<RealtimeQualityLevel?> get downlinkQualityLevel;

  /// Updates a ready, disconnected camera stream while preserving its track and view bindings.
  ///
  /// Provide exactly one format or preset while the preview is ready and disconnected.
  ///
  /// Parameters:
  /// - [videoFormat]: The complete capture format, with dimensions supported by the model.
  /// - [preset]: The resolution preset; preserves the current frame rate, bitrate, and encoding
  ///   preference.
  ///
  /// The returned future completes with an error if the state or format is invalid,
  /// another media operation conflicts, or configuration fails.
  Future<void> updateCameraFormat({
    RealtimeVideoFormat? videoFormat,
    RealtimeCameraPreset? preset,
  });

  /// Changes the uplink encoding level without changing capture or generation dimensions.
  ///
  /// Automatic adaptation remains active after a manual adjustment.
  ///
  /// Parameters:
  /// - [level]: The requested quality level; generation must be active.
  ///
  /// The returned future completes with an error on conflicting operations or adjustment failure.
  Future<void> setUplinkQualityLevel(
    RealtimeQualityLevel level,
  );

  /// Changes the downlink target level; returned video may reflect the submitted dimensions later.
  ///
  /// Automatic adaptation remains active after a manual adjustment.
  ///
  /// Parameters:
  /// - [level]: The requested quality level; generation must be active.
  ///
  /// The returned future completes with an error on conflicting operations or adjustment failure.
  Future<void> setDownlinkQualityLevel(
    RealtimeQualityLevel level,
  );

  /// The local media preview volume, from 0 to 1.
  /// Camera streams have no local audio player and return the default value of 0.45.
  Future<double> get localAudioVolume;

  /// The remote audio playback volume, from 0 to 1 in increments of 0.01.
  /// Initially 1.0; resets to 0 after each successful camera stream creation.
  Future<double> get remoteAudioVolume;

  /// Sets the state listener and immediately delivers the current state.
  ///
  /// Runtime failures are reported through the state's reason.
  ///
  /// Parameters:
  /// - [listener]: The state listener, or null to remove it.
  Future<void> setStateListener(
    RealtimeStateListener? listener,
  );

  /// Sets the uplink video statistics listener.
  ///
  /// Receives null when video is unpublished or disconnected so your app can clear statistics.
  ///
  /// Parameters:
  /// - [listener]: The statistics listener, or null to remove it.
  Future<void> setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  );

  /// Sets the downlink video statistics listener for the current result stream.
  ///
  /// Receives null when the result stream is cleared.
  ///
  /// Parameters:
  /// - [listener]: The statistics listener, or null to remove it.
  Future<void> setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  );

  /// Sets the network quality listener independently of automatic adaptation.
  ///
  /// Parameters:
  /// - [listener]: The network quality listener, or null to remove it.
  Future<void> setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  );

  /// Sets the device performance alarm listener.
  ///
  /// Parameters:
  /// - [listener]: The performance alarm listener, or null to remove it.
  Future<void> setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  );

  /// Sets the local media preview volume.
  ///
  /// Camera streams have no local audio player. Valid settings do not change the reported value of
  /// 0.45.
  ///
  /// Parameters:
  /// - [volume]: A finite volume from 0 to 1; out-of-range values, NaN, and infinity are invalid.
  Future<void> setLocalAudioVolume(
    double volume,
  );

  /// Sets remote audio playback volume in increments of 0.01.
  ///
  /// Retains settings before audio subscription and applies them before playback; failed RTC writes
  /// retain the last successful value.
  /// Camera stream creation resets remote volume to 0. Set the volume after creating the stream to
  /// enable playback.
  ///
  /// Parameters:
  /// - [volume]: A finite volume from 0 to 1; out-of-range values, NaN, and infinity are invalid.
  Future<void> setRemoteAudioVolume(
    double volume,
  );

  /// Creates a local camera stream and starts its preview.
  ///
  /// Omitting both [videoFormat] and [preset] uses the model's default camera format.
  /// State becomes ready after capture produces a frame and the preview is mounted.
  /// Observe state changes to wait for readiness.
  ///
  /// Parameters:
  /// - [videoFormat]: The complete capture format; cannot be combined with [preset].
  /// - [position]: The initial camera position; defaults to the front camera.
  /// - [preset]: The resolution preset, using the matching model format's frame rate and encoding
  ///   settings.
  ///
  /// Returns the local camera stream.
  ///
  /// The returned future completes with an error if configuration is invalid or permission is denied.
  Future<RealtimeMediaStream> createLocalCameraStream({
    RealtimeVideoFormat? videoFormat,
    CameraPosition position = CameraPosition.front,
    RealtimeCameraPreset? preset,
  });

  /// Stops the camera and releases capture resources. Disconnect realtime before calling.
  Future<void> stopLocalCameraStream();

  /// Switches between the front and rear cameras.
  ///
  /// During generation, stops the task, switches cameras, and resumes cached conditions and face
  /// restoration without leaving RTC.
  ///
  /// Returns the local camera stream after switching.
  Future<RealtimeMediaStream> switchCamera();

  /// Creates a server session, joins RTC, and publishes local video.
  ///
  /// Parameters:
  /// - [localStream]: The active local stream created and owned by this manager.
  ///
  /// Returns the remote stream to bind to a result view.
  Future<RealtimeMediaStream> connect({
    required RealtimeMediaStream localStream,
  });

  /// Disconnects realtime while preserving the local camera preview.
  ///
  /// Parameters:
  /// - [reason]: The disconnection reason; defaults to normal for an explicit stop.
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  });

  /// Closes realtime and releases connection and local capture resources.
  ///
  /// Repeated calls await the same cleanup. The manager can create a new local stream after cleanup
  /// completes.
  Future<void> close();

  /// Starts generation, or updates active conditions without repeating first-frame readiness.
  ///
  /// The first generation requires conditions. Startup can be replaced by a new request or
  /// interrupted by disconnection.
  ///
  /// Parameters:
  /// - [localStream]: The local stream for automatic connection; may be omitted when already
  ///   connected.
  /// - [context]: The conditions, required on the first start; null later reuses the most recently
  ///   submitted conditions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  ///
  /// Returns the connection's remote stream when [localStream] is supplied, or null otherwise.
  /// Initial startup waits for stream confirmation, frame decoding, and audio activation. Condition
  /// updates wait only for signaling.
  Future<RealtimeMediaStream?> startGeneration({
    RealtimeMediaStream? localStream,
    RealtimeContext? context,
    bool faceRestoration = false,
  });
}
