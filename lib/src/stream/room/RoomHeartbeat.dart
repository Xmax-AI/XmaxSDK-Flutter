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

/// Sends room heartbeats at a fixed interval, isolating stopped heartbeat cycles.
final class RoomHeartbeat {

  /// Creates a room heartbeat scheduler.
  RoomHeartbeat({
    required RtcManaging rtcManager,
    this.interval = const Duration(seconds: 10),
  }) : _rtcManager = rtcManager;

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// The fixed heartbeat interval; defaults to 10 seconds.
  final Duration interval;

  /// The periodic heartbeat timer for the current room.
  Timer? _timer;

  /// The asynchronous operation revision.
  int _version = 0;

  /// Replaces the previous heartbeat cycle and sends periodic heartbeats for the specified user.
  ///
  /// Parameters:
  /// - [userID]: The RTC user account, not a numeric UID.
  void start({
    required String userID,
  }) {
    stop();

    final version = ++_version;

    _timer = Timer.periodic(
      interval,
      (
        _,
      ) {
      if (version == _version) {
        // Heartbeats run periodically in the background; transport failures are not reported separately here.
        // Connection and generation callbacks report errors that require application handling.
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
    },
    );
  }

  /// Stops room heartbeats and invalidates callbacks from the previous cycle.
  void stop() {
    _version += 1;
    _timer?.cancel();
    _timer = null;
  }
}
