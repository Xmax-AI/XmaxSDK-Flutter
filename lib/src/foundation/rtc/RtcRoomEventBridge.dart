//
//  RtcRoomEventBridge.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../errors/XmaxError.dart';
import 'RtcQualityConverter.dart';
import 'RtcRoomEvent.dart';

/// Converts Agora callbacks into scoped room notifications and SDK quality events.
final class RtcRoomEventBridge {

  /// Creates a room callback bridge.
  RtcRoomEventBridge({
    required this.isCurrent,
    required this.isClosed,
    required this.onLeft,
    required this.onJoined,
    required this.onUserJoined,
    required this.onAccount,
    required this.onUserOffline,
    required this.onPublication,
    required this.onDecoded,
    required this.onRendered,
    required this.onRemoteStatistics,
    required this.onEvent,
  });

  /// Checks that a native callback belongs to the open room.
  final bool Function(
    RtcConnection connection,
  ) isCurrent;

  /// Checks whether account updates must be ignored.
  final bool Function() isClosed;

  /// Receives native leave acknowledgements, including during shutdown.
  final void Function(
    RtcConnection connection,
  ) onLeft;

  /// Receives local UID confirmation for the room join.
  final void Function(
    RtcConnection connection,
  ) onJoined;

  /// Receives a remote user join.
  final void Function(
    int uid,
  ) onUserJoined;

  /// Receives a numeric UID-to-account mapping.
  final void Function(
    int uid,
    String? account,
  ) onAccount;

  /// Receives a remote user departure.
  final void Function(
    int uid,
  ) onUserOffline;

  /// Receives remote video publication changes.
  final void Function(
    int uid,
    bool published,
  ) onPublication;

  /// Receives a valid first decoded remote frame.
  final void Function(
    int uid,
  ) onDecoded;

  /// Receives a valid first displayed native remote frame.
  final void Function(
    int uid,
  ) onRendered;

  /// Receives remote measurements for account resolution.
  final void Function(
    int uid,
    RemoteVideoStats statistics,
  ) onRemoteStatistics;

  /// Receives normalized quality, performance, and failure events.
  final void Function(
    RtcRoomEvent event,
  ) onEvent;

  /// The native event handler registered for this room lifecycle.
  late final handler = RtcEngineEventHandler(
    onLeaveChannel: (
      connection,
      _,
    ) => onLeft(connection),
    onJoinChannelSuccess: (
      connection,
      _,
    ) {
      if (isCurrent(connection)) {
        onJoined(connection);
      }
    },
    onUserJoined: (
      connection,
      uid,
      _,
    ) {
      if (isCurrent(connection)) {
        onUserJoined(uid);
      }
    },
    onUserInfoUpdated: (
      uid,
      info,
    ) {
      final account = info.userAccount;

      if (!isClosed()) {
        onAccount(
          uid,
          account,
        );
      }
    },
    onUserOffline: (
      connection,
      uid,
      _,
    ) {
      if (isCurrent(connection)) {
        onUserOffline(uid);
      }
    },
    onRemoteVideoStateChanged: (
      connection,
      uid,
      state,
      reason,
      _,
    ) {
      if (!isCurrent(connection)) {
        return;
      }

      if (reason == RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
        onPublication(
          uid,
          false,
        );
      } else if (state == RemoteVideoState.remoteVideoStateStarting ||
          state == RemoteVideoState.remoteVideoStateDecoding) {
        onPublication(
          uid,
          true,
        );
      }
    },
    onFirstRemoteVideoDecoded: (
      connection,
      uid,
      width,
      height,
      _,
    ) {
      if (isCurrent(connection) && width > 0 && height > 0) {
        onDecoded(uid);
      }
    },
    onFirstRemoteVideoFrame: (
      connection,
      uid,
      width,
      height,
      _,
    ) {
      if (isCurrent(connection) && width > 0 && height > 0) {
        onRendered(uid);
      }
    },
    onNetworkQuality: (
      connection,
      uid,
      up,
      down,
    ) {
      if (isCurrent(connection) && uid == 0) {
        onEvent(
          RtcRoomNetworkQuality(
            quality: RealtimeNetworkQuality(
              uplink: RtcQualityConverter.quality(up),
              downlink: RtcQualityConverter.quality(down),
            ),
          ),
        );
      }
    },
    onLocalVideoStats: (
      connection,
      _,
      stats,
    ) {
      if (!isCurrent(connection)) {
        return;
      }

      onEvent(
        RtcRoomUplinkVideoStatistics(
          statistics: RtcQualityConverter.uplinkVideoStatistics(stats),
        ),
      );
      final alarm = RtcQualityConverter.performanceAlarm(stats);

      if (alarm != null) {
        onEvent(RtcRoomPerformanceAlarm(alarm: alarm));
      }
    },
    onRemoteVideoStats: (
      connection,
      stats,
    ) {
      final uid = stats.uid;

      if (isCurrent(connection) && uid != null) {
        onRemoteStatistics(
          uid,
          stats,
        );
      }
    },
    onConnectionStateChanged: (
      connection,
      state,
      reason,
    ) {
      if (isCurrent(connection) &&
          state == ConnectionStateType.connectionStateFailed) {
        _failure('RTC connection failed: ${reason.name}');
      }
    },
    onStreamMessageError: (
      connection,
      _,
      _,
      code,
      _,
      _,
    ) {
      if (isCurrent(connection)) {
        _failure('RTC DataStream failed: ${code.name}');
      }
    },
  );

  /// Converts a native transport failure to the room's normalized event type.
  ///
  /// [message] identifies the native connection or signaling failure.
  void _failure(
    String message,
  ) => onEvent(
    RtcRoomFailure(
      error: XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Bad state: $message',
      ),
    ),
  );
}
