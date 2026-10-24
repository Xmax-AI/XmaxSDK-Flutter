//
//  StreamControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:ui';

import '../service/realtime/RealtimeContext.dart';
import '../service/realtime/RealtimeNetworkQuality.dart';
import '../service/realtime/RealtimePerformanceAlarm.dart';
import '../service/realtime/RealtimePoint.dart';
import '../service/realtime/RealtimeSession.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../foundation/rtc/VideoStatistics.dart';
import '../core/realtime/RealtimeQualityLevel.dart';
import 'quality/QualityConfiguration.dart';

/// A cancellable wait for a generation result stream.
///
/// After the start message is sent, [value] waits for a matching result stream from the server.
/// Calling [cancel] ends the wait without leaving RTC, allowing later tasks to reuse the
/// connection.
final class GenerationStartConfirmation {

  /// Creates a cancellable result confirmation task.
  GenerationStartConfirmation({
    required this.value,
    required void Function() onCancel,
  }) : _onCancel = onCancel;

  /// The future that completes on result confirmation, or fails on error or cancellation.
  final Future<void> value;

  /// The function invoked to cancel result confirmation.
  final void Function() _onCancel;

  /// Cancels the result-stream wait without leaving the RTC room.
  void cancel() => _onCancel();
}

/// The transport interface used by Core.
abstract interface class StreamControlling {

  /// Loads valid model history, prepares independent link policies, and applies the initial
  /// transport format.
  ///
  /// Parameters:
  /// - [baseline]: The media dimensions, frame rate, and encoding settings unaffected by quality
  ///   updates.
  /// - [model]: The model identifier used to isolate quality-level history.
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
  });

  /// The result-stream width and height, in pixels.
  Size? get targetSize;

  /// The fixed media baseline and successfully applied levels for the current connection.
  QualityConfiguration? get qualityConfiguration;

  /// Applies a manual level for one direction, excluding concurrent adaptation and condition
  /// updates.
  ///
  /// Parameters:
  /// - [level]: The requested transport quality level.
  /// - [downlink]: True to update result dimensions; false to update uplink encoding.
  Future<void> setQualityLevel(
    RealtimeQualityLevel level, {
    required bool downlink,
  });

  /// Sets the uplink statistics listener; reports null when publication stops or the room
  /// disconnects.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  );

  /// Sets the result-stream downlink statistics listener; reports null when the result is cleared.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  );

  /// Whether a generation task is starting or running.
  bool get hasGenerationTask;

  /// The remote playback volume, from 0 to 1 in increments of 0.01.
  double get remoteAudioVolume;

  /// Resolves the video bitrate budget and applies RTC encoding settings.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  Future<void> setVideoEncoderConfig(
    RealtimeVideoFormat videoFormat,
  );

  /// Sets the network quality listener without replacing the SDK's adaptation policy.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  );

  /// Sets the listener for performance limitation and recovery events.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  );

  /// Sets remote volume from 0 to 1 in increments of 0.01; retains the last applied value on
  /// failure.
  ///
  /// Parameters:
  /// - [volume]: A finite volume value between 0 and 1.
  Future<void> setRemoteAudioVolume(
    double volume,
  );

  /// Applies volume and subscribes to remote audio after result confirmation, then enables
  /// adaptation.
  Future<void> activateRemoteAudio();

  /// Joins the RTC room with existing session credentials and publishes local video.
  ///
  /// Parameters:
  /// - [connection]: The RTC connection parameters for this session.
  /// - [ensureActive]: A validity check invoked before execution; must throw a cancellation error
  ///   if the operation expired.
  Future<void> connect({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  });

  /// Ends generation and disconnects realtime while retaining the local camera preview.
  Future<void> disconnect();

  /// Sends the generation start message and returns a cancellable result-stream wait.
  ///
  /// The returned task completes only after a subscribed video stream matches the expected user.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The generation canvas dimensions and frame rate.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: The result dimensions; when omitted, no target_size field is sent and canvas
  ///   dimensions are used.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false.
  Future<GenerationStartConfirmation> beginGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  });

  /// Wait for quality updates before changing conditions so the latest result dimensions are used.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: Fallback result dimensions before quality setup; adaptive dimensions take
  ///   precedence. Omit if neither exists.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  Future<void> updateGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  });

  /// Submits result dimensions and the downlink bitrate budget for the current task.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [targetSize]: The result-stream width and height, in pixels.
  /// - [ensureActive]: A validity check invoked before execution; must throw a cancellation error
  ///   if the operation expired.
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  });

  /// Stops generation and interactions while retaining the RTC connection.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  Future<void> stopGeneration({
    required String taskID,
  });

  /// Submits normalized interaction points; sends nothing if the task identifier or point list is
  /// empty.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [points]: Media coordinates from 0 to 1, not view pixel coordinates.
  Future<void> sendTracks({
    required String taskID,
    required List<RealtimePoint> points,
  });
}
