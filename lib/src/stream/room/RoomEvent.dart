//
//  RoomEvent.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:convert';
import 'dart:ui';

import '../../foundation/runtime/RuntimeInfo.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../encoding/EncodingBitratePolicy.dart';
import '../../foundation/errors/XmaxError.dart';

/// Encodes room JSON messages containing user, task, and runtime information.
abstract final class RoomEvent {

  /// Encodes a start message with the generation canvas, result format, and generation conditions.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The server generation canvas dimensions and frame rate.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: The result dimensions in pixels. Omit to exclude target_size and use
  ///   generation canvas dimensions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  ///
  /// Returns JSON containing start parameters, task correlation fields, and runtime information.
  static String start({
    required String userID,
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) => _generation(
    event: 'start',
    userID: userID,
    taskID: taskID,
    videoFormat: videoFormat,
    context: context,
    targetSize: targetSize,
    faceRestoration: faceRestoration,
    includeBitrates: true,
  );

  /// Encodes a condition update including the current face restoration setting.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The server generation canvas dimensions and frame rate.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: The result dimensions in pixels. Omit to exclude target_size and use
  ///   generation canvas dimensions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  ///
  /// Returns JSON containing the prompt, optional reference image, and face restoration setting.
  static String changeCondition({
    required String userID,
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) => _generation(
    event: 'change_condition',
    userID: userID,
    taskID: taskID,
    videoFormat: videoFormat,
    context: context,
    targetSize: targetSize,
    faceRestoration: faceRestoration,
  );

  /// Encodes an update to result dimensions and the corresponding downlink bitrate budget.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  /// - [taskID]: The current generation task identifier.
  /// - [targetSize]: The result-stream width and height, in pixels.
  ///
  /// Returns JSON containing result dimensions and the downlink bitrate budget.
  static String changeTargetSize({
    required String userID,
    required String taskID,
    required Size targetSize,
  }) => _encode(<String, Object?>{
    'event': 'change_target_size',
    'params': <String, Object?>{
      'target_size': _size(targetSize),
      ..._downlinkBitrates(targetSize),
    },
    'user_id': userID,
    'uid': taskID,
  });

  /// Encodes a stop message for the specified generation task.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  /// - [taskID]: The current generation task identifier.
  ///
  /// Returns stop-event JSON containing user, task correlation, and runtime fields.
  static String stop({
    required String userID,
    required String taskID,
  }) => _encode(<String, Object?>{
    'event': 'stop',
    'user_id': userID,
    'uid': taskID,
  });

  /// Encodes normalized interaction points for the current task.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  /// - [taskID]: The current generation task identifier.
  /// - [points]: Media coordinates from 0 to 1, not view pixel coordinates.
  ///
  /// Returns interaction JSON containing the normalized point sequence.
  static String tracks({
    required String userID,
    required String taskID,
    required List<RealtimePoint> points,
  }) => _encode(<String, Object?>{
    'event': 'tracks',
    'tracks': points.map((
      point,
    ) => <double>[point.x, point.y]).toList(),
    'user_id': userID,
    'uid': taskID,
  });

  /// Encodes a room heartbeat for the current user.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  ///
  /// Returns heartbeat JSON containing the current room user and runtime information.
  static String heartbeat({
    required String userID,
  }) => _encode(<String, Object?>{'event': 'heartbeat', 'user_id': userID});

  /// Encodes start or condition messages with optional result dimensions and bitrate bounds.
  ///
  /// Parameters:
  /// - [event]: The room event to encode.
  /// - [userID]: The RTC user account, not a numeric UID.
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The server generation canvas dimensions and frame rate.
  /// - [context]: The generation conditions for this request.
  /// - [targetSize]: The result dimensions in pixels. Omit to exclude target_size and use
  ///   generation canvas dimensions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  /// - [includeBitrates]: Whether to include downlink bitrate bounds in generation messages;
  ///   omitted by default.
  ///
  /// Returns JSON containing generation conditions and optional transport parameters.
  static String _generation({
    required String event,
    required String userID,
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool includeBitrates = false,
  }) {
    final params = <String, Object?>{
      'model': 'default',
      'size': <int>[videoFormat.width, videoFormat.height],
      'prompt': context.prompt,
      'face_replace': faceRestoration,
      if (includeBitrates) 'mirror': false,
      if (includeBitrates)
        ..._downlinkBitrates(
          targetSize ??
              Size(
                videoFormat.width.toDouble(),
                videoFormat.height.toDouble(),
              ),
        ),
    };
    final referencePath = context.referencePath;

    if (targetSize != null) {
      params['target_size'] = _size(targetSize);
    }

    if (referencePath != null) {
      params['ref_image_path'] = referencePath;
    }

    // Omitting the reference image field clears the server's previous reference condition.
    return _encode(<String, Object?>{
      'event': event,
      'params': params,
      'user_id': userID,
      'uid': taskID,
    });
  }

  /// Converts pixel dimensions into an integer array ordered as width, height.
  ///
  /// Parameters:
  /// - [value]: The pixel dimensions to encode.
  ///
  /// Returns pixel dimensions as an integer array ordered as width, height.
  static List<int> _size(
    Size value,
  ) => <int>[
    value.width.toInt(),
    value.height.toInt(),
  ];

  /// Encodes room JSON with runtime information and any available task correlation identifier.
  ///
  /// Parameters:
  /// - [event]: The room event to encode.
  ///
  /// Returns JSON containing runtime and session_uid when available.
  static String _encode(
    Map<String, Object?> event,
  ) => jsonEncode(<String, Object?>{
    ...event,
    if (event['uid'] != null) 'session_uid': event['uid'],
    'runtime': RuntimeInfo.current.toJson(),
  });

  /// Calculates downlink bitrate bounds at 24 fps for the result size, capped at 10000 kbps.
  ///
  /// Parameters:
  /// - [size]: The target video width and height, in pixels.
  ///
  /// Returns min_bitrate and max_bitrate, in kbps.
  static Map<String, int> _downlinkBitrates(
    Size size,
  ) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 2 ||
        size.height < 2 ||
        size.width != size.width.truncateToDouble() ||
        size.height != size.height.truncateToDouble()) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Invalid return video dimensions',
      );
    }

    final budget = EncodingBitratePolicy.resolve(
      RealtimeVideoFormat(
        width: size.width.toInt(),
        height: size.height.toInt(),
        fps: 24,
      ),
    );

    return {'min_bitrate': 100, 'max_bitrate': budget.$2.clamp(
      100,
      10000,
    )};
  }
}
