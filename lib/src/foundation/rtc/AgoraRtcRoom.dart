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
import 'RtcEventListener.dart';
import 'RtcMessageQueue.dart';
import 'RtcModels.dart';
import 'RtcRoom.dart';
import 'RtcStatsLogger.dart';
import 'VideoStatistics.dart';

/// 过滤离房后的回调，维护数字 UID 与用户账号的映射。
final class AgoraRtcRoom implements RtcRoom {

  /// 创建指定引擎和房间的操作入口。
  AgoraRtcRoom({
    required this.engine,
    required this.roomID,
    required this.listener,
  });

  /// 当前使用的原生 RTC 引擎。
  final RtcEngine engine;

  /// 云端分配的 RTC 房间标识。
  final String roomID;

  /// 读取当前 RTC 事件接收器的函数；返回 null 时停止向上分发事件。
  final RtcEventListener? Function() listener;

  /// 用于通知加入房间和发送队列初始化完成的完成器。
  final _joined = Completer<void>();

  /// 数字 UID 到 RTC 用户账号的映射。
  final _accounts = <int, String>{};

  /// 当前仍在房间中的远端数字 UID 集合。
  final _online = <int>{};

  /// 已经通知媒体发布的远端用户 UID 集合。
  final _announced = <int>{};

  /// 已收到首帧解码通知的远端 UID 集合。
  final _decoded = <int>{};

  /// 已收到首帧渲染通知的远端 UID 集合。
  final _rendered = <int>{};

  /// 当前是否正在创建房间 DataStream，避免重复创建。
  bool _preparingSender = false;

  /// 按数字 UID 合并的账号查询任务。
  final _pendingAccounts = <int, Future<String?>>{};

  /// 当前房间的原生 RTC 事件处理器。
  late final RtcEngineEventHandler _handler;

  /// 当前房间的有序、限速信令发送队列。
  RtcMessageQueue? _sender;

  /// 当前房间是否已关闭。
  bool _isClosed = false;

  /// 当前房间是否已关闭。
  @override
  bool get isClosed => _isClosed;

  /// 检查回调是否来自尚未关闭的当前房间。
  ///
  /// - [connection]：当前会话的 RTC 房间参数。
  ///
  /// 返回回调是否来自尚未关闭的当前房间。
  bool _isCurrent(
    RtcConnection connection,
  ) => !_isClosed && connection.channelId == roomID;

