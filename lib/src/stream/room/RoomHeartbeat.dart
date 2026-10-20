//
//  RoomHeartbeat.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/rtc/RtcManaging.dart';
import 'RoomEvent.dart';

/// 按固定间隔提交房间心跳，并隔离已停止的心跳周期。
final class RoomHeartbeat {

  /// 创建房间心跳调度器。
  RoomHeartbeat({
    required RtcManaging rtcManager,
    this.interval = const Duration(seconds: 10),
  }) : _rtcManager = rtcManager;

  /// RTC 采集、房间及传输操作入口。
  final RtcManaging _rtcManager;

  /// 房间心跳的固定发送间隔，默认 10 秒。
  final Duration interval;

  /// 当前房间的周期心跳计时器。
  Timer? _timer;

  /// 当前异步操作的版本号。
  int _version = 0;

  /// 替换旧心跳周期，按固定间隔为指定用户提交房间心跳。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  void start({
    required String userID,
  }) {
    stop();

    final version = ++_version;

    _timer = Timer.periodic(interval, (_) {
      if (version == _version) {
        // 房间心跳在后台定时发送，此处的传输错误不再单独上报。
        // 连接和生成操作各自通过 SDK 回调报告需要接入方处理的错误。
        unawaited(() async {
          try {
            await _rtcManager.sendRoomMessage(
              RoomEvent.heartbeat(userID: userID),
            );
          } catch (error) {
            if (version == _version) {
              XmaxLogger.error(
                category: XmaxLoggerCategory.room,
                message:
                    '发送 RTC 房间心跳失败 (Failed to Send RTC Room Heartbeat)\n'
                    '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
              );
            }
          }
        }());
      }
    });
  }

  /// 停止房间心跳，并使旧心跳回调失效。
  void stop() {
    _version += 1;
    _timer?.cancel();
    _timer = null;
  }
}
