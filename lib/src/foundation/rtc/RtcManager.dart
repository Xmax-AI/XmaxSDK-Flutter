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
import 'dart:typed_data';
import '../../service/realtime/RealtimeMediaFrame.dart';
import 'RemoteStream.dart';

import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import '../media/camera/CameraPosition.dart';
import '../media/video/RealtimeExternalVideoFrame.dart';
import 'RoomJoinConfiguration.dart';
import 'LocalStream.dart';
import 'RtcEngineManager.dart';
import 'RtcEventListener.dart';
import 'RtcManaging.dart';
import 'RtcPlatform.dart';
import 'RtcQualityListener.dart';
import 'RtcRoom.dart';
import 'RtcRoomEvent.dart';
import 'VideoEncodingConfiguration.dart';

/// Coordinates a shared engine lease, camera preview, and one room lifecycle.
final class RtcManager implements RtcManaging {

  /// Configures frame output for the current engine lease only.
  ///
  /// See [RtcManaging.setRemoteMediaFrameListener] for the delivery contract.
  @override
  Future<void> setRemoteMediaFrameListener({
    required RemoteStream? stream,
    required void Function(
      RealtimeMediaFrameContent content,
    )? listener,
  }) async {
    final lease = _lease;
    if (lease == null && listener == null) {
      return;
    }
    await _platform.setRemoteMediaFrameListener(
      stream: stream,
      listener: listener,
    );
  }

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

  /// The cancellation signal for the current engine acquisition.
  Completer<void>? _initializationCancellation;

  /// The in-flight native resource release.
  Future<void>? _destroyFuture;

  /// The current RTC room.
  RtcRoom? _room;

  /// The in-flight leave operation that subsequent joins must await.
  Future<void>? _leavingRoom;

  /// The current room and media event listener.
  RtcEventListener? _eventListener;

  /// The quality and statistics receiver retained across room joins.
  RtcQualityListener? _qualityListener;

  /// The current local video first-frame readiness callback.
  void Function()? _cameraPreviewReadyListener;

  /// The platform adapter owned by the current lease.
  RtcPlatform get _platform {
    final lease = _lease;

    if (lease == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC Engine is not initialized',
      );
    }

