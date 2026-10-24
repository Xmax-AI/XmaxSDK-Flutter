//
//  RoomControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:ui';

import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeSessionConnection.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// An interface for room lifecycle and signaling.
abstract interface class RoomControlling {

  /// Joins the RTC room, saves the user identity, and starts heartbeats after success.
  ///
  /// Parameters:
  /// - [connection]: The RTC connection parameters for this session.
  /// - [ensureActive]: A validity check invoked before execution; must throw a cancellation error
  ///   if the operation expired.
  Future<void> join({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  });

  /// Stops heartbeats, clears the local user identity, and leaves the RTC room.
  Future<void> leave();

  /// Sends a start message to the joined room without establishing a connection or waiting for a
  /// result frame.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The server generation canvas dimensions and frame rate, not the current
  ///   uplink encoding level.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: The result dimensions in pixels. Omit to exclude target_size and use
  ///   generation canvas dimensions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  Future<void> startGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  });

  /// Updates task conditions; omitting the reference image clears the previous reference condition.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: The result dimensions in pixels. Omit to exclude target_size and use
  ///   generation canvas dimensions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  Future<void> changeGenerationCondition({
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

  /// Sends a generation stop message while retaining the RTC room connection.
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
