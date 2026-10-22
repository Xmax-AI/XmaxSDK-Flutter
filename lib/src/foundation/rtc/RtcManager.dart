//
//  RtcManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import '../media/camera/CameraPosition.dart';
import 'AgoraRtcRoom.dart';
import 'RtcEngineManager.dart';
import 'RtcEventListener.dart';
import 'RtcManaging.dart';
import 'RtcModels.dart';

/// 协调共享引擎租约、摄像头预览与单次房间生命周期。
final class RtcManager implements RtcManaging {

  /// 创建 RTC 采集与房间管理器。
  ///
  /// - [engineManager]：引擎租约分配器；默认使用进程共享的独占分配器。
  RtcManager({
    RtcEngineManager? engineManager,
  }) : _engineManager = engineManager ?? RtcEngineManager.shared;

  /// 等待 RTC 加入房间和发送队列就绪的最长时限。
  static const joinTimeout = Duration(seconds: 15);

  /// 等待原生房间释放的最长时限。
  static const cleanupTimeout = Duration(seconds: 2);

  /// 分配独占 RTC 引擎租约的组件。
  final RtcEngineManager _engineManager;

  /// 需要释放的独占 RTC 引擎租约。
  RtcEngineLease? _lease;

  /// 正在进行的 RTC 引擎初始化任务。
  Future<void>? _initializing;

  /// 正在进行的 RTC 原生资源释放任务。
  Future<void>? _destroyFuture;

  /// 当前 RTC 房间实例。
  AgoraRtcRoom? _room;

  /// 正在执行的退房任务；后续入房必须等待该任务结束。
  Future<void>? _leavingRoom;

  /// 当前 RTC 房间和媒体事件监听器。
  RtcEventListener? _eventListener;

  /// 本地采集的原生 RTC 事件处理器。
  RtcEngineEventHandler? _handler;

  /// 当前本地视频首帧就绪通知。
  void Function()? _cameraPreviewReadyListener;

  /// 摄像头位置；创建流时默认使用前置摄像头。
  CameraPosition _position = CameraPosition.front;

  /// 最近一次成功应用的 RTC 编码配置。
  VideoEncodingConfiguration? _encoding;

  /// 用于原生视频渲染的当前 RTC 引擎。
  RtcEngineEx get renderEngine => _lease!.engine.engine;

  /// 当前使用的原生 RTC 引擎。
  RtcEngineEx get _engine {
    if (_lease == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC Engine is not initialized',
      );
    }

