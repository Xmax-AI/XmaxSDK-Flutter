//
//  RoomController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:convert';
import 'dart:ui';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/rtc/RoomJoinConfiguration.dart';
import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/runtime/RuntimeInfo.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeSessionConnection.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'RoomControlling.dart';
import 'RoomEvent.dart';
import 'RoomHeartbeat.dart';

/// Manages RTC room lifecycle, heartbeat, and generation signaling.
final class RoomController implements RoomControlling {

  /// Creates a room signaling controller.
  ///
  /// Parameters:
  /// - [rtcManager]: The RTC room signaling interface.
  /// - [heartbeat]: The heartbeat scheduler; defaults to one using the same RTC manager.
  RoomController({
    required RtcManaging rtcManager,
    RoomHeartbeat? heartbeat,
  }) : _rtcManager = rtcManager,
       _heartbeat = heartbeat ?? RoomHeartbeat(rtcManager: rtcManager);

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// The heartbeat scheduler for the current RTC room.
  final RoomHeartbeat _heartbeat;

  /// The RTC user account, not a numeric UID.
  String? _userID;

  /// Whether an RTC room join operation is in progress.
  bool _joining = false;

  /// Joins the RTC room, saves the user identity, and starts heartbeats after success.
  ///
  /// See [RoomControlling.join] for the usage contract.
  @override
  Future<void> join({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  }) async {
    ensureActive();

    if (_userID != null || _joining) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Leave the current RTC room before joining another one',
      );
    }

    _joining = true;
    _heartbeat.stop();

    try {
      // RoomEvent encodes messages synchronously; cache runtime information
      // before sending generation messages or starting room heartbeats.
      await RuntimeInfo.resolve();
      ensureActive();

      await _rtcManager.joinRoom(
        configuration: RoomJoinConfiguration(
          roomID: connection.roomID,
          userID: connection.userID,
          token: connection.token,
        ),
      );

      ensureActive();

      _userID = connection.userID;
      _heartbeat.start(userID: connection.userID);
    } catch (error) {
      await _rtcManager.leaveRoom();
      throw XmaxError.from(error);
    } finally {
      _joining = false;
    }
  }

  /// Stops heartbeats, clears the local user identity, and leaves the RTC room.
  @override
  Future<void> leave() async {
    // Clear the saved identity before awaiting native room exit.
    _userID = null;
    _joining = false;
    _heartbeat.stop();

    await _rtcManager.leaveRoom();
  }

  /// Sends a start message to the joined room without establishing a connection or waiting for a
  /// result frame.
  ///
  /// See [RoomControlling.startGeneration] for the usage contract.
  @override
  Future<void> startGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
  }) => _send(
    RoomEvent.start(
      userID: _requireUserID(),
      taskID: taskID,
      videoFormat: videoFormat,
      context: context,
      targetSize: targetSize,
      faceRestoration: faceRestoration,
      paddingContain: paddingContain,
    ),
  );

  /// Updates task conditions; omitting the reference image clears the previous reference condition.
  ///
  /// See [RoomControlling.changeGenerationCondition] for the usage contract.
  @override
  Future<void> changeGenerationCondition({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
  }) => _send(
    RoomEvent.changeCondition(
      userID: _requireUserID(),
      taskID: taskID,
      videoFormat: videoFormat,
      context: context,
      targetSize: targetSize,
      faceRestoration: faceRestoration,
      paddingContain: paddingContain,
    ),
  );

  /// Submits result dimensions and the downlink bitrate budget for the current task.
  ///
  /// See [RoomControlling.changeTargetSize] for the usage contract.
  @override
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  }) {
    ensureActive();

    return _send(
      RoomEvent.changeTargetSize(
        userID: _requireUserID(),
        taskID: taskID,
        targetSize: targetSize,
      ),
    );
  }

  /// Sends a stop message while retaining the RTC room connection.
  ///
  /// Parameters:
  /// - [taskID]: The identifier of the generation task to stop.
  @override
  Future<void> stopGeneration({
    required String taskID,
  }) async {
    final userID = _userID;

    if (userID == null || taskID.isEmpty) {
      return;
    }

    await _send(RoomEvent.stop(
      userID: userID,
      taskID: taskID,
    ));
  }

  /// Submits normalized interaction points; sends nothing if the task identifier or point list is
  /// empty.
  ///
  /// See [RoomControlling.sendTracks] for the usage contract.
  @override
  Future<void> sendTracks({
    required String taskID,
    required List<RealtimePoint> points,
  }) async {
    if (taskID.isEmpty || points.isEmpty) {
      return;
    }

    await _send(
      RoomEvent.tracks(
        userID: _requireUserID(),
        taskID: taskID,
        points: points,
      ),
    );
  }

  /// Reads the joined room's user account; throws an RTC error if no room is joined.
  ///
  /// Returns the current room's user account; throws an RTC error if no room is joined.
  String _requireUserID() {
    final userID = _userID;

    if (userID == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room is not joined',
      );
    }

    return userID;
  }

  /// Sends a complete room message and logs its formatted representation.
  ///
  /// Parameters:
  /// - [message]: The complete room JSON message to send or format.
  Future<void> _send(
    String message,
  ) async {
    try {
      await _rtcManager.sendRoomMessage(message);
    } catch (error) {
      throw XmaxError.from(error);
    }

    XmaxLogger.debug(
      category: XmaxLoggerCategory.room,
      message: _formatSignalLog(message),
    );
  }

  /// Formats a room JSON message with a stable key order for logging.
  ///
  /// Parameters:
  /// - [message]: The complete room JSON message to send or format.
  ///
  /// Returns the room message formatted with a stable key order.
  static String _formatSignalLog(
    String message,
  ) {
    try {
      final object = jsonDecode(message);

      if (object is! Map<String, dynamic>) {
        throw const FormatException();
      }

      final eventType = object['event'] is String
          ? object['event'] as String
          : 'unknown';
      final formatted = const JsonEncoder.withIndent(
        '  ',
      ).convert(_sortJson(object));
      final indented = formatted.replaceAll(
        '\n',
        '\n   ',
      );

      return '发送房间信令 (Outbound Room Signaling)\n'
          '├─ ${XmaxLogger.localized('类型：', 'Type: ')}$eventType\n'
          '└─ ${XmaxLogger.localized('内容：', 'Content: ')}\n'
          '   $indented';
    } catch (_) {
      return '发送房间信令 (Outbound Room Signaling)\n└─ ${XmaxLogger.localized('内容：', 'Content: ')}$message';
    }
  }

  /// Recursively sorts JSON object keys, preserving array order and null values.
  ///
  /// Parameters:
  /// - [value]: The JSON value to sort.
  ///
  /// Returns the sorted JSON value.
  static Object? _sortJson(
    Object? value,
  ) {
    if (value is Map) {
      final keys = value.keys.map((
        key,
      ) => key.toString()).toList()..sort();

      return <String, Object?>{
        for (final key in keys) key: _sortJson(value[key]),
      };
    }

    if (value is List) {
      return value.map(_sortJson).toList(growable: false);
    }

    return value;
  }
}
