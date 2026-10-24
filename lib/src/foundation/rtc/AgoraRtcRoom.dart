//
//  AgoraRtcRoom.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import 'RtcEventListener.dart';
import 'RtcMessageQueue.dart';
import 'RtcModels.dart';
import 'RtcRoom.dart';
import 'RtcStatsLogger.dart';
import 'VideoStatistics.dart';

/// Filters callbacks after leave and maps numeric UIDs to RTC user accounts.
final class AgoraRtcRoom implements RtcRoom {

  /// Creates a room adapter for an RTC engine.
  AgoraRtcRoom({
    required this.engine,
    required this.roomID,
    required this.listener,
    this.leaveTimeout = const Duration(seconds: 2),
  });

  /// The native RTC engine in use.
  final RtcEngineEx engine;

  /// The server-assigned RTC room identifier.
  final String roomID;

  /// The current RTC event listener provider; null suppresses event delivery.
  final RtcEventListener? Function() listener;

  /// The deadline for native leave and its callback; defaults to 2 seconds.
  final Duration leaveTimeout;

  /// The completer for room join and signaling queue initialization.
  final _joined = Completer<void>();

  /// The completer for the room's native leave callback.
  final _left = Completer<void>();

  /// The shared room shutdown operation used by cleanup and join rollback.
  Future<void>? _destroying;

  /// The local account used for targeted leave during or after joining.
  String? _userAccount;

  /// The confirmed connection containing the native-assigned local UID.
  RtcConnection? _connection;

  /// The room's native connection; throws if closed or the local UID is not yet confirmed.
  RtcConnection get connection {
    final current = _connection;

    if (_isClosed || current == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room connection is unavailable',
      );
    }

