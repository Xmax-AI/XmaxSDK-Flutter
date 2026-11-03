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
import '../../foundation/rtc/RtcRoomEvent.dart';
import '../../foundation/tasks/OperationCancellation.dart';
import '../../foundation/runtime/RuntimeInfo.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeSessionConnection.dart';
import '../../service/realtime/RealtimeTiming.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'RoomCommandController.dart';
import 'RoomControlling.dart';
import 'RoomMessageDecoder.dart';
import 'RoomEvent.dart';
import 'RoomHeartbeat.dart';

/// Manages RTC room lifecycle, heartbeat, and generation signaling.
final class RoomController implements RoomControlling {

  /// Creates a room signaling controller.
  ///
  /// Parameters:
  /// - [rtcManager]: The RTC room signaling interface.
  /// - [heartbeat]: The heartbeat scheduler; defaults to one using the same RTC manager.
  /// - [timing]: The startup recorder shared with session creation and local publication.
  RoomController({
    required RtcManaging rtcManager,
    RoomHeartbeat? heartbeat,
    RealtimeTiming? timing,
  }) : _rtcManager = rtcManager,
       _timing = timing ?? RealtimeTiming(),
       _heartbeat = heartbeat ?? RoomHeartbeat(rtcManager: rtcManager);

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// The startup recorder measuring the native RTC join operation.
  final RealtimeTiming _timing;

  /// The heartbeat scheduler for the current RTC room.
  final RoomHeartbeat _heartbeat;

  /// The RTC user account, not a numeric UID.
  String? _userID;

  /// The identity of the current room join and its asynchronous callbacks.
  Object? _roomOperation;

  /// The command scheduler scoped to the current joined room.
  RoomCommandController? _commands;

  /// The bounded decoder for incoming service receipts.
  final RoomMessageDecoder _decoder = RoomMessageDecoder();

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

    final operation = Object();
    _roomOperation = operation;
    _joining = true;
    _heartbeat.stop();

    try {
      // RoomEvent encodes messages synchronously; cache runtime information
      // before sending generation messages or starting room heartbeats.
      await RuntimeInfo.resolve();
      ensureActive();
      _ensureRoomOperation(operation);

      _timing.beginRoomJoin();
      await _rtcManager.joinRoom(
        configuration: RoomJoinConfiguration(
          roomID: connection.roomID,
          userID: connection.userID,
          token: connection.token,
        ),
      );
      _timing.finishRoomJoin();

      ensureActive();
      _ensureRoomOperation(operation);

      _commands = RoomCommandController(
        sendMessage: (
          message,
          cancellation,
        ) => _send(
          message,
          reportFailure: false,
          cancellation: cancellation,
        ),
      );
      _rtcManager.setRoomMessageListener((
        message,
      ) {
        if (identical(_roomOperation, operation)) {
          _receive(
            message,
            connection,
          );
        }
      });
      _userID = connection.userID;
      _heartbeat.start(userID: connection.userID);
    } catch (error) {
      if (identical(_roomOperation, operation)) {
        _invalidate();
        await _rtcManager.leaveRoom();
      }
      throw XmaxError.from(error);
    } finally {
      if (identical(_roomOperation, operation)) {
        _joining = false;
      }
    }
  }

  /// Stops heartbeats, clears the local user identity, and leaves the RTC room.
  @override
  Future<void> leave() async {
    _invalidate();

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
  }) => _requireCommands().send(
    kind: RoomCommandKind.start,
    taskID: taskID,
    createMessage: (
      xid,
    ) => RoomEvent.start(
      xid: xid,
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
  }) => _requireCommands().send(
    kind: RoomCommandKind.changeCondition,
    taskID: taskID,
    createMessage: (
      xid,
    ) => RoomEvent.changeCondition(
      xid: xid,
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

    return _requireCommands().send(
      kind: RoomCommandKind.changeTargetSize,
      taskID: taskID,
      ensureCurrent: ensureActive,
      createMessage: (
        xid,
      ) => RoomEvent.changeTargetSize(
        xid: xid,
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
    cancelGenerationCommands(taskID: taskID);
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

  /// Cancels pending command attempts before asynchronous task or room cleanup.
  ///
  /// See [RoomControlling.cancelGenerationCommands] for the cancellation scope.
  @override
  void cancelGenerationCommands({
    String? taskID,
  }) {
    _commands?.cancel(taskID: taskID);
  }

  /// Invalidates message routing and every retry before leaving the native room.
  void _invalidate() {
    _roomOperation = null;
    _userID = null;
    _joining = false;
    _heartbeat.stop();
    _rtcManager.setRoomMessageListener(null);
    _decoder.reset();
    _commands?.close();
    _commands = null;
  }

  /// Rejects a join result whose [operation] no longer owns the room.
  void _ensureRoomOperation(
    Object operation,
  ) {
    if (!identical(_roomOperation, operation)) {
      throw OperationCancellation.error;
    }
  }

  /// Returns the current room's command scheduler, rejecting sends while disconnected.
  RoomCommandController _requireCommands() {
    _requireUserID();
    return _commands!;
  }

  /// Accepts receipts only from the current room's expected remote account.
  ///
  /// Parameters:
  /// - [message]: The copied signaling packet and resolved sender.
  /// - [connection]: The credentials owning this listener's room lifetime.
  void _receive(
    RtcRoomMessage message,
    RealtimeSessionConnection connection,
  ) {
    final stream = message.stream;
    final bot = connection.botName ?? '';
    if (stream.roomID != connection.roomID || stream.userID.isEmpty ||
        stream.userID == connection.userID ||
        (bot.isNotEmpty && stream.userID != bot)) {
      return;
    }

    final decoded = _decoder.decode(
      sender: stream.userID,
      data: message.data,
    );
    if (decoded == null || decoded['event'] != 'xid_ack' ||
        (decoded['user_id'] != null && decoded['user_id'] != connection.userID)) {
      return;
    }
    final xid = decoded['xid'];
    final count = decoded['count'];
    if (xid is String && count is int) {
      _commands?.acknowledge(
        xid: xid,
        count: count,
      );
    }
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
  /// - [reportFailure]: Whether a transport failure also faults the room.
  /// - [cancellation]: Cancels remaining fragments of this transport attempt.
  Future<void> _send(
    String message, {
    bool reportFailure = true,
    Future<void>? cancellation,
  }) async {
    try {
      await _rtcManager.sendRoomMessage(
        message,
        reportFailure: reportFailure,
        cancellation: cancellation,
      );
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
