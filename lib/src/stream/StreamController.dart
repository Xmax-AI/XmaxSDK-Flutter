//
//  StreamController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:ui';

import '../foundation/errors/XmaxError.dart';
import '../foundation/logging/XmaxLogger.dart';
import '../foundation/rtc/RemoteStream.dart';
import '../foundation/rtc/RtcEventListener.dart';
import '../foundation/rtc/RtcManaging.dart';
import '../foundation/rtc/VideoStatistics.dart';
import '../service/realtime/RealtimeContext.dart';
import '../service/realtime/RealtimeError.dart';
import '../service/realtime/RealtimeNetworkQuality.dart';
import '../service/realtime/RealtimePerformanceAlarm.dart';
import '../service/realtime/RealtimePoint.dart';
import '../service/realtime/RealtimeSessionConnection.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import 'StreamControlling.dart';
import 'encoding/EncodingController.dart';
import 'encoding/EncodingControlling.dart';
import 'quality/QualityConfiguration.dart';
import 'quality/QualityController.dart';
import 'quality/QualityControlling.dart';
import 'quality/RealtimeQualityLevel.dart';
import 'room/RoomController.dart';
import 'room/RoomControlling.dart';

/// An internal callback for result-stream binding changes; receives null when the binding is
/// cleared.
///
/// Parameters:
/// - [stream]: The remote RTC stream to process.
typedef RemoteStreamListener =
    void Function(
      RemoteStream? stream,
    );

/// An internal callback for first-frame readiness of a result stream.
///
/// Parameters:
/// - [stream]: The remote RTC stream to process.
typedef RemoteFrameRenderedListener =
    void Function(
      RemoteStream stream,
    );

/// Coordinates RTC rooms, media streams, encoding, and quality.
final class StreamController implements StreamControlling {

  /// Creates a transport controller and registers RTC event handlers.
  ///
  /// Parameters:
  /// - [rtcManager]: The capture, room, and transport interface.
  /// - [roomController]: The signaling controller; defaults to one using the same RTC manager.
  /// - [encodingController]: The encoding controller; defaults to one using the same RTC manager.
  /// - [qualityController]: The quality controller; defaults to an independent policy instance.
  /// - [errorListener]: The callback for remote connection or generation failures.
  /// - [localMediaErrorListener]: The callback for local media failures while disconnected;
  ///   defaults to [errorListener].
  /// - [remoteStreamListener]: The callback for result-stream binding changes.
  /// - [remoteFrameRenderedListener]: The callback for the first rendered result frame.
  /// - [remoteFrameReadyListener]: The callback for the first decoded result frame.
  /// - [generationTimeout]: The timeout for generation signaling and result confirmation; defaults
  ///   to 15 seconds.
  /// - [monotonicTime]: The sample clock in seconds; defaults to the process monotonic clock.
  StreamController({
    required RtcManaging rtcManager,
    RoomControlling? roomController,
    EncodingControlling? encodingController,
    QualityControlling? qualityController,
    RealtimeErrorListener? errorListener,
    RealtimeErrorListener? localMediaErrorListener,
    RemoteStreamListener? remoteStreamListener,
    RemoteFrameRenderedListener? remoteFrameRenderedListener,
    RemoteFrameRenderedListener? remoteFrameReadyListener,
    this.generationTimeout = const Duration(seconds: 15),
    double Function()? monotonicTime,
  }) : _rtcManager = rtcManager,
       _roomController =
           roomController ?? RoomController(rtcManager: rtcManager),
       _encodingController =
           encodingController ?? EncodingController(rtcManager: rtcManager),
       _qualityController = qualityController ?? QualityController(),
       _monotonicTime = monotonicTime,
       _errorListener = errorListener,
       _localMediaErrorListener = localMediaErrorListener,
       _remoteStreamListener = remoteStreamListener,
       _remoteFrameReadyListener = remoteFrameReadyListener,
       _remoteFrameRenderedListener = remoteFrameRenderedListener {
    rtcManager.setEventListener(
      RtcEventListener(
        onRemoteVideoPublished: _onRemoteVideoPublished,
        onFirstRemoteVideoFrameRendered: _onFirstRemoteVideoFrameRendered,
        onFirstRemoteVideoFrameDecoded: _onFirstRemoteVideoFrameDecoded,
        onRemoteAudioPublished: _onRemoteAudioPublished,
        onUplinkVideoStatistics: (
          value,
        ) {
          if (_localVideoPublished) {
            _uplinkStatisticsListener?.call(value);
          }
        },
        onDownlinkVideoStatistics: (
          value,
        ) {
          if (value != null && _activeRemoteStream?.userID == value.userID) {
            _downlinkStatisticsListener?.call(value);
          }
        },
        onError: _onError,
        onNetworkQuality: _networkQualityDidChange,
        onPerformanceAlarm: _qualityController.emitPerformanceAlarm,
      ),
    );
  }