  /// 加入 RTC 房间并创建信令发送队列，不自动发布或订阅媒体。
  ///
  /// - [configuration]：本次入房使用的房间标识、用户账号和访问令牌。
  @override
  Future<void> join(
    RoomJoinConfiguration configuration,
  ) async {
    _joined.future.ignore();
    _handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, _) {
        if (!_isCurrent(connection) ||
            _joined.isCompleted ||
            _preparingSender) {
          return;
        }

        _preparingSender = true;
        unawaited(_prepareSender());
      },
      onUserJoined: (connection, uid, _) {
        if (!_isCurrent(connection)) return;

        _online.add(uid);
        unawaited(_publish(uid));
      },
      onUserInfoUpdated: (uid, info) {
        if (_isClosed) return;

        final account = info.userAccount;

        if (account != null && account.isNotEmpty) _accounts[uid] = account;

        if (_online.contains(uid)) unawaited(_publish(uid));
      },
      onUserOffline: (connection, uid, _) {
        if (!_isCurrent(connection)) return;

        final account = _accounts.remove(uid);

        _online.remove(uid);
        _announced.remove(uid);
        _decoded.remove(uid);
        _rendered.remove(uid);
        if (account != null) {
          final stream = _stream(uid, account);

          listener()?.onRemoteVideoPublished?.call(stream, false);
          listener()?.onRemoteAudioPublished?.call(stream, false);
        }
      },
      onRemoteVideoStateChanged: (connection, uid, state, reason, _) {
        if (!_isCurrent(connection)) return;

        if (reason ==
            RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
          _announced.remove(uid);
          _decoded.remove(uid);
          _rendered.remove(uid);
          unawaited(
            _withStream(
              uid,
              (stream) =>
                  listener()?.onRemoteVideoPublished?.call(stream, false),
            ),
          );
        } else if (state == RemoteVideoState.remoteVideoStateStarting ||
            state == RemoteVideoState.remoteVideoStateDecoding) {
          unawaited(_publish(uid));
        }
      },
      onFirstRemoteVideoDecoded: (connection, uid, width, height, _) {
        if (!_isCurrent(connection) || width <= 0 || height <= 0) return;

        _decoded.add(uid);
        unawaited(
          _withStream(
            uid,
            (stream) =>
                listener()?.onFirstRemoteVideoFrameDecoded?.call(stream),
          ),
        );
      },
      onFirstRemoteVideoFrame: (connection, uid, width, height, _) {
        if (!_isCurrent(connection) || width <= 0 || height <= 0) return;

        _rendered.add(uid);
        unawaited(
          _withStream(
            uid,
            (stream) =>
                listener()?.onFirstRemoteVideoFrameRendered?.call(stream),
          ),
        );
      },
      onNetworkQuality: (connection, uid, up, down) {
        if (!_isCurrent(connection) || uid != 0) return;

        final quality = RealtimeNetworkQuality(
          uplink: _quality(up),
          downlink: _quality(down),
        );

        RtcStatsLogger.logNetworkQuality(quality);
        listener()?.onNetworkQuality?.call(quality);
      },
      onLocalVideoStats: (connection, _, stats) {
        if (!_isCurrent(connection)) return;

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
      onRemoteVideoStats: (connection, stats) {
        final uid = stats.uid;

        if (!_isCurrent(connection) || uid == null) return;

        unawaited(
          _withStream(uid, (stream) {
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
          }),
        );
      },
      onConnectionStateChanged: (connection, state, reason) {
        if (_isCurrent(connection) &&
            state == ConnectionStateType.connectionStateFailed) {
          _failure(StateError('RTC connection failed: ${reason.name}'));
        }
      },
      onStreamMessageError: (connection, _, _, code, _, _) {
        if (_isCurrent(connection)) {
          _failure(StateError('RTC DataStream failed: ${code.name}'));
        }
      },
    );
    engine.registerEventHandler(_handler);

