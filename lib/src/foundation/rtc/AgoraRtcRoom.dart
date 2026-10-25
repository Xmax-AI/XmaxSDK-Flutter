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

import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import 'RemoteStream.dart';
import 'RoomJoinConfiguration.dart';
import 'AgoraRtcPlatform.dart';
import 'RtcRoomEvent.dart';
import 'RtcRoomEventBridge.dart';
import 'RtcQualityConverter.dart';
import 'RtcMessageQueue.dart';
import 'RtcRoom.dart';
import 'RtcStatsLogger.dart';

/// An Agora connection adapter for users, media, and data-stream signaling.
final class AgoraRtcRoom implements RtcRoom {

  /// Creates a room adapter for an RTC engine.
  AgoraRtcRoom({
    required this.platform,
    required this.roomID,
    this.leaveTimeout = const Duration(seconds: 2),
  });

  /// The platform owning local media and the shared engine.
  final AgoraRtcPlatform platform;

  /// The native engine used only within the Agora adapter.
  RtcEngineEx get engine => platform.engine;

  /// The server-assigned RTC room identifier.
  final String roomID;

  /// The normalized room event receiver.
  void Function(
    RtcRoomEvent event,
  )? _listener;

  /// Sets room event delivery without changing native subscriptions.
  @override
  void setEventListener(
    void Function(
      RtcRoomEvent event,
    )? listener,
  ) => _listener = _isClosed ? null : listener;

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

  /// The bridge filtering and translating native connection callbacks.
  late final RtcRoomEventBridge _bridge;

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
    _bridge = RtcRoomEventBridge(
      isCurrent: _isCurrent,
      isClosed: () => _isClosed,
      onLeft: _onLeft,
      onJoined: _onJoined,
      onUserJoined: (
        uid,
      ) {
        _online.add(uid);
        unawaited(_publish(uid));
      },
      onAccount: (
        uid,
        account,
      ) {
        if (account != null && account.isNotEmpty) {
          _accounts[uid] = account;
        }

        if (_online.contains(uid)) {
          unawaited(_publish(uid));
        }
      },
      onUserOffline: _onUserOffline,
      onPublication: _onPublication,
      onDecoded: (
        uid,
      ) {
        _decoded.add(uid);
        unawaited(
          _withStream(
            uid,
            (
              stream,
            ) => _emit(RtcRoomFirstVideoDecoded(stream: stream)),
          ),
        );
      },
      onRendered: (
        uid,
      ) {
        _rendered.add(uid);
        unawaited(
          _withStream(
            uid,
            (
              stream,
            ) => _emit(RtcRoomFirstVideoRendered(stream: stream)),
          ),
        );
      },
      onRemoteStatistics: (
        uid,
        stats,
      ) {
        unawaited(
          _withStream(
            uid,
            (
              stream,
            ) => _emit(
              RtcRoomDownlinkVideoStatistics(
                statistics: RtcQualityConverter.downlinkVideoStatistics(
                  userID: stream.userID,
                  stats: stats,
                ),
              ),
            ),
          ),
        );
      },
      onEvent: (
        event,
      ) {
        if (event case RtcRoomFailure(:final error)) {
          _failure(error);
        } else {
          _emit(event);
        }
      },
    );
    engine.registerEventHandler(_bridge.handler);

