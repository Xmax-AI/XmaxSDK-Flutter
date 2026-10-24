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
import 'RoomJoinConfiguration.dart';
import 'RtcEngineManager.dart';
import 'RtcEventListener.dart';
import 'RtcManaging.dart';
import 'VideoEncodingConfiguration.dart';

/// Coordinates a shared engine lease, camera preview, and one room lifecycle.
final class RtcManager implements RtcManaging {

  /// Creates an RTC capture and room manager.
  ///
  /// Parameters:
  /// - [engineManager]: The engine lease allocator; defaults to the process-wide allocator.
  RtcManager({
    RtcEngineManager? engineManager,
  }) : _engineManager = engineManager ?? RtcEngineManager.shared;

  /// The deadline for RTC join and signaling queue readiness.
  static const joinTimeout = Duration(seconds: 15);

  /// The deadline for native room release.
  static const cleanupTimeout = Duration(seconds: 2);

  /// The allocator for exclusive RTC engine leases.
  final RtcEngineManager _engineManager;

  /// The exclusive RTC engine lease to release.
  RtcEngineLease? _lease;

  /// The in-flight engine initialization.
  Future<void>? _initializing;

  /// The in-flight native resource release.
  Future<void>? _destroyFuture;

  /// The current RTC room.
  AgoraRtcRoom? _room;

  /// The in-flight leave operation that subsequent joins must await.
  Future<void>? _leavingRoom;

  /// The current room and media event listener.
  RtcEventListener? _eventListener;

  /// The native event handler for local capture.
  RtcEngineEventHandler? _handler;

  /// The current local video first-frame readiness callback.
  void Function()? _cameraPreviewReadyListener;

  /// The camera position, initially front-facing when a stream is created.
  CameraPosition _position = CameraPosition.front;

  /// The most recently applied RTC encoding configuration.
  VideoEncodingConfiguration? _encoding;

  /// The RTC engine used for native video rendering.
  RtcEngineEx get renderEngine => _lease!.engine.engine;

  /// The native RTC engine in use.
  RtcEngineEx get _engine {
    if (_lease == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC Engine is not initialized',
      );
    }

