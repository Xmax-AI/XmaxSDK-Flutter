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
import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/RtcModels.dart';
import '../../foundation/runtime/RuntimeInfo.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeSession.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'RoomControlling.dart';
import 'RoomEvent.dart';
import 'RoomHeartbeat.dart';

/// 管理 RTC 房间身份、心跳和生成控制信令。
final class RoomController implements RoomControlling {

  /// 创建房间信令控制器。
  ///
  /// - [rtcManager]：房间信令发送入口。
  /// - [heartbeat]：心跳调度器；默认基于同一 RTC 管理器创建。
  RoomController({
    required RtcManaging rtcManager,
    RoomHeartbeat? heartbeat,
  }) : _rtcManager = rtcManager,
       _heartbeat = heartbeat ?? RoomHeartbeat(rtcManager: rtcManager);

  /// RTC 采集、房间及传输操作入口。
  final RtcManaging _rtcManager;

  /// 维持当前 RTC 房间的心跳组件。
  final RoomHeartbeat _heartbeat;

  /// RTC 用户账号，不是数字 UID。
  String? _userID;

  /// 是否正在执行 RTC 入房操作。
  bool _joining = false;

  /// 加入 RTC 房间，成功后保存用户身份并启动房间心跳。
  ///
  /// 详细说明见 [RoomControlling.join]。
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
      // RoomEvent 同步编码信令，因此先读取并缓存运行环境，
      // 再发送生成信令或启动房间心跳。
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

  /// 停止房间心跳、清除本地用户身份并退出 RTC 房间。
  @override
  Future<void> leave() async {
    // 等待原生房间退出前，先清除本地保存的用户身份。
    _userID = null;
    _joining = false;
    _heartbeat.stop();

    await _rtcManager.leaveRoom();
  }

  /// 向已加入的房间发送生成启动信令；不在此层建立连接或等待结果首帧。
  ///
  /// 详细说明见 [RoomControlling.startGeneration]。
  @override
  Future<void> startGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) => _send(
    RoomEvent.start(
      userID: _requireUserID(),
      taskID: taskID,
      videoFormat: videoFormat,
      context: context,
      targetSize: targetSize,
      faceRestoration: faceRestoration,
    ),
  );

  /// 向当前任务发送新条件；省略参考图字段会清除先前参考图条件。
  ///
  /// 详细说明见 [RoomControlling.changeGenerationCondition]。
  @override
  Future<void> changeGenerationCondition({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) => _send(
    RoomEvent.changeCondition(
      userID: _requireUserID(),
      taskID: taskID,
      videoFormat: videoFormat,
      context: context,
      targetSize: targetSize,
      faceRestoration: faceRestoration,
    ),
  );

  /// 提交当前生成任务的回传尺寸和下行码率预算。
  ///
  /// 详细说明见 [RoomControlling.changeTargetSize]。
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

  /// 发送停止信令，保留 RTC 房间连接。
  ///
  /// - [taskID]：要停止的生成任务标识。
  @override
  Future<void> stopGeneration({
    required String taskID,
  }) async {
    final userID = _userID;

    if (userID == null || taskID.isEmpty) {
      return;
    }

    await _send(RoomEvent.stop(userID: userID, taskID: taskID));
  }

  /// 提交当前生成任务的归一化交互轨迹；任务标识或触点列表为空时不发送。
  ///
  /// 详细说明见 [RoomControlling.sendTracks]。
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

  /// 读取已加入房间的用户账号；未加入时抛出 RTC 错误。
  ///
  /// 返回当前已加入房间的用户账号；未加入时抛出 RTC 错误。
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

  /// 发送完整房间信令并记录格式化日志。
  ///
  /// - [message]：需要发送或格式化的完整房间 JSON 信令。
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

  /// 将房间 JSON 信令按固定的键顺序格式化为日志。
  ///
  /// - [message]：需要发送或格式化的完整房间 JSON 信令。
  ///
  /// 返回按固定的键顺序格式化的房间信令日志。
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
      final indented = formatted.replaceAll('\n', '\n   ');

      return '发送房间信令 (Outbound Room Signaling)\n'
          '├─ ${XmaxLogger.localized('类型：', 'Type: ')}$eventType\n'
          '└─ ${XmaxLogger.localized('内容：', 'Content: ')}\n'
          '   $indented';
    } catch (_) {
      return '发送房间信令 (Outbound Room Signaling)\n└─ ${XmaxLogger.localized('内容：', 'Content: ')}$message';
    }
  }

  /// 递归按键排序 JSON 对象，保留数组顺序和空值。
  ///
  /// - [value]：要排序的 JSON 数据。
  ///
  /// 返回排序后的 JSON 数据。
  static Object? _sortJson(
    Object? value,
  ) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();

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