    return current;
  }

  /// The mapping from numeric UIDs to RTC user accounts.
  final _accounts = <int, String>{};

  /// The remote UIDs currently present in the room.
  final _online = <int>{};

  /// The remote UIDs whose media publication has been reported.
  final _announced = <int>{};

  /// The remote UIDs with a decoded first frame.
  final _decoded = <int>{};

  /// The remote UIDs with a rendered first frame.
  final _rendered = <int>{};

  /// Whether room DataStream creation is in progress.
  bool _preparingSender = false;

  /// The account lookup operations coalesced by numeric UID.
  final _pendingAccounts = <int, Future<String?>>{};

  /// The room's native RTC event handler.
  late final RtcEngineEventHandler _handler;

  /// The room's ordered, rate-limited signaling queue.
  RtcMessageQueue? _sender;

  /// Whether the room has been closed.
  bool _isClosed = false;

  /// Whether the room has been closed.
  @override
  bool get isClosed => _isClosed;

  /// Whether native join has completed and the room remains open.
  bool get isJoined => !_isClosed && _connection != null;

  /// Checks whether a callback belongs to the current open room.
  ///
  /// Parameters:
  /// - [connection]: The RTC connection parameters for this session.
  ///
  /// Returns whether the callback belongs to the current open room.
  bool _isCurrent(
    RtcConnection connection,
  ) =>
      !_isClosed &&
      connection.channelId == roomID &&
      (_connection == null ||
          connection.localUid == null ||
          connection.localUid == _connection!.localUid);

  /// Joins RTC and prepares signaling without automatically publishing or subscribing to media.
  ///
  /// Parameters:
  /// - [configuration]: The room identifier, local account, and access token for this join.
  @override
  Future<void> join(
    RoomJoinConfiguration configuration,
  ) async {
    _joined.future.ignore();
    _userAccount = configuration.userID;
    _handler = RtcEngineEventHandler(
      onLeaveChannel: (
        connection,
        _,
      ) {
        if (!_isClosed ||
            connection.channelId != roomID ||
            (_connection != null &&
                connection.localUid != null &&
                connection.localUid != _connection!.localUid) ||
            _left.isCompleted) {
          return;
        }

        _left.complete();
        XmaxLogger.debug(
          category: XmaxLoggerCategory.rtc,
          message: 'RTC 房间已退出 (RTC Room Left)',
        );
      },
      onJoinChannelSuccess: (
        connection,
        _,
      ) {
        if (!_isCurrent(connection) ||
            _joined.isCompleted ||
            _preparingSender) {
          return;
        }

        final uid = connection.localUid;

        if (uid == null || uid <= 0) {
          _failure(StateError('RTC join returned no local UID'));

          return;
        }

        _connection = RtcConnection(
          channelId: roomID,
          localUid: uid,
        );
        _preparingSender = true;
        unawaited(_prepareSender());
      },
      onUserJoined: (
        connection,
        uid,
        _,
      ) {
        if (!_isCurrent(connection)) {
          return;
        }

        _online.add(uid);
        unawaited(_publish(uid));
      },
      onUserInfoUpdated: (
        uid,
        info,
      ) {
        if (_isClosed) {
          return;
        }

        final account = info.userAccount;

        if (account != null && account.isNotEmpty) {
          _accounts[uid] = account;
        }

        if (_online.contains(uid)) {
          unawaited(_publish(uid));
        }
      },
      onUserOffline: (
        connection,
        uid,
        _,
      ) {
        if (!_isCurrent(connection)) {
          return;
        }

        final account = _accounts.remove(uid);

        _online.remove(uid);
        _announced.remove(uid);
        _decoded.remove(uid);
        _rendered.remove(uid);
        if (account != null && _connection != null) {
          final stream = _stream(
            uid,
            account,
          );

          listener()?.onRemoteVideoPublished?.call(
            stream,
            false,
          );
          listener()?.onRemoteAudioPublished?.call(
            stream,
            false,
          );
        }
      },
      onRemoteVideoStateChanged: (
        connection,
        uid,
        state,
        reason,
        _,
      ) {
        if (!_isCurrent(connection)) {
          return;
        }

        if (reason ==
            RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
          _announced.remove(uid);
          _decoded.remove(uid);
          _rendered.remove(uid);
          unawaited(
            _withStream(
              uid,
              (
                stream,
              ) =>
                  listener()?.onRemoteVideoPublished?.call(
                    stream,
                    false,
                  ),
            ),
          );
        } else if (state == RemoteVideoState.remoteVideoStateStarting ||
            state == RemoteVideoState.remoteVideoStateDecoding) {
          unawaited(_publish(uid));
        }
      },
      onFirstRemoteVideoDecoded: (
        connection,
        uid,
        width,
        height,
        _,
      ) {
        if (!_isCurrent(connection) || width <= 0 || height <= 0) {
          return;
        }

        _decoded.add(uid);
        unawaited(
          _withStream(
            uid,
            (
              stream,
            ) =>
                listener()?.onFirstRemoteVideoFrameDecoded?.call(stream),
          ),
        );
      },
      onFirstRemoteVideoFrame: (
        connection,
        uid,
        width,
        height,
        _,
      ) {
        if (!_isCurrent(connection) || width <= 0 || height <= 0) {
          return;
        }

        _rendered.add(uid);
        unawaited(
          _withStream(
            uid,
            (
              stream,
            ) =>
                listener()?.onFirstRemoteVideoFrameRendered?.call(stream),
          ),
        );
      },
      onNetworkQuality: (
        connection,
        uid,
        up,
        down,
      ) {
        if (!_isCurrent(connection) || uid != 0) {
          return;
        }

        final quality = RealtimeNetworkQuality(
          uplink: _quality(up),
          downlink: _quality(down),
        );

        RtcStatsLogger.logNetworkQuality(quality);
        listener()?.onNetworkQuality?.call(quality);
      },
      onLocalVideoStats: (
        connection,
        _,
        stats,
      ) {
        if (!_isCurrent(connection)) {
          return;
        }

        final value = UplinkVideoStatistics(
          width: _positive(stats.encodedFrameWidth),
          height: _positive(stats.encodedFrameHeight),
          captureFrameRate: _nonnegative(stats.captureFrameRate),
          encodeFrameRate: _nonnegative(stats.encoderOutputFrameRate),
          sendFrameRate: _nonnegative(stats.sentFrameRate),
          bitrateKbps: _nonnegative(stats.sentBitrate),
          packetLossPercent: _loss(stats.txPacketLossRate),
        );

        RtcStatsLogger.logUplinkVideoStatistics(value);
        listener()?.onUplinkVideoStatistics?.call(value);

        final adaptation = stats.qualityAdaptIndication;

        if (adaptation == QualityAdaptIndication.adaptDownBandwidth ||
            adaptation == QualityAdaptIndication.adaptUpBandwidth) {
          listener()?.onPerformanceAlarm?.call(
            RealtimePerformanceAlarm(
              status: adaptation == QualityAdaptIndication.adaptDownBandwidth
                  ? RealtimePerformanceStatus.limited
                  : RealtimePerformanceStatus.recovered,
              suggestedVideoFormat:
                  value.width != null &&
                      value.height != null &&
                      (value.encodeFrameRate ?? 0) > 0
                  ? RealtimeVideoFormat(
                    width: value.width!,
                    height: value.height!,
                    fps: value.encodeFrameRate!,
                  )
                  : null,
            ),
          );
        }
      },
      onRemoteVideoStats: (
        connection,
        stats,
      ) {
        final uid = stats.uid;

        if (!_isCurrent(connection) || uid == null) {
          return;
        }

        unawaited(
          _withStream(
            uid,
            (
              stream,
            ) {
            final value = DownlinkVideoStatistics(
              userID: stream.userID,
              width: _positive(stats.width),
              height: _positive(stats.height),
              decodeFrameRate: _nonnegative(stats.decoderOutputFrameRate),
              renderFrameRate: _nonnegative(stats.rendererOutputFrameRate),
              bitrateKbps: _nonnegative(stats.receivedBitrate),
              packetLossPercent: _loss(stats.packetLossRate),
              endToEndDelayMs: _nonnegative(stats.e2eDelay),
            );

            RtcStatsLogger.logDownlinkVideoStatistics(value);
            listener()?.onDownlinkVideoStatistics?.call(value);
          },
          ),
        );
      },
      onConnectionStateChanged: (
        connection,
        state,
        reason,
      ) {
        if (_isCurrent(connection) &&
            state == ConnectionStateType.connectionStateFailed) {
          _failure(StateError('RTC connection failed: ${reason.name}'));
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
        if (_isCurrent(connection)) {
          _failure(StateError('RTC DataStream failed: ${code.name}'));
        }
      },
    );
    engine.registerEventHandler(_handler);

    try {
      await engine.joinChannelWithUserAccountEx(
        token: configuration.token,
        channelId: roomID,
        userAccount: configuration.userID,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: false,
          publishCustomVideoTrack: false,
          publishMicrophoneTrack: false,
          publishCustomAudioTrack: false,
          autoSubscribeAudio: false,
          autoSubscribeVideo: false,
        ),
      );
      await _joined.future;
    } catch (_) {
      try {
        await destroy();
      } catch (error) {
        XmaxLogger.error(
          category: XmaxLoggerCategory.rtc,
          message: '释放 RTC 资源失败 (Failed to Release RTC Resources)\n└─ $error',
        );
      }

      rethrow;
    }
  }

  /// Creates the ordered signaling queue and completes room join.
  Future<void> _prepareSender() async {
    try {
      final id = await engine.createDataStreamEx(
        config: const DataStreamConfig(
          ordered: true,
          syncWithAudio: false,
        ),
        connection: connection,
      );

      if (_isClosed) {
        return;
      }

      _sender = RtcMessageQueue(
        send: (
          packet,
        ) async {
          try {
            await engine.sendStreamMessageEx(
              streamId: id,
              data: packet,
              length: packet.length,
              connection: connection,
            );
          } catch (error) {
            throw error is XmaxError
                ? error
                : XmaxError(
                  code: XmaxErrorCode.rtcError,
                  message: 'RTC sendStreamMessageEx failed: $error',
                );
          }
        },
        onFailure: _failure,
      );
      if (!_joined.isCompleted) {
        _joined.complete();
      }

      // Resolves pending remote accounts after join because publication can precede local join confirmation.
      for (final uid in _online.toList()) {
        unawaited(_publish(uid));
      }
    } catch (error) {
      _failure(error);
    }
  }

  /// Rejects an unfinished join or forwards a failure after the room is joined.
  ///
  /// Parameters:
  /// - [error]: The room or signaling failure.
  void _failure(
    Object error,
  ) {
    if (_isClosed) {
      return;
    }

    final failure = error is XmaxError
        ? error
        : XmaxError(
          code: XmaxErrorCode.rtcError,
          message: '$error',
        );

    if (!_joined.isCompleted) {
      _joined.completeError(failure);
    } else {
      listener()?.onError?.call(failure);
    }
  }

  /// Resolves an account for a numeric UID, coalescing concurrent lookups.
  ///
  /// Parameters:
  /// - [uid]: The numeric UID assigned by RTC.
  ///
  /// Returns the RTC account, or null if unavailable.
  Future<String?> _account(
    int uid,
  ) async {
    if (_accounts[uid] case final account?) {
      return account;
    }

    if (_pendingAccounts[uid] case final pending?) {
      return pending;
    }

    final future = () async {
      try {
        final info = await engine.getUserInfoByUidEx(
          uid: uid,
          connection: connection,
        );
        final account = info.userAccount;

        if (!_isClosed &&
            _online.contains(uid) &&
            account != null &&
            account.isNotEmpty) {
          return _accounts[uid] = account;
        }
      } catch (_) {
        // Waits for user information updates when account lookup is temporarily unavailable.
      }

      return null;
    }();

    _pendingAccounts[uid] = future;

    try {
      return await future;
    } finally {
      _pendingAccounts.remove(uid);
    }
  }

  /// Runs a remote stream operation only after resolving an account that remains online.
  ///
  /// Parameters:
  /// - [uid]: The numeric UID assigned by RTC.
  /// - [action]: The operation to run with a resolved user and valid room.
  Future<void> _withStream(
    int uid,
    void Function(
      RemoteStream,
    )
    action,
  ) async {
    if (_isClosed || _connection == null) {
      return;
    }

    final account = await _account(uid);

    if (!_isClosed && _online.contains(uid) && account != null) {
      action(_stream(
        uid,
        account,
      ));
    }
  }

  /// Reports remote media availability and replays any earlier first-frame events.
  ///
  /// Parameters:
  /// - [uid]: The numeric UID assigned by RTC.
  Future<void> _publish(
    int uid,
  ) => _withStream(
    uid,
    (
      stream,
    ) {
    if (!_announced.add(uid)) {
      return;
    }

    listener()?.onRemoteVideoPublished?.call(
      stream,
      true,
    );
    listener()?.onRemoteAudioPublished?.call(
      stream,
      true,
    );
    if (_decoded.contains(uid)) {
      listener()?.onFirstRemoteVideoFrameDecoded?.call(stream);
    }

    if (_rendered.contains(uid)) {
      listener()?.onFirstRemoteVideoFrameRendered?.call(stream);
    }
  },
  );

  /// Creates a remote stream binding with room, account, UID, and engine identity.
  ///
  /// Parameters:
  /// - [uid]: The numeric UID assigned by RTC.
  /// - [account]: The RTC user account.
  ///
  /// Returns the remote stream's room and user binding.
  RemoteStream _stream(
    int uid,
    String account,
  ) => RemoteStream(
    roomID: roomID,
    userID: account,
    streamID: account,
    uid: uid,
    localUid: connection.localUid,
    engine: engine,
  );

  /// Resolves an account to a numeric UID for subscription and volume control.
  ///
  /// Parameters:
  /// - [account]: The RTC user account.
  ///
  /// Returns the numeric RTC UID for the account.
  Future<int> resolveUID(
    String account,
  ) async {
    for (final entry in _accounts.entries) {
      if (entry.value == account) {
        return entry.key;
      }
    }

    final info = await engine.getUserInfoByUserAccountEx(
      userAccount: account,
      connection: connection,
    );

    if (_isClosed || info.uid == null) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'RTC room has closed',
      );
    }

    return info.uid!;
  }

  /// Submits room signaling, discarding pending trajectories on condition changes; adaptive
  /// configuration failures retain the connection.
  ///
  /// Parameters:
  /// - [message]: The room JSON message containing its event and payload.
  @override
  Future<void> sendMessage(
    String message,
  ) {
    final sender = _sender;

    if (_isClosed || sender == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room is not joined',
      );
    }

    final event = jsonDecode(message) as Map<String, dynamic>;
    final type = event['event'];

    if (type == 'stop' || type == 'start' || type == 'change_condition') {
      sender.discardPendingMessages();
    }

    return sender.enqueue(
      message,
      replacingPendingMessage: type == 'tracks'
          ? 'tracks:${event['uid']}'
          : null,
      reportFailure: type != 'change_target_size',
    );
  }

  /// Closes the room and waits for native leave without changing local camera capture.
  @override
  Future<void> destroy() {
    if (_destroying case final active?) {
      return active;
    }

    _isClosed = true;
    _sender?.close();
    if (!_joined.isCompleted) {
      _joined.completeError(
        const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'RTC join cancelled',
        ),
      );
    }

    _accounts.clear();
    _online.clear();
    _announced.clear();
    _decoded.clear();
    _rendered.clear();

    final future = _leave();

    _destroying = future;

    return future;
  }

  /// Leaves the local account's room and removes event listeners after leave confirmation or
  /// timeout.
  Future<void> _leave() async {
    try {
      // A native leave request returning does not replace the matching connection's leave callback.
      await (() async {
        final account = _userAccount;

        if (account != null) {
          await engine.leaveChannelWithUserAccountEx(
            channelId: roomID,
            userAccount: account,
          );
          await _left.future;
        }
      })().timeout(leaveTimeout);
    } finally {
      engine.unregisterEventHandler(_handler);
    }
  }

  /// Retains positive statistics values.
  ///
  /// Parameters:
  /// - [value]: The RTC statistic; missing or nonpositive values resolve to null.
  static int? _positive(
    int? value,
  ) => value != null && value > 0 ? value : null;

  /// Retains nonnegative statistics values, including valid zeros.
  ///
  /// Parameters:
  /// - [value]: The RTC statistic; missing or negative values resolve to null.
  static int? _nonnegative(
    int? value,
  ) => value != null && value >= 0 ? value : null;

  /// Retains valid packet loss percentages.
  ///
  /// Parameters:
  /// - [value]: The loss percentage; missing values or values outside 0 to 100 resolve to null.
  static int? _loss(
    int? value,
  ) => value != null && value >= 0 && value <= 100 ? value : null;

  /// Converts native RTC network quality to SDK quality.
  ///
  /// Parameters:
  /// - [value]: The native RTC network quality level.
  static RealtimeNetworkQualityLevel _quality(
    QualityType value,
  ) => switch (value) {
    QualityType.qualityExcellent => RealtimeNetworkQualityLevel.excellent,
    QualityType.qualityGood => RealtimeNetworkQualityLevel.good,
    QualityType.qualityPoor => RealtimeNetworkQualityLevel.poor,
    QualityType.qualityBad => RealtimeNetworkQualityLevel.bad,
    QualityType.qualityVbad => RealtimeNetworkQualityLevel.veryBad,
    QualityType.qualityDown => RealtimeNetworkQualityLevel.down,
    _ => RealtimeNetworkQualityLevel.unknown,
  };
}