    return lease.engine;
  }

  /// The current local input binding, independent of view creation and room publication.
  ///
  /// See [RtcManaging.localStream] for lifecycle requirements.
  @override
  LocalStream get localStream => _platform.localStream;

  /// Acquires and initializes the RTC engine for this lifecycle.
  ///
  /// Concurrent callers share initialization and its cancellation. See [RtcManaging.initialize]
  /// for cancellation and native resource ownership.
  @override
  Future<void> initialize({
    Future<void>? cancellation,
  }) {
    if (_initializing case final pending?) {
      _bindInitializationCancellation(cancellation);
      return pending;
    }

    if (_lease != null && _destroyFuture == null) {
      return Future<void>.value();
    }

    final signal = Completer<void>();

    _initializationCancellation = signal;
    _bindInitializationCancellation(cancellation);
    final future = _initialize(
      _destroyFuture,
      signal,
    );

    _initializing = future;

    return future.whenComplete(() {
      if (identical(
        _initializing,
        future,
      )) {
        _initializing = null;
        _initializationCancellation = null;
      }
    });
  }

  /// Binds an operation's cancellation without allowing stale signals to affect later owners.
  ///
  /// Parameters:
  /// - [cancellation]: The operation's cancellation signal, or null for explicit destruction only.
  void _bindInitializationCancellation(
    Future<void>? cancellation,
  ) {
    final signal = _initializationCancellation;

    if (cancellation == null || signal == null) {
      return;
    }

    // A signal from a completed initialization must not cancel a later engine owner.
    void cancel() {
      if (identical(
        _initializationCancellation,
        signal,
      ) && !signal.isCompleted) {
        signal.complete();
      }
    }

    unawaited(
      cancellation.then<void>(
        (
          _,
        ) => cancel(),
        onError: (
          Object error,
          StackTrace stackTrace,
        ) => cancel(),
      ),
    );
  }

  /// Acquires an exclusive engine lease and registers local media events.
  ///
  /// Parameters:
  /// - [release]: The preceding destruction to await without waiting on this initialization itself.
  /// - [cancellation]: The signal invalidating this initialization before lease handoff.
  Future<void> _initialize(
    Future<void>? release,
    Completer<void> cancellation,
  ) async {
    await release;
    if (cancellation.isCompleted) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'RTC initialization was cancelled',
      );
    }

    final lease = await _engineManager.acquire(cancellation: cancellation.future);

    if (cancellation.isCompleted) {
      try {
        await _engineManager.release(lease);
      } catch (error) {
        _logCleanup(error);
      }
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'RTC initialization was cancelled',
      );
    }

    _lease = lease;

    try {
      lease.engine.setEventListener(_eventListener);
      lease.engine.setCameraPreviewReadyListener(_cameraPreviewReadyListener);
    } catch (_) {
      _lease = null;
      await _engineManager.release(lease);
      rethrow;
    }
  }

  /// Releases RTC resources and invalidates subsequent native callbacks.
  @override
  Future<void> destroy() {
    final cancellation = _initializationCancellation;

    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
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
          await _engineManager.release(lease);
        } catch (error) {
          _logCleanup(error);
        }
      }

      _lease = null;
    }
  }

  /// Applies video encoding through the current platform adapter.
  ///
  /// See [RtcManaging.configureVideoEncoding] for the usage contract.
  @override
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  ) => _platform.configureVideoEncoding(configuration);

  /// Starts camera capture and preview without changing microphone capture.
  ///
  /// See [RtcManaging.startVideoCapture] for the usage contract.
  @override
  Future<void> startVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) => _platform.startVideoCapture(
    width: width,
    height: height,
    frameRate: frameRate,
  );

  /// Updates capture settings without restarting preview.
  ///
  /// See [RtcManaging.updateVideoCapture] for the usage contract.
  @override
  Future<void> updateVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) => _platform.updateVideoCapture(
    width: width,
    height: height,
    frameRate: frameRate,
  );

  /// Stops camera preview and capture if this manager owns a platform.
  @override
  Future<void> stopVideoCapture() async {
    await _lease?.engine.stopVideoCapture();
  }

  /// Starts built-in microphone capture through the current platform adapter.
  @override
  Future<void> startAudioCapture() => _platform.startAudioCapture();

  /// Stops microphone capture if this manager owns a platform.
  @override
  Future<void> stopAudioCapture() async {
    await _lease?.engine.stopAudioCapture();
  }

  /// Selects external media without starting camera or microphone capture.
  ///
  /// See [RtcManaging.startExternalVideoSource] for the usage contract.
  @override
  Future<void> startExternalVideoSource({
    required bool hasAudio,
  }) => _platform.startExternalVideoSource(hasAudio: hasAudio);

  /// Stops external preview and its opted-in audio track.
  @override
  Future<void> stopExternalVideoSource() async {
    await _lease?.engine.stopExternalVideoSource();
  }

  /// Submits owned external pixels through the current platform.
  ///
  /// See [RtcManaging.pushExternalVideoFrame] for the usage contract.
  @override
  Future<void> pushExternalVideoFrame(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  }) => _platform.pushExternalVideoFrame(
    frame,
    timestamp: timestamp,
  );

  /// Submits external PCM only while the source is published.
  ///
  /// See [RtcManaging.pushExternalAudioFrame] for the usage contract.
  @override
  Future<void> pushExternalAudioFrame(
    Uint8List data, {
    required Duration timestamp,
  }) => _platform.pushExternalAudioFrame(
    data,
    timestamp: timestamp,
  );

  /// Switches capture through the current platform without changing the local track.
  ///
  /// See [RtcManaging.switchCamera] for the usage contract.
  @override
  Future<void> switchCamera({
    required CameraPosition position,
  }) => _platform.switchCamera(position: position);

  /// Joins an RTC room and releases its resources if joining fails.
  ///
  /// Parameters:
  /// - [configuration]: The room identifier, local account, and access token for this join.
  @override
  Future<void> joinRoom({
    required RoomJoinConfiguration configuration,
  }) async {
    await leaveRoom();

    final room = _platform.createRoom(
      roomID: configuration.roomID,
      leaveTimeout: cleanupTimeout,
    );

    room.setEventListener((
      event,
    ) {
      if (identical(
        _room,
        room,
      ) && !room.isClosed) {
        _handleRoomEvent(event);
      }
    });
    _room = room;

    try {
      await room.join(configuration).timeout(joinTimeout);
    } catch (error) {
      try {
        await leaveRoom();
      } catch (cleanup) {
        _logCleanup(cleanup);
      }

      if (error is TimeoutException) {
        throw const XmaxError(
          code: XmaxErrorCode.timeout,
          message: 'RTC operation timed out',
        );
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
  RtcRoom get _requiredRoom {
    final room = _room;

    if (room == null || room.isClosed) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room is not joined',
      );
    }

    return room;
  }

  /// Publishes the currently configured local source for this room.
  ///
  /// See [RtcManaging.publishLocalVideo] for the usage contract.
  @override
  Future<void> publishLocalVideo({
    required bool publish,
  }) => _requiredRoom.publishLocalVideo(publish);

  /// Sets the remote account's video subscription.
  ///
  /// See [RtcManaging.subscribeRemoteVideo] for the usage contract.
  @override
  Future<void> subscribeRemoteVideo({
    required String streamID,
    required bool subscribe,
  }) => _requiredRoom.subscribeRemoteVideo(
    userID: streamID,
    subscribe: subscribe,
  );

  /// Sets the remote account's audio subscription.
  ///
  /// See [RtcManaging.subscribeRemoteAudio] for the usage contract.
  @override
  Future<void> subscribeRemoteAudio({
    required String streamID,
    required bool subscribe,
  }) => _requiredRoom.subscribeRemoteAudio(
    userID: streamID,
    subscribe: subscribe,
  );

  /// Applies the remote account's playback volume for this room.
  ///
  /// See [RtcManaging.setRemoteAudioVolume] for the usage contract.
  @override
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String streamID,
  }) => _requiredRoom.setRemoteAudioVolume(
    volume: volume,
    userID: streamID,
  );

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
  ) {
    _eventListener = listener;
    _lease?.engine.setEventListener(listener);
  }

  /// Replaces the independent quality and statistics receiver.
  ///
  /// Parameters:
  /// - [listener]: The quality receiver, or null to stop delivery.
  @override
  void setQualityListener(
    RtcQualityListener? listener,
  ) {
    _qualityListener = listener;
  }

  /// Sets the internal local camera first-frame callback.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setCameraPreviewReadyListener(
    void Function()? listener,
  ) {
    _cameraPreviewReadyListener = listener;
    _lease?.engine.setCameraPreviewReadyListener(listener);
  }

  /// Forwards normalized room events to independent media and quality receivers.
  ///
  /// [event] belongs to the currently active room.
  void _handleRoomEvent(
    RtcRoomEvent event,
  ) {
    switch (event) {
      case RtcRoomVideoPublication(:final stream, :final published):
        _eventListener?.onRemoteVideoPublished?.call(
          stream,
          published,
        );
      case RtcRoomAudioPublication(:final stream, :final published):
        _eventListener?.onRemoteAudioPublished?.call(
          stream,
          published,
        );
      case RtcRoomFirstVideoDecoded(:final stream):
        _eventListener?.onFirstRemoteVideoFrameDecoded?.call(stream);
      case RtcRoomFirstVideoRendered(:final stream):
        _eventListener?.onFirstRemoteVideoFrameRendered?.call(stream);
      case RtcRoomFailure(:final error):
        _eventListener?.onError?.call(error);
      case RtcRoomNetworkQuality(:final quality):
        _qualityListener?.onNetworkQuality(quality);
      case RtcRoomUplinkVideoStatistics(:final statistics):
        _qualityListener?.onUplinkVideoStatistics(statistics);
      case RtcRoomDownlinkVideoStatistics(:final statistics):
        _qualityListener?.onDownlinkVideoStatistics(statistics);
      case RtcRoomPerformanceAlarm(:final alarm):
        _qualityListener?.onPerformanceAlarm(alarm);
    }
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