  /// The RTC capture, room, and transport interface.
  final RtcManaging _rtcManager;

  /// The controller for room identity, heartbeats, and application signaling.
  final RoomControlling _roomController;

  /// The RTC video encoding controller.
  final EncodingControlling _encodingController;

  /// The controller for uplink and downlink quality policies.
  final QualityControlling _qualityController;

  /// The monotonic clock used to timestamp network samples.
  final _qualityClock = Stopwatch()..start();

  /// An optional injected monotonic sample clock, in seconds.
  final double Function()? _monotonicTime;

  /// Reads monotonic seconds without using wall-clock time.
  double _sampleTime() => _monotonicTime?.call() ?? _qualityClock.elapsedMicroseconds / 1e6;

  /// The SDK listener for network samples, separate from your app's listener.
  void Function(
    RealtimeNetworkQuality quality,
    double sampledAt,
  )? _adaptiveQualityListener;

  /// The current connection's baseline and successfully applied quality levels.
  @override
  QualityConfiguration? get qualityConfiguration =>
      _qualityController.qualityConfiguration;

  /// Prepares directional policies without configuring capture or returned dimensions.
  ///
  /// See [StreamControlling.prepareQuality] for the usage contract.
  @override
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
    int minimumInputPixels = 0,
    bool isAdaptiveQualityEnabled = true,
  }) => _qualityController.prepareQuality(
    baseline: baseline,
    model: model,
    minimumInputPixels: minimumInputPixels,
    isAdaptiveQualityEnabled: isAdaptiveQualityEnabled,
  );

  /// Sets the internal adaptation listener without replacing your app's listener.
  ///
  /// Parameters:
  /// - [listener]: The SDK sample handler, or null to disable adaptation.
  @override
  void setAdaptiveQualityListener(
    void Function(
      RealtimeNetworkQuality quality,
      double sampledAt,
    )? listener,
  ) {
    _adaptiveQualityListener = listener;
  }

  /// Proposes directional levels without committing a transport update.
  ///
  /// Parameters:
  /// - [quality]: The current directional network measurements.
  /// - [sampledAt]: The sample's monotonic timestamp, in seconds.
  ///
  /// Returns independent candidates; null leaves that direction unchanged.
  @override
  QualityChange proposeQuality(
    RealtimeNetworkQuality quality,
    double sampledAt,
  ) => _qualityController.proposeQuality(
    quality,
    sampledAt,
  );

  /// Records a successfully applied level or a failed adjustment.
  ///
  /// Parameters:
  /// - [level]: The attempted level.
  /// - [downlink]: Whether this is the result-stream direction.
  /// - [success]: Whether configuration completed successfully.
  @override
  Future<void> completeQuality(
    RealtimeQualityLevel level, {
    required bool downlink,
    required bool success,
  }) => _qualityController.completeQuality(
    level,
    downlink: downlink,
    success: success,
    now: _sampleTime(),
  );

  /// Discards consecutive samples collected while adaptation was unavailable.
  @override
  void resetQualitySamples() => _qualityController.resetQualitySamples();

  /// Delivers public measurements and forwards samples for SDK operation admission.
  ///
  /// Parameters:
  /// - [quality]: The directional measurements from the same network sample.
  void _networkQualityDidChange(
    RealtimeNetworkQuality quality,
  ) {
    _qualityController.emitNetworkQuality(quality);
    _adaptiveQualityListener?.call(
      quality,
      _sampleTime(),
    );
  }

  /// The listener for remote connection and generation runtime errors.
  final RealtimeErrorListener? _errorListener;

  /// The callback for local media failures before a remote connection exists.
  final RealtimeErrorListener? _localMediaErrorListener;

  /// The callback for result-stream changes.
  final RemoteStreamListener? _remoteStreamListener;

  /// The callback for the first rendered result frame.
  final RemoteFrameRenderedListener? _remoteFrameRenderedListener;

  /// The callback for the first decoded result frame.
  final RemoteFrameRenderedListener? _remoteFrameReadyListener;

  /// The total timeout for start signaling and result-stream confirmation.
  final Duration generationTimeout;

  /// The server-assigned RTC room identifier.
  String _roomID = '';

  /// The revision used to reject failures from previous connections.
  int _connectionRevision = 0;

  /// The RTC user account expected to publish the result stream.
  String _botName = '';

  /// Whether local camera video has been published in the current room.
  bool _localVideoPublished = false;

  /// The identifiers of successfully subscribed result video streams.
  final Set<String> _remoteVideoSubscriptions = <String>{};

  /// First-frame rendering records keyed by room, account, and stream identifier.
  final Set<(String, String, String)> _renderedRemoteStreams = {};

  /// First-frame decoding records keyed by room, account, and stream identifier.
  final Set<(String, String, String)> _decodedRemoteStreams = {};

  /// The published audio streams belonging to the expected result user.
  final Map<String, String> _publishedRemoteAudioStreams = <String, String>{};

  /// The confirmed remote result stream for the current task.
  RemoteStream? _activeRemoteStream;

  /// The identifier of the currently subscribed remote audio stream.
  String? _subscribedRemoteAudioStreamID;

  /// The remote audio activation currently in progress.
  Future<void>? _audioActivation;

  /// Whether audio playback is enabled for the current result stream.
  bool _remoteAudioEnabled = false;

  /// The most recently applied remote audio volume, as a percentage.
  int _remoteAudioVolumePercentage = 100;

  /// The remote audio subscription version used to discard stale results.
  int _audioSubscriptionVersion = 0;

  /// The identifier of the task that is starting or generating.
  String? _generationTaskID;

  /// The completer for result-stream confirmation or failure.
  Completer<void>? _generationCompleter;

  /// The timeout timer for current result confirmation.
  Timer? _generationTimer;

  /// Whether the current task's start message has been sent successfully.
  bool _startSignalSent = false;

  /// The published video streams belonging to the expected result user.
  final _publishedVideoStreams = <String, RemoteStream>{};

  /// The identifiers of result video streams with subscriptions in progress.
  final _subscribingVideo = <String>{};

  /// The uplink statistics listener used while local video is published.
  UplinkVideoStatisticsListener? _uplinkStatisticsListener;

  /// The downlink video statistics listener for the current result stream.
  DownlinkVideoStatisticsListener? _downlinkStatisticsListener;

  /// Sets the uplink statistics listener; reports null when publication stops or the room
  /// disconnects.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  ) => _uplinkStatisticsListener = listener;

  /// Sets the result-stream downlink statistics listener; reports null when the result is cleared.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  ) => _downlinkStatisticsListener = listener;

  /// Whether a generation task is starting or running.
  @override
  bool get hasGenerationTask => _generationTaskID != null;

  /// The remote playback volume, from 0 to 1 in increments of 0.01.
  @override
  double get remoteAudioVolume => _remoteAudioVolumePercentage / 100;

  /// Resolves the video bitrate budget and applies RTC encoding settings.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  @override
  Future<void> setVideoEncoderConfig(
    RealtimeVideoFormat videoFormat,
  ) => _encodingController.configure(videoFormat);

  /// Sets the network quality listener without replacing the SDK's adaptation policy.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  ) {
    _qualityController.setNetworkQualityListener(listener);
  }

  /// Sets the listener for performance limitation and recovery events.
  ///
  /// Parameters:
  /// - [listener]: The event listener, or null to remove it.
  @override
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  ) {
    _qualityController.setPerformanceAlarmListener(listener);
  }

  /// Sets remote volume from 0 to 1 in increments of 0.01; retains the last applied value on
  /// failure.
  ///
  /// Parameters:
  /// - [volume]: A finite volume value between 0 and 1.
  @override
  Future<void> setRemoteAudioVolume(
    double volume,
  ) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Audio volume must be between 0 and 1',
      );
    }

    final rtcVolume = (volume * 100).round();
    final streamID = _subscribedRemoteAudioStreamID;

    if (streamID != null) {
      await _rtcManager.setRemoteAudioVolume(
        volume: rtcVolume,
        streamID: streamID,
      );
    }

    _remoteAudioVolumePercentage = rtcVolume;
  }

  /// Applies volume and subscribes to remote audio after result confirmation, then enables
  /// adaptation.
  @override
  Future<void> activateRemoteAudio() async {
    final stream = _activeRemoteStream;

    if (_generationTaskID == null || stream == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Remote generation audio stream is unavailable',
      );
    }

    _remoteAudioEnabled = true;
    // Audio may be published after video; subscribe when its publication event arrives.
    final streamID = _publishedRemoteAudioStreams[stream.userID];

    if (streamID == null) {
      return;
    }

    if (_subscribedRemoteAudioStreamID == streamID) {
      return;
    }

    final activeOperation = _audioActivation;

    if (activeOperation != null) {
      return activeOperation;
    }

    final operation = _performActivateRemoteAudio(
      stream,
      streamID,
    );

    _audioActivation = operation;

    try {
      await operation;
    } finally {
      if (identical(
        _audioActivation,
        operation,
      )) {
        _audioActivation = null;
      }
    }
  }

  /// Subscribes using the current result stream and volume, cancelling stale subscriptions.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  /// - [streamID]: The identifier of the media stream to publish, subscribe to, or control.
  Future<void> _performActivateRemoteAudio(
    RemoteStream stream,
    String streamID,
  ) async {
    final version = _audioSubscriptionVersion;
    final initialVolume = _remoteAudioVolumePercentage;

    await _rtcManager.setRemoteAudioVolume(
      volume: initialVolume,
      streamID: streamID,
    );
    _ensureAudioStreamCurrent(
      stream,
      streamID,
      version,
    );

    await _rtcManager.subscribeRemoteAudio(
      streamID: streamID,
      subscribe: true,
    );
    if (!_isAudioStreamCurrent(
      stream,
      streamID,
      version,
    )) {
      await _safe(
        '取消过期 RTC 远端音频订阅失败 '
        '(Failed to Unsubscribe from Stale RTC Remote Audio)',
        () => _rtcManager.subscribeRemoteAudio(
          streamID: streamID,
          subscribe: false,
        ),
      );
      _ensureAudioStreamCurrent(
        stream,
        streamID,
        version,
      );
    }

    _subscribedRemoteAudioStreamID = streamID;
    if (initialVolume != _remoteAudioVolumePercentage) {
      await _rtcManager.setRemoteAudioVolume(
        volume: _remoteAudioVolumePercentage,
        streamID: streamID,
      );
    }
  }

  /// Joins the RTC room with existing session credentials and publishes local video.
  ///
  /// See [StreamControlling.connect] for the usage contract.
  @override
  Future<void> connect({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  }) async {
    // Existing remote publication events may arrive before room joining completes.
    _connectionRevision += 1;
    _renderedRemoteStreams.clear();
    _decodedRemoteStreams.clear();
    _roomID = connection.roomID.trim();
    _publishedVideoStreams.clear();
    _subscribingVideo.clear();
    _botName = connection.botName?.trim() ?? '';

    try {
      await _roomController.join(
        connection: connection,
        ensureActive: ensureActive,
      );

      ensureActive();
      await _rtcManager.publishLocalVideo(publish: true);
      _localVideoPublished = true;
      _uplinkStatisticsListener?.call(null);
    } catch (_) {
      _roomID = '';
      _botName = '';
      _publishedRemoteAudioStreams.clear();
      _renderedRemoteStreams.clear();
      _decodedRemoteStreams.clear();
      rethrow;
    }
  }

  /// Ends generation and disconnects realtime while retaining the local camera preview.
  @override
  Future<void> disconnect() async {
    _adaptiveQualityListener = null;
    _qualityController.resetQuality();
    _connectionRevision += 1;
    // Cancel result-stream waits before changing RTC subscriptions.
    await _clearGeneration(notifyRemote: true);

    for (final streamID in _remoteVideoSubscriptions.toList()) {
      await _safe(
        '取消订阅 RTC 远端视频失败 (Failed to Unsubscribe from RTC Remote Video)',
        () => _rtcManager.subscribeRemoteVideo(
          streamID: streamID,
          subscribe: false,
        ),
      );
    }

    if (_localVideoPublished) {
      await _safe(
        '取消发布 RTC 本地视频失败 (Failed to Unpublish RTC Local Video)',
        () => _rtcManager.publishLocalVideo(publish: false),
      );
    }

    _remoteVideoSubscriptions.clear();
    _renderedRemoteStreams.clear();
    _decodedRemoteStreams.clear();
    _publishedRemoteAudioStreams.clear();
    _localVideoPublished = false;
    _uplinkStatisticsListener?.call(null);
    _downlinkStatisticsListener?.call(null);
    _publishedVideoStreams.clear();
    _subscribingVideo.clear();
    _roomID = '';
    _botName = '';

    await _roomController.leave();
  }

  /// Sends the generation start message and returns a cancellable result-stream wait.
  ///
  /// See [StreamControlling.beginGeneration] for the usage contract.
  @override
  Future<GenerationStartConfirmation> beginGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
    Future<void>? cancellation,
  }) async {
    if (taskID.trim().isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Realtime generation task ID cannot be empty',
      );
    }

    if (_roomID.isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room is not configured',
      );
    }

    if (_generationTaskID != null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Realtime generation is already active',
      );
    }

    // Select a matching result stream only after submitting the start message.
    final completer = Completer<void>();
    // Cancellation may arrive immediately after the start message is sent;
    // attach error handling before returning the result-stream wait to the caller.
    completer.future.ignore();
    _generationTaskID = taskID;
    _generationCompleter = completer;
    _startSignalSent = false;
    cancellation?.then((
      _,
    ) {
      if (_generationTaskID == taskID && identical(
        _generationCompleter,
        completer,
      )) {
        _rejectGeneration(
          const XmaxError(
            code: XmaxErrorCode.cancelled,
            message: 'Realtime generation start cancelled',
          ),
        );
      }
    });
    _generationTimer = Timer(
      generationTimeout,
      () {
      // Log generation startup and result confirmation without prompts or credentials.
      XmaxLogger.warn(
        category: XmaxLoggerCategory.stream,
        message:
            '生成确认超时 (Generation Confirmation Timed Out)\n'
            '├─ ${XmaxLogger.localized('taskID：', 'taskID: ')}$taskID\n'
            '├─ ${XmaxLogger.localized('视频订阅数：', 'Video Subscriptions: ')}${_remoteVideoSubscriptions.length}\n'
            '└─ ${XmaxLogger.localized('目标视频已发布：', 'Expected Video Published: ')}${_publishedVideoStreams.isNotEmpty}',
      );
      _rejectGeneration(
        const XmaxError(
          code: XmaxErrorCode.timeout,
          message: 'Realtime generation start timed out',
        ),
      );
    },
    );

    try {
      // Signaling delays and result publication share a single timeout.
      // Cancellation must also end tasks still waiting for RTC message delivery.
      await Future.any<void>([
        _roomController.startGeneration(
          taskID: taskID,
          videoFormat: videoFormat,
          context: context,
          targetSize: targetSize,
          faceRestoration: faceRestoration,
          paddingContain: paddingContain,
        ),
        completer.future,
      ]);
      if (_generationTaskID == taskID &&
          identical(
            _generationCompleter,
            completer,
          )) {
        _startSignalSent = true;
        _confirmPublishedRemoteStream();
      }

      return GenerationStartConfirmation(
        value: completer.future,
        onCancel: () {
          if (_generationTaskID == taskID &&
              identical(
                _generationCompleter,
                completer,
              )) {
            _rejectGeneration(
              const XmaxError(
                code: XmaxErrorCode.cancelled,
                message: 'Realtime generation start cancelled',
              ),
            );
          }
        },
      );
    } catch (error) {
      // Remove the completer before returning the failure to the caller
      // to avoid an unhandled cancellation error during cleanup.
      if (identical(
        _generationCompleter,
        completer,
      )) {
        _generationTimer?.cancel();
        _generationTimer = null;
        _generationCompleter = null;
      }

      // Stop the server task because the generation request may already have arrived.
      await _safe(
        '停止取消的生成失败 (Failed to Stop Cancelled Generation)',
        () => stopGeneration(taskID: taskID),
      );
      rethrow;
    }
  }

  /// Submits conditions within the caller's admitted configuration operation.
  ///
  /// See [StreamControlling.updateGeneration] for the usage contract.
  @override
  Future<void> updateGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
  }) => _roomController.changeGenerationCondition(
    taskID: taskID,
    videoFormat: videoFormat,
    context: context,
    targetSize: targetSize,
    faceRestoration: faceRestoration,
    paddingContain: paddingContain,
  );

  /// Submits result dimensions and the downlink bitrate budget for the current task.
  ///
  /// See [StreamControlling.changeTargetSize] for the usage contract.
  @override
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  }) => _roomController.changeTargetSize(
    taskID: taskID,
    targetSize: targetSize,
    ensureActive: ensureActive,
  );

  /// Stops generation and interactions while retaining the RTC connection.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  @override
  Future<void> stopGeneration({
    required String taskID,
  }) async {
    final stoppedTaskID = _generationTaskID;

    if (stoppedTaskID == null ||
        (taskID.isNotEmpty && taskID != stoppedTaskID)) {
      return;
    }

    await _clearGeneration(notifyRemote: true);
    await _roomController.stopGeneration(taskID: stoppedTaskID);
  }

  /// Submits normalized interaction points; sends nothing if the task identifier or point list is
  /// empty.
  ///
  /// See [StreamControlling.sendTracks] for the usage contract.
  @override
  Future<void> sendTracks({
    required String taskID,
    required List<RealtimePoint> points,
  }) => _roomController.sendTracks(
    taskID: taskID,
    points: points,
  );

  /// Tracks the expected user's video publications and subscriptions, clearing results on
  /// unpublication.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  /// - [published]: Whether the remote stream is published.
  void _onRemoteVideoPublished(
    RemoteStream stream,
    bool published,
  ) {
    if (!_isExpectedRemote(stream)) {
      return;
    }

    if (published) {
      _publishedVideoStreams[stream.streamID] = stream;
      if (!_remoteVideoSubscriptions.contains(stream.streamID) &&
          _subscribingVideo.add(stream.streamID)) {
        unawaited(_subscribeRemoteVideo(stream));
      }
    } else {
      _publishedVideoStreams.remove(stream.streamID);
      _remoteVideoSubscriptions.remove(stream.streamID);
      _decodedRemoteStreams.remove((
        stream.roomID,
        stream.userID,
        stream.streamID,
      ));
      _renderedRemoteStreams.remove((
        stream.roomID,
        stream.userID,
        stream.streamID,
      ));
      if (_activeRemoteStream?.streamID == stream.streamID) {
        _activeRemoteStream = null;
        unawaited(_deactivateRemoteAudio());
        _clearRemoteStream();
      }
    }
  }

  /// Records the first decoded result frame and notifies waiting operations.
  ///
  /// Parameters:
  /// - [stream]: The remote stream whose first frame has been decoded.
  void _onFirstRemoteVideoFrameDecoded(
    RemoteStream stream,
  ) {
    if (!_isExpectedRemote(stream)) {
      return;
    }

    _decodedRemoteStreams.add((stream.roomID, stream.userID, stream.streamID));

    final active = _activeRemoteStream;

    if (active != null &&
        active.roomID == stream.roomID &&
        active.userID == stream.userID &&
        active.streamID == stream.streamID) {
      _remoteFrameReadyListener?.call(stream);
    }
  }

  /// Records the first rendered result frame and notifies the view that it can display video.
  ///
  /// Parameters:
  /// - [stream]: The remote stream whose first frame has been rendered.
  void _onFirstRemoteVideoFrameRendered(
    RemoteStream stream,
  ) {
    if (!_isExpectedRemote(stream)) {
      return;
    }

    // RTC first-frame events belong to subscriptions, not individual generation tasks.
    // Retain first-frame records until unpublication or disconnect, including events preceding result selection.
    _renderedRemoteStreams.add((stream.roomID, stream.userID, stream.streamID));

    final active = _activeRemoteStream;

    if (active == null ||
        active.roomID != stream.roomID ||
        active.userID != stream.userID ||
        active.streamID != stream.streamID) {
      return;
    }

    _remoteFrameRenderedListener?.call(stream);
  }

  /// Tracks the result user's audio publications and subscribes when needed.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  /// - [published]: Whether the remote stream is published.
  void _onRemoteAudioPublished(
    RemoteStream stream,
    bool published,
  ) {
    if (!_isExpectedRemote(stream)) {
      return;
    }

    if (published) {
      _publishedRemoteAudioStreams[stream.userID] = stream.streamID;
      if (_activeRemoteStream?.userID == stream.userID) {
        unawaited(_activatePublishedAudio());
      }

      return;
    }

    if (_publishedRemoteAudioStreams[stream.userID] != stream.streamID) {
      return;
    }

    _publishedRemoteAudioStreams.remove(stream.userID);
    if (_activeRemoteStream?.userID == stream.userID) {
      unawaited(_deactivateRemoteAudio());
    }
  }

  /// Activate newly published audio only when result audio is enabled.
  Future<void> _activatePublishedAudio() async {
    if (!_remoteAudioEnabled) {
      return;
    }

    final revision = _audioSubscriptionVersion;
    final connectionRevision = _connectionRevision;

    try {
      await activateRemoteAudio();
    } catch (error) {
      if (revision != _audioSubscriptionVersion ||
          connectionRevision != _connectionRevision) {
        return;
      }

      final xmaxError = XmaxError.from(error);

      if (xmaxError.code != XmaxErrorCode.cancelled) {
        _errorListener?.call(xmaxError);
      }
    }
  }

  /// Subscribes to the expected user's video, discarding results from expired connections.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  Future<void> _subscribeRemoteVideo(
    RemoteStream stream,
  ) async {
    final revision = _connectionRevision;

    try {
      await _rtcManager.subscribeRemoteVideo(
        streamID: stream.streamID,
        subscribe: true,
      );
      if (revision != _connectionRevision ||
          !_publishedVideoStreams.containsKey(stream.streamID)) {
        return;
      }

      _remoteVideoSubscriptions.add(stream.streamID);
      _subscribingVideo.remove(stream.streamID);
      _confirmPublishedRemoteStream();
    } catch (error) {
      // Late failures from an older room must not remove newer subscriptions or fail newer generation requests.
      if (revision != _connectionRevision) {
        return;
      }

      _subscribingVideo.remove(stream.streamID);
      _remoteVideoSubscriptions.remove(stream.streamID);

      final xmaxError = XmaxError.from(error);

      if (!_rejectGeneration(xmaxError)) {
        _errorListener?.call(xmaxError);
      }
    }
  }

  /// Confirms the result stream after successful start signaling and subscription to the expected
  /// video.
  void _confirmPublishedRemoteStream() {
    final taskID = _generationTaskID;
    final completer = _generationCompleter;

    if (!_startSignalSent ||
        taskID == null ||
        completer == null ||
        completer.isCompleted) {
      return;
    }

    final stream = _publishedVideoStreams.values
        .where(
          (
            stream,
          ) =>
              _isExpectedRemote(stream) &&
              _remoteVideoSubscriptions.contains(stream.streamID),
        )
        .firstOrNull;

    if (stream == null) {
      return;
    }

    XmaxLogger.debug(
      category: XmaxLoggerCategory.stream,
      message:
          '生成结果流已确认 (Generation Stream Confirmed)\n└─ ${XmaxLogger.localized('taskID：', 'taskID: ')}$taskID',
    );
    _activeRemoteStream = stream;
    _remoteStreamListener?.call(stream);
    if (_decodedRemoteStreams.contains((
      stream.roomID,
      stream.userID,
      stream.streamID,
    ))) {
      _remoteFrameReadyListener?.call(stream);
    }

    if (_renderedRemoteStreams.contains((
      stream.roomID,
      stream.userID,
      stream.streamID,
    ))) {
      _remoteFrameRenderedListener?.call(stream);
    }

    _generationTimer?.cancel();
    _generationTimer = null;
    _generationCompleter = null;
    completer.complete();
  }

  /// Fails pending result confirmation first; otherwise forwards the error to the active lifecycle
  /// listener.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  void _onError(
    Object error,
  ) {
    final xmaxError = XmaxError.from(error);

    if (!_rejectGeneration(xmaxError)) {
      final listener = _roomID.isEmpty
          ? (_localMediaErrorListener ?? _errorListener)
          : _errorListener;

      listener?.call(xmaxError);
    }
  }

  /// Checks whether the stream's room and user account match the current session.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  ///
  /// Returns whether the stream's room and account match the current session.
  bool _isExpectedRemote(
    RemoteStream stream,
  ) =>
      stream.roomID == _roomID &&
      (_botName.isEmpty || stream.userID == _botName);

  /// Fails current result confirmation with the specified error and cancels its timer.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns whether a pending result confirmation was found and completed.
  bool _rejectGeneration(
    XmaxError error,
  ) {
    final completer = _generationCompleter;

    _generationTimer?.cancel();
    _generationTimer = null;
    _generationCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);

      return true;
    }

    return false;
  }

  /// Ends the task and readiness waits, stops adaptation, and clears remote audio and display
  /// state.
  ///
  /// Parameters:
  /// - [notifyRemote]: Whether to notify the view to clear its result-stream binding.
  Future<void> _clearGeneration({
    required bool notifyRemote,
  }) async {
    _rejectGeneration(
      const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime generation start cancelled',
      ),
    );

    _generationTaskID = null;
    _startSignalSent = false;
    _downlinkStatisticsListener?.call(null);
    _remoteAudioEnabled = false;
    _activeRemoteStream = null;
    await _deactivateRemoteAudio();

    if (notifyRemote) {
      _clearRemoteStream();
    }
  }

  /// Checks whether an audio subscription still belongs to the current task and result stream.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  /// - [streamID]: The identifier of the media stream to publish, subscribe to, or control.
  /// - [version]: The asynchronous operation revision.
  ///
  /// Returns whether the task, audio stream, and subscription version remain valid.
  bool _isAudioStreamCurrent(
    RemoteStream stream,
    String streamID,
    int version,
  ) =>
      version == _audioSubscriptionVersion &&
      _generationTaskID != null &&
      identical(
        _activeRemoteStream,
        stream,
      ) &&
      _publishedRemoteAudioStreams[stream.userID] == streamID;

  /// Throws a cancellation error if the audio subscription is no longer valid.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  /// - [streamID]: The identifier of the media stream to publish, subscribe to, or control.
  /// - [version]: The asynchronous operation revision.
  void _ensureAudioStreamCurrent(
    RemoteStream stream,
    String streamID,
    int version,
  ) {
    if (!_isAudioStreamCurrent(
      stream,
      streamID,
      version,
    )) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Remote generation audio subscription was cancelled',
      );
    }
  }

  /// Invalidates pending audio subscriptions and cancels the active remote subscription.
  Future<void> _deactivateRemoteAudio() async {
    final subscribedID = _subscribedRemoteAudioStreamID;

    _audioSubscriptionVersion += 1;
    _subscribedRemoteAudioStreamID = null;
    if (subscribedID == null) {
      return;
    }

    await _safe(
      '取消订阅 RTC 远端音频失败 (Failed to Unsubscribe from RTC Remote Audio)',
      () => _rtcManager.subscribeRemoteAudio(
        streamID: subscribedID,
        subscribe: false,
      ),
    );
  }

  /// Clears the result-stream binding, logging listener failures without propagating them.
  void _clearRemoteStream() {
    try {
      _remoteStreamListener?.call(null);
    } catch (error) {
      XmaxLogger.error(
        category: XmaxLoggerCategory.stream,
        message:
            '清理 RTC 远端生成流失败 '
            '(Failed to Clean Up RTC Remote Generation Stream)\n'
            '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
      );
    }
  }

  /// Performs a cleanup operation, logging failures so remaining cleanup can continue.
  ///
  /// Parameters:
  /// - [title]: The log group's title.
  /// - [operation]: The asynchronous operation to execute.
  Future<void> _safe(
    String title,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      XmaxLogger.error(
        category: XmaxLoggerCategory.stream,
        message: '$title\n└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
      );
    }
  }
}