    try {
      await engine.joinChannelWithUserAccount(
        token: configuration.token,
        channelId: roomID,
        userAccount: configuration.userID,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: false,
          publishMicrophoneTrack: false,
          autoSubscribeAudio: false,
          autoSubscribeVideo: false,
        ),
      );
      await _joined.future;
    } catch (_) {
      await destroy();
      rethrow;
    }
  }

  /// 创建有序信令队列，然后通知加入房间的操作已完成。
  Future<void> _prepareSender() async {
    try {
      final id = await engine.createDataStream(
        const DataStreamConfig(ordered: true, syncWithAudio: false),
      );

      if (_isClosed) return;

      _sender = RtcMessageQueue(
        send: (packet) async {
          try {
            await engine.sendStreamMessage(
              streamId: id,
              data: packet,
              length: packet.length,
            );
          } catch (error) {
            throw error is XmaxError
                ? error
                : XmaxError(
                    code: XmaxErrorCode.rtcError,
                    message: 'RTC sendStreamMessage failed: $error',
                  );
          }
        },
        onFailure: _failure,
      );
      if (!_joined.isCompleted) _joined.complete();
    } catch (error) {
      _failure(error);
    }
  }

  /// 通知当前错误：尚未加入房间时使加入操作失败，否则触发运行错误回调。
  ///
  /// - [error]：房间或信令发送错误。
  void _failure(
    Object error,
  ) {
    if (_isClosed) return;

    final failure = error is XmaxError
        ? error
        : XmaxError(code: XmaxErrorCode.rtcError, message: '$error');

    if (!_joined.isCompleted) {
      _joined.completeError(failure);
    } else {
      listener()?.onError?.call(failure);
    }
  }

  /// 解析数字 UID 对应的用户账号，并合并同时进行的查询。
  ///
  /// - [uid]：RTC 分配的数字用户标识（UID）。
  ///
  /// 返回 RTC 用户账号；无法获取时返回 null。
  Future<String?> _account(
    int uid,
  ) async {
    if (_accounts[uid] case final account?) return account;

    if (_pendingAccounts[uid] case final pending?) return pending;

    final future = () async {
      try {
        final info = await engine.getUserInfoByUid(uid);
        final account = info.userAccount;

        if (!_isClosed &&
            _online.contains(uid) &&
            account != null &&
            account.isNotEmpty) {
          return _accounts[uid] = account;
        }
      } catch (_) {
        // 查询暂不可用时，等待用户信息更新事件提供账号映射。
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

  /// 仅在用户账号可解析且用户仍在线时执行远端流操作。
  ///
  /// - [uid]：RTC 分配的数字用户标识（UID）。
  /// - [action]：在用户映射成功且房间有效时执行的操作。
  Future<void> _withStream(
    int uid,
    void Function(
      RemoteStream,
    )
    action,
  ) async {
    final account = await _account(uid);

    if (!_isClosed && _online.contains(uid) && account != null) {
      action(_stream(uid, account));
    }
  }

  /// 通知远端用户媒体可用，并补发已到达的首帧就绪事件。
  ///
  /// - [uid]：RTC 分配的数字用户标识（UID）。
  Future<void> _publish(
    int uid,
  ) => _withStream(uid, (stream) {
    if (!_announced.add(uid)) return;

    listener()?.onRemoteVideoPublished?.call(stream, true);
    listener()?.onRemoteAudioPublished?.call(stream, true);
    if (_decoded.contains(uid)) {
      listener()?.onFirstRemoteVideoFrameDecoded?.call(stream);
    }

    if (_rendered.contains(uid)) {
      listener()?.onFirstRemoteVideoFrameRendered?.call(stream);
    }
  });

  /// 创建包含房间、用户账号、数字 UID 和引擎的远端流描述。
  ///
  /// - [uid]：RTC 分配的数字用户标识（UID）。
  /// - [account]：RTC 用户账号。
  ///
  /// 返回包含房间和用户绑定的远端流描述。
  RemoteStream _stream(
    int uid,
    String account,
  ) => RemoteStream(
    roomID: roomID,
    userID: account,
    streamID: account,
    uid: uid,
    engine: engine,
  );

  /// 解析用户账号对应的数字 UID，供订阅和音量控制使用。
  ///
  /// - [account]：RTC 用户账号。
  ///
  /// 返回账号对应的 RTC 数字 UID。
  Future<int> resolveUID(
    String account,
  ) async {
    for (final entry in _accounts.entries) {
      if (entry.value == account) return entry.key;
    }

    final info = await engine.getUserInfoByUserAccount(account);

    if (_isClosed || info.uid == null) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'RTC room has closed',
      );
    }

    return info.uid!;
  }

  /// 提交房间 JSON 信令；条件变更清理待发轨迹，自动调档失败不关闭连接。
  ///
  /// - [message]：包含 event 及对应业务字段的房间 JSON 信令。
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

  /// 关闭当前 RTC 资源，并使后续原生回调失效。
  @override
  Future<void> destroy() async {
    if (_isClosed) return;

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
    // 即使移除事件处理器失败，也要继续退出房间。
    try {
      engine.unregisterEventHandler(_handler);
    } finally {
      await engine.leaveChannel();
    }
  }

  /// 保留正数统计值。
  ///
  /// - [value]：RTC 返回的统计值；缺失或不大于 0 时返回 null。
  static int? _positive(
    int? value,
  ) => value != null && value > 0 ? value : null;

  /// 保留非负统计值，包含有效的零值。
  ///
  /// - [value]：RTC 返回的统计值；缺失或小于 0 时返回 null。
  static int? _nonnegative(
    int? value,
  ) => value != null && value >= 0 ? value : null;

  /// 保留有效的丢包率。
  ///
  /// - [value]：RTC 返回的丢包率百分比；缺失或超出 0～100 时返回 null。
  static int? _loss(
    int? value,
  ) => value != null && value >= 0 && value <= 100 ? value : null;

  /// 将 RTC 网络质量等级转换为 SDK 定义的等级。
  ///
  /// - [value]：RTC 返回的网络质量等级。
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