    return renderEngine;
  }

  /// Acquires and initializes the RTC engine for this lifecycle.
  @override
  Future<void> initialize() async {
    await _destroyFuture;
    if (_lease != null) {
      return;
    }

    if (_initializing case final pending?) {
      return pending;
    }

    final future = _initialize();

    _initializing = future;

    try {
      await future;
    } finally {
      if (identical(
        _initializing,
        future,
      )) {
        _initializing = null;
      }
    }
  }

  /// Acquires an exclusive engine lease and registers local media events.
  Future<void> _initialize() async {
    final lease = await _engineManager.acquire();

    _lease = lease;

    try {
      final handler = RtcEngineEventHandler(
        onError: (
          code,
          message,
        ) => _eventListener?.onError?.call(
          XmaxError(
            code: XmaxErrorCode.rtcError,
            message: 'RTC ${code.name}: $message',
          ),
        ),
        onFirstLocalVideoFrame: (
          _,
          width,
          height,
          _,
        ) {
          if (width > 0 && height > 0) {
            _cameraPreviewReadyListener?.call();
          }
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

  /// Releases RTC resources and invalidates subsequent native callbacks.
  @override
  Future<void> destroy() {
    if (_destroyFuture case final active?) {
      return active;
    }

    final future = _destroy();

    _destroyFuture = future;

    return future.whenComplete(() {
      if (identical(
        _destroyFuture,
        future,
      )) {
        _destroyFuture = null;
      }
    });
  }

  /// Waits for initialization before releasing the room, event handlers, and engine lease.
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

  /// Applies encoding to the current RTC connection, or to the preview engine before join.
  ///
  /// Parameters:
  /// - [configuration]: The encoding dimensions, frame rate, minimum and target bitrate, and
  ///   degradation preference.
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
        ? XmaxLogger.localized(
          '本地预览',
          'Local Preview',
        )
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

  /// Starts camera capture and preview with the specified format, leaving the microphone disabled.
  ///
  /// See [RtcManaging.startVideoCapture] for the usage contract.
  @override
  Future<void> startVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) async {
    await updateVideoCapture(
      width: width,
      height: height,
      frameRate: frameRate,
    );
    await _checked(() => _engine.enableLocalVideo(true));
    await _checked(() => _engine.startPreview());
  }

  /// Updates capture settings without changing the camera, capture lifecycle, or preview binding.
  ///
  /// See [RtcManaging.updateVideoCapture] for the usage contract.
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
          format: VideoFormat(
            width: width,
            height: height,
            fps: frameRate,
          ),
        ),
      ),
    );
  }

  /// Stops local preview and camera capture.
  @override
  Future<void> stopVideoCapture() async {
    if (_lease == null) {
      return;
    }

    await _checked(() => _engine.stopPreview());
    await _checked(() => _engine.enableLocalVideo(false));
  }

  /// Switches the native camera and reapplies the encoding mirror setting.
  ///
  /// Completes after camera switching and mirror configuration both succeed.
  ///
  /// Parameters:
  /// - [position]: The camera position to select.
  @override
  Future<void> switchCamera({
    required CameraPosition position,
  }) async {
    if (_position != position) {
      await _checked(() => _engine.switchCamera());
      _position = position;
    }

    if (_encoding case final encoding?) {
      await configureVideoEncoding(encoding);
    }
  }

  /// Joins an RTC room and releases its resources if joining fails.
  ///
  /// Parameters:
  /// - [configuration]: The room identifier, local account, and access token for this join.
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

  /// Leaves RTC and cancels pending signaling while preserving an active local camera preview.
  @override
  Future<void> leaveRoom() {
    if (_leavingRoom case final active?) {
      return active;
    }

    final room = _room;

    if (room == null) {
      return Future<void>.value();
    }

    _room = null;

    final future = room.destroy();

    _leavingRoom = future;

    return future.whenComplete(() {
      if (identical(
        _leavingRoom,
        future,
      )) {
        _leavingRoom = null;
      }
    });
  }

  /// The current open room; throws an RTC error if unavailable.
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

  /// Sets camera publication for the current room without publishing microphone audio.
  ///
  /// Parameters:
  /// - [publish]: Whether to publish local camera video.
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
    if (publish && _encoding != null) {
      await configureVideoEncoding(_encoding!);
    }
  }

  /// Sets video subscription for a remote user.
  ///
  /// See [RtcManaging.subscribeRemoteVideo] for the usage contract.
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

  /// Sets audio subscription for a remote user.
  ///
  /// See [RtcManaging.subscribeRemoteAudio] for the usage contract.
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

  /// Applies a remote user's playback volume percentage to RTC.
  ///
  /// See [RtcManaging.setRemoteAudioVolume] for the usage contract.
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

  /// Sends ordered room signaling with fragmentation and rate limiting when needed.
  ///
  /// Parameters:
  /// - [message]: The complete message text.
  @override
  Future<void> sendRoomMessage(
    String message,
  ) => _requiredRoom.sendMessage(message);

  /// Replaces the internal RTC event listener.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setEventListener(
    RtcEventListener? listener,
  ) => _eventListener = listener;

  /// Sets the internal local camera first-frame callback.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setCameraPreviewReadyListener(
    void Function()? listener,
  ) => _cameraPreviewReadyListener = listener;

  /// Runs an RTC call and normalizes native failures and timeouts as SDK errors.
  ///
  /// Parameters:
  /// - [operation]: The asynchronous operation to execute.
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

  /// Logs native local video state without changing capture or preview state.
  ///
  /// Parameters:
  /// - [source]: The video source associated with this state change.
  /// - [state]: The native capture or encoding state.
  /// - [reason]: The native reason for the state change.
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

  /// Logs native resource cleanup failures.
  ///
  /// Parameters:
  /// - [error]: The operation error.
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