    return renderEngine;
  }

  /// 获取并初始化当前生命周期使用的 RTC 引擎。
  @override
  Future<void> initialize() async {
    await _destroyFuture;
    if (_lease != null) return;

    if (_initializing case final pending?) return pending;

    final future = _initialize();

    _initializing = future;

    try {
      await future;
    } finally {
      if (identical(_initializing, future)) _initializing = null;
    }
  }

  /// 获取独占引擎租约并注册本地媒体事件。
  Future<void> _initialize() async {
    final lease = await _engineManager.acquire();

    _lease = lease;

    try {
      final handler = RtcEngineEventHandler(
        onError: (code, message) => _eventListener?.onError?.call(
          XmaxError(
            code: XmaxErrorCode.rtcError,
            message: 'RTC ${code.name}: $message',
          ),
        ),
        onFirstLocalVideoFrame: (_, width, height, _) {
          if (width > 0 && height > 0) _cameraPreviewReadyListener?.call();
        },
        onLocalVideoStateChanged: _logLocalVideoState,
      );

      _handler = handler;
      _engine.registerEventHandler(handler);
    } catch (_) {
      _lease = null;
      await _engineManager.release(lease);
      rethrow;
    }
  }

  /// 关闭当前 RTC 资源，并使后续原生回调失效。
  @override
  Future<void> destroy() {
    if (_destroyFuture case final active?) return active;

    final future = _destroy();

    _destroyFuture = future;

    return future.whenComplete(() {
      if (identical(_destroyFuture, future)) _destroyFuture = null;
    });
  }

  /// 等待初始化结束后释放房间、事件处理器和引擎租约。
  Future<void> _destroy() async {
    try {
      await _initializing;
    } catch (_) {}

    final lease = _lease;

    _cameraPreviewReadyListener = null;

    try {
      await leaveRoom();
    } catch (error) {
      _logCleanup(error);
    } finally {
      if (lease != null) {
        try {
          if (_handler case final handler?) {
            lease.engine.engine.unregisterEventHandler(handler);
          }
        } catch (error) {
          _logCleanup(error);
        }

        try {
          await _engineManager.release(lease);
        } catch (error) {
          _logCleanup(error);
        }
      }

      _lease = null;
      _handler = null;
      _encoding = null;
      _position = CameraPosition.front;
    }
  }

  /// 将编码配置应用到当前 RTC 连接；尚未入房时配置本地预览使用的引擎。
  ///
  /// - [configuration]：视频分辨率、帧率、最低与目标码率及编码偏好。
  @override
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  ) async {
    final encoder = VideoEncoderConfiguration(
      dimensions: VideoDimensions(
        width: configuration.width,
        height: configuration.height,
      ),
      frameRate: configuration.frameRate,
      minBitrate: configuration.minimumBitrate,
      bitrate: configuration.maximumBitrate,
      orientationMode: OrientationMode.orientationModeAdaptive,
      mirrorMode: _position == CameraPosition.front
          ? VideoMirrorModeType.videoMirrorModeEnabled
          : VideoMirrorModeType.videoMirrorModeDisabled,
      degradationPreference: switch (configuration.encoderPreference) {
        RealtimeVideoEncoderPreference.maintainFramerate =>
          DegradationPreference.maintainFramerate,
        RealtimeVideoEncoderPreference.maintainQuality =>
          DegradationPreference.maintainQuality,
        _ => DegradationPreference.maintainAuto,
      },
    );
    final room = _room;
    final connection = room?.isJoined == true ? room!.connection : null;

    await _checked(
      () => connection == null
          ? _engine.setVideoEncoderConfiguration(encoder)
          : room!.engine.setVideoEncoderConfigurationEx(
              config: encoder,
              connection: connection,
            ),
    );
    _encoding = configuration;

    final scope = connection == null
        ? XmaxLogger.localized('本地预览', 'Local Preview')
        : '${connection.channelId}/${connection.localUid}';

    XmaxLogger.debug(
      category: XmaxLoggerCategory.rtc,
      message:
          '视频编码目标配置 (Video Encoder Target Configuration)\n'
          '├─ ${XmaxLogger.localized('配置范围：', 'Scope: ')}$scope\n'
          '├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}'
          '${configuration.width} × ${configuration.height}\n'
          '├─ ${XmaxLogger.localized('目标帧率：', 'Target Frame Rate: ')}'
          '${configuration.frameRate} fps\n'
          '└─ ${XmaxLogger.localized('码率范围：', 'Bitrate Range: ')}'
          '${configuration.minimumBitrate}–${configuration.maximumBitrate} kbps',
    );
  }

  /// 按给定规格启动摄像头采集和本地预览，不开启麦克风。
  ///
  /// 详细说明见 [RtcManaging.startVideoCapture]。
  @override
  Future<void> startVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) async {
    await updateVideoCapture(width: width, height: height, frameRate: frameRate);
    await _checked(() => _engine.enableLocalVideo(true));
    await _checked(() => _engine.startPreview());
  }

  /// 原地更新采集规格，不改变当前摄像头、采集生命周期或预览绑定。
  ///
  /// 详细说明见 [RtcManaging.updateVideoCapture]。
  @override
  Future<void> updateVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) async {
    await _checked(
      () => _engine.setCameraCapturerConfiguration(
        CameraCapturerConfiguration(
          cameraDirection: _position == CameraPosition.front
              ? CameraDirection.cameraFront
              : CameraDirection.cameraRear,
          followEncodeDimensionRatio: false,
          format: VideoFormat(width: width, height: height, fps: frameRate),
        ),
      ),
    );
  }

  /// 停止本地预览和摄像头采集。
  @override
  Future<void> stopVideoCapture() async {
    if (_lease == null) return;

    await _checked(() => _engine.stopPreview());
    await _checked(() => _engine.enableLocalVideo(false));
  }

  /// 将原生采集切换到指定摄像头，并重新应用当前编码镜像设置。
  ///
  /// - [position]：需要切换到的摄像头位置。
  ///
  /// 摄像头切换和编码镜像配置均完成后结束。
  @override
  Future<void> switchCamera({
    required CameraPosition position,
  }) async {
    if (_position != position) {
      await _checked(() => _engine.switchCamera());
      _position = position;
    }

    if (_encoding case final encoding?) await configureVideoEncoding(encoding);
  }

  /// 加入指定 RTC 房间，并在失败时清理本次房间资源。
  ///
  /// - [configuration]：本次入房使用的房间标识、用户账号和访问令牌。
  @override
  Future<void> joinRoom({
    required RoomJoinConfiguration configuration,
  }) async {
    await leaveRoom();

    final room = AgoraRtcRoom(
      engine: _engine,
      roomID: configuration.roomID,
      listener: () => _eventListener,
      leaveTimeout: cleanupTimeout,
    );

    _room = room;

    try {
      await _checked(() => room.join(configuration).timeout(joinTimeout));
    } catch (error) {
      try {
        await leaveRoom();
      } catch (cleanup) {
        _logCleanup(cleanup);
      }

      throw XmaxError.from(error);
    }
  }

  /// 退出当前 RTC 房间，取消待发信令并保留仍在使用的本地摄像头预览。
  @override
  Future<void> leaveRoom() {
    if (_leavingRoom case final active?) return active;

    final room = _room;

    if (room == null) return Future<void>.value();

    _room = null;

    final future = room.destroy();

    _leavingRoom = future;

    return future.whenComplete(() {
      if (identical(_leavingRoom, future)) _leavingRoom = null;
    });
  }

  /// 尚未关闭的当前 RTC 房间；不可用时抛出 RTC 错误。
  AgoraRtcRoom get _requiredRoom {
    final room = _room;

    if (room == null || room.isClosed) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room is not joined',
      );
    }

    return room;
  }

  /// 设置当前房间是否发布摄像头视频；不发布麦克风音频。
  ///
  /// - [publish]：是否发布本地摄像头视频。
  @override
  Future<void> publishLocalVideo({
    required bool publish,
  }) async {
    final room = _requiredRoom;

    await _checked(
      () => room.engine.updateChannelMediaOptionsEx(
        options: ChannelMediaOptions(
          publishCameraTrack: publish,
          publishCustomVideoTrack: false,
          publishMicrophoneTrack: false,
        ),
        connection: room.connection,
      ),
    );
    if (publish && _encoding != null) await configureVideoEncoding(_encoding!);
  }

  /// 设置是否接收指定远端用户的视频。
  ///
  /// 详细说明见 [RtcManaging.subscribeRemoteVideo]。
  @override
  Future<void> subscribeRemoteVideo({
    required String streamID,
    required bool subscribe,
  }) => _checked(() async {
    final room = _requiredRoom;
    final uid = await room.resolveUID(streamID);

    await room.engine.muteRemoteVideoStreamEx(
      uid: uid,
      mute: !subscribe,
      connection: room.connection,
    );
  });

  /// 设置是否接收指定远端用户的音频。
  ///
  /// 详细说明见 [RtcManaging.subscribeRemoteAudio]。
  @override
  Future<void> subscribeRemoteAudio({
    required String streamID,
    required bool subscribe,
  }) => _checked(() async {
    final room = _requiredRoom;
    final uid = await room.resolveUID(streamID);

    await room.engine.muteRemoteAudioStreamEx(
      uid: uid,
      mute: !subscribe,
      connection: room.connection,
    );
  });

  /// 将指定远端用户的播放音量百分比提交给 RTC。
  ///
  /// 详细说明见 [RtcManaging.setRemoteAudioVolume]。
  @override
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String streamID,
  }) => _checked(() async {
    final room = _requiredRoom;
    final uid = await room.resolveUID(streamID);

    await room.engine.adjustUserPlaybackSignalVolumeEx(
      uid: uid,
      volume: volume,
      connection: room.connection,
    );
  });

  /// 按队列顺序发送完整房间 JSON 信令，必要时进行分片和限速。
  ///
  /// - [message]：完整消息文本。
  @override
  Future<void> sendRoomMessage(
    String message,
  ) => _requiredRoom.sendMessage(message);

  /// 替换 RTC 内部事件监听器。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setEventListener(
    RtcEventListener? listener,
  ) => _eventListener = listener;

  /// 设置本地摄像头首帧就绪的内部通知。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setCameraPreviewReadyListener(
    void Function()? listener,
  ) => _cameraPreviewReadyListener = listener;

  /// 执行 RTC 调用，并将原生异常和超时转换为 SDK 错误。
  ///
  /// - [operation]：要执行的异步操作。
  static Future<void> _checked(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on AgoraRtcException catch (error) {
      throw XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC operation failed: $error',
      );
    } on TimeoutException {
      throw const XmaxError(
        code: XmaxErrorCode.timeout,
        message: 'RTC operation timed out',
      );
    }
  }

  /// 记录原生本地视频状态及原因，不更改采集或预览状态。
  ///
  /// - [source]：本次状态变化的视频源。
  /// - [state]：原生采集或编码状态。
  /// - [reason]：原生上报的状态变化原因。
  static void _logLocalVideoState(
    VideoSourceType source,
    LocalVideoStreamState state,
    LocalVideoStreamReason reason,
  ) {
    XmaxLogger.debug(
      category: XmaxLoggerCategory.rtc,
      message:
          '本地视频状态 (Local Video State)\n'
          '├─ ${XmaxLogger.localized('视频源：', 'Source: ')}${source.name}\n'
          '├─ ${XmaxLogger.localized('状态：', 'State: ')}${state.name}\n'
          '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}${reason.name}',
    );
  }

  /// 记录原生资源释放期间的错误。
  ///
  /// - [error]：本次操作的错误。
  static void _logCleanup(
    Object error,
  ) {
    try {
      XmaxLogger.error(
        category: XmaxLoggerCategory.rtc,
        message: '释放 RTC 资源失败 (Failed to Release RTC Resources)\n└─ $error',
      );
    } catch (_) {}
  }
}