    try {
      await AgoraRtcPlatform.check(
        () => engine.joinChannelWithUserAccountEx(
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

  /// Completes native leave only for this room's local connection.
  ///
  /// [connection] identifies the native leave acknowledgement.
  void _onLeft(
    RtcConnection connection,
  ) {
    if (!_isClosed || connection.channelId != roomID ||
        (_connection != null && connection.localUid != null &&
            connection.localUid != _connection!.localUid) || _left.isCompleted) {
      return;
    }

    _left.complete();
    XmaxLogger.debug(
      category: XmaxLoggerCategory.rtc,
      message: 'RTC 房间已退出 (RTC Room Left)',
    );
  }

  /// Confirms the local UID before creating the room's signaling queue.
  ///
  /// [connection] contains the native-assigned local UID.
  void _onJoined(
    RtcConnection connection,
  ) {
    if (_joined.isCompleted || _preparingSender) {
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
  }

  /// Clears a departed user's mappings and both media publications.
  ///
  /// [uid] is the departing remote UID.
  void _onUserOffline(
    int uid,
  ) {
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

      _emit(
        RtcRoomVideoPublication(
          stream: stream,
          published: false,
        ),
      );
      _emit(
        RtcRoomAudioPublication(
          stream: stream,
          published: false,
        ),
      );
    }
  }

  /// Applies remote video publication while retaining account identity until departure.
  ///
  /// Parameters:
  /// - [uid]: The remote numeric UID.
  /// - [published]: Whether video is available.
  void _onPublication(
    int uid,
    bool published,
  ) {
    if (published) {
      unawaited(_publish(uid));
      return;
    }

    _announced.remove(uid);
    _decoded.remove(uid);
    _rendered.remove(uid);
    unawaited(
      _withStream(
        uid,
        (
          stream,
        ) => _emit(
          RtcRoomVideoPublication(
            stream: stream,
            published: false,
          ),
        ),
      ),
    );
  }

  /// Delivers normalized room events only while this connection remains open.
  ///
  /// [event] contains a publication, first-frame, failure, or quality notification.
  void _emit(
    RtcRoomEvent event,
  ) {
    if (_isClosed) {
      return;
    }

    switch (event) {
      case RtcRoomNetworkQuality(:final quality):
        RtcStatsLogger.logNetworkQuality(quality);
      case RtcRoomUplinkVideoStatistics(:final statistics):
        RtcStatsLogger.logUplinkVideoStatistics(statistics);
      case RtcRoomDownlinkVideoStatistics(:final statistics):
        RtcStatsLogger.logDownlinkVideoStatistics(statistics);
      default:
        break;
    }

    _listener?.call(event);
  }

  /// Changes camera or custom publication for this connection only.
  ///
  /// [publish] controls video and the source's opted-in external audio.
  @override
  Future<void> publishLocalVideo(
    bool publish,
  ) async {
    await AgoraRtcPlatform.check(
      () => engine.updateChannelMediaOptionsEx(
        options: ChannelMediaOptions(
          publishCameraTrack: publish && !platform.usesExternalVideo,
          publishCustomVideoTrack: publish && platform.usesExternalVideo,
          customVideoTrackId: 0,
          publishMicrophoneTrack: false,
          publishCustomAudioTrack: publish && platform.externalAudioTrackID != null,
          publishCustomAudioTrackId: platform.externalAudioTrackID,
        ),
        connection: connection,
      ),
    );
    platform.isPublishingLocalMedia = publish;

    if (publish) {
      await platform.reapplyVideoConfiguration();
    }
  }

  /// Changes the video subscription for a resolved remote account.
  ///
  /// Parameters:
  /// - [userID]: The remote RTC account.
  /// - [subscribe]: Whether to receive video.
  @override
  Future<void> subscribeRemoteVideo({
    required String userID,
    required bool subscribe,
  }) => AgoraRtcPlatform.check(() async {
    final uid = await resolveUID(userID);

    await engine.muteRemoteVideoStreamEx(
      uid: uid,
      mute: !subscribe,
      connection: connection,
    );
  });

  /// Changes the audio subscription for a resolved remote account.
  ///
  /// Parameters:
  /// - [userID]: The remote RTC account.
  /// - [subscribe]: Whether to receive audio.
  @override
  Future<void> subscribeRemoteAudio({
    required String userID,
    required bool subscribe,
  }) => AgoraRtcPlatform.check(() async {
    final uid = await resolveUID(userID);

    await engine.muteRemoteAudioStreamEx(
      uid: uid,
      mute: !subscribe,
      connection: connection,
    );
  });

  /// Sets connection-scoped playback volume for a remote account.
  ///
  /// Parameters:
  /// - [volume]: The playback percentage, from 0 to 100.
  /// - [userID]: The remote RTC account.
  @override
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String userID,
  }) => AgoraRtcPlatform.check(() async {
    final uid = await resolveUID(userID);

    await engine.adjustUserPlaybackSignalVolumeEx(
      uid: uid,
      volume: volume,
      connection: connection,
    );
  });

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
      _emit(RtcRoomFailure(error: failure));
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

      _emit(
        RtcRoomVideoPublication(
          stream: stream,
          published: true,
        ),
      );
      _emit(
        RtcRoomAudioPublication(
          stream: stream,
          published: true,
        ),
      );

      if (_decoded.contains(uid)) {
        _emit(RtcRoomFirstVideoDecoded(stream: stream));
      }

      if (_rendered.contains(uid)) {
        _emit(RtcRoomFirstVideoRendered(stream: stream));
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
    _listener = null;
    platform.isPublishingLocalMedia = false;
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
      engine.unregisterEventHandler(_bridge.handler);
    }
  }
}
