//
//  AgoraRtcPlatform.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../service/realtime/RealtimeVideoFormat.dart';
import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import '../media/camera/CameraPosition.dart';
import '../media/video/RealtimeExternalVideoFrame.dart';
import 'AgoraRtcRoom.dart';
import 'LocalStream.dart';
import 'RtcEventListener.dart';
import 'RtcManaging.dart';
import 'RtcPlatform.dart';
import 'RtcRoom.dart';
import 'VideoEncodingConfiguration.dart';
import 'RemoteStream.dart';
import 'AgoraRemoteMediaObserver.dart';
import '../../service/realtime/RealtimeMediaFrame.dart';

/// An Agora engine adapter for local media, encoding, rendering, and room creation.
class AgoraRtcPlatform implements RtcPlatform {

  /// The optional raw media observer; absent during ordinary texture-only rendering.
  AgoraRemoteMediaObserver? _mediaObserver;

  /// Rejects native callbacks and late UID lookups after observer replacement.
  int _mediaObserverVersion = 0;

  /// Enables copied I420 and PCM only for the requested result binding.
  ///
  /// See [RtcPlatform.setRemoteMediaFrameListener] for the delivery contract.
  @override
  Future<void> setRemoteMediaFrameListener({
    required RemoteStream? stream,
    required void Function(
      RealtimeMediaFrameContent content,
    )? listener,
  }) async {
    final version = ++_mediaObserverVersion;
    final previous = _mediaObserver;
    _mediaObserver = null;
    if (previous != null) {
      previous.active = false;
      engine.getMediaEngine().unregisterVideoFrameObserver(previous.video);
      engine.getMediaEngine().unregisterAudioFrameObserver(previous.audio);
    }
    if (_isClosed || stream == null || listener == null) {
      return;
    }

    final room = _room;
    if (room == null || !room.isJoined || room.roomID != stream.roomID) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Remote media observation requires an active result room',
      );
    }
    final uid = await room.resolveUID(stream.userID);
    if (_isClosed || version != _mediaObserverVersion || room.isClosed) {
      return;
    }
    await engine.setPlaybackAudioFrameBeforeMixingParameters(
      sampleRate: 48000,
      channel: 1,
      samplesPerCall: 480,
    );
    if (_isClosed || version != _mediaObserverVersion || room.isClosed) {
      return;
    }

    final observer = AgoraRemoteMediaObserver(
      channelID: stream.roomID,
      uid: uid,
      listener: listener,
    );
    _mediaObserver = observer;
    engine.getMediaEngine().registerVideoFrameObserver(observer.video);
    engine.getMediaEngine().registerAudioFrameObserver(observer.audio);
  }

  /// Wraps an initialized engine with local capture disabled.
  AgoraRtcPlatform(
    this.engine,
  ) {
    _handler = RtcEngineEventHandler(
      onError: (
        code,
        message,
      ) {
        if (!_isClosed) {
          _eventListener?.onError?.call(
            XmaxError(
              code: XmaxErrorCode.rtcError,
              message: 'RTC ${code.name}: $message',
            ),
          );
        }
      },
      onFirstLocalVideoFrame: (
        _,
        width,
        height,
        _,
      ) {
        if (!_isClosed && width > 0 && height > 0) {
          _cameraPreviewReadyListener?.call();
        }
      },
      onLocalVideoStateChanged: (
        source,
        state,
        reason,
      ) {
        if (!_isClosed) {
          _logLocalVideoState(
            source,
            state,
            reason,
          );
        }
      },
    );
    engine.registerEventHandler(_handler);
  }

  /// The native engine owned by this adapter.
  final RtcEngineEx engine;

  /// The handler forwarding engine-wide media and failure events.
  late final RtcEngineEventHandler _handler;

  /// The current engine-wide failure receiver.
  RtcEventListener? _eventListener;

  /// The one-shot readiness receiver managed by camera control.
  void Function()? _cameraPreviewReadyListener;

  /// The active or most recently closed room adapter.
  AgoraRtcRoom? _room;

  /// Whether native resources are no longer available.
  bool _isClosed = false;

  /// The shared engine shutdown awaited by repeated cleanup requests.
  Future<void>? _destroying;

  /// The current capture camera.
  CameraPosition _position = CameraPosition.front;

  /// Whether the current local input is caller-owned external video.
  bool _usesExternalVideo = false;

  /// Whether built-in microphone capture has started successfully.
  bool _isMicrophoneCapturing = false;

  /// The optional custom audio track configured for external input.
  int? _externalAudioTrackID;

  /// Whether room publication currently permits external audio submission.
  bool isPublishingLocalMedia = false;

  /// The most recently applied encoding settings.
  VideoEncodingConfiguration? _encoding;

  /// Whether local publication uses custom rather than camera video.
  bool get usesExternalVideo => _usesExternalVideo;

  /// Whether the current camera input has enabled microphone capture for room publication.
  bool get isMicrophoneCapturing => _isMicrophoneCapturing;

  /// Reapplies retained encoding after room publication changes its native connection.
  Future<void> reapplyVideoConfiguration() async {
    final encoding = _encoding;

    if (encoding != null) {
      await configureVideoEncoding(encoding);
    }
  }

  /// The opted-in custom audio track, or null for video-only input.
  int? get externalAudioTrackID => _externalAudioTrackID;

  /// Initializes an Agora engine with camera and microphone capture disabled.
  ///
  /// [appID] is the RTC application identifier expected by the server.
  static Future<RtcPlatform> create(
    String appID,
  ) async {
    final engine = createAgoraRtcEngineEx();

    try {
      await engine.initialize(
        RtcEngineContext(
          appId: appID,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
      await engine.enableVideo();
      await engine.enableLocalVideo(false);
      await engine.enableLocalAudio(false);

      return AgoraRtcPlatform(engine);
    } catch (_) {
      await engine.release();
      rethrow;
    }
  }

  /// Replaces engine-wide failure delivery.
  @override
  void setEventListener(
    RtcEventListener? listener,
  ) => _eventListener = _isClosed ? null : listener;

  /// Replaces local capture first-frame delivery.
  @override
  void setCameraPreviewReadyListener(
    void Function()? listener,
  ) => _cameraPreviewReadyListener = _isClosed ? null : listener;

  /// Creates an unjoined room while retaining local media independently.
  ///
  /// Parameters:
  /// - [roomID]: The server-assigned channel identifier.
  /// - [leaveTimeout]: The deadline for native leave confirmation.
  @override
  RtcRoom createRoom({
    required String roomID,
    required Duration leaveTimeout,
  }) {
    if (_isClosed || (_room != null && !_room!.isClosed)) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC platform cannot create another active room',
      );
    }

    final room = AgoraRtcRoom(
      platform: this,
      roomID: roomID,
      leaveTimeout: leaveTimeout,
    );
    _room = room;

    return room;
  }

  /// The native input binding for the currently selected local media source.
  @override
  LocalStream get localStream => LocalStream(
    engine: engine,
    isExternal: _usesExternalVideo,
  );

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
      mirrorMode: !_usesExternalVideo && _position == CameraPosition.front
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

    await check(
      () => connection == null
          ? engine.setVideoEncoderConfiguration(encoder)
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

  /// Starts camera capture and preview without changing microphone capture.
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
    await check(() => engine.enableLocalVideo(true));
    await check(() => engine.startPreview());
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
    await check(
      () => engine.setCameraCapturerConfiguration(
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
    if (_isClosed) {
      return;
    }

    await check(() => engine.stopPreview());
    await check(() => engine.enableLocalVideo(false));
  }

  /// Starts built-in microphone capture without monitoring it locally.
  @override
  Future<void> startAudioCapture() async {
    if (_usesExternalVideo) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Microphone capture cannot be combined with an external media source',
      );
    }
    if (_isMicrophoneCapturing) {
      return;
    }

    await check(() => engine.enableLocalAudio(true));
    _isMicrophoneCapturing = true;
  }

  /// Stops built-in microphone capture without affecting video capture or remote audio playback.
  @override
  Future<void> stopAudioCapture() async {
    if (_isClosed) {
      return;
    }

    await check(() => engine.enableLocalAudio(false));
    _isMicrophoneCapturing = false;
  }

  /// Configures custom media with native camera and microphone capture disabled.
  ///
  /// See [RtcManaging.startExternalVideoSource] for the usage contract.
  @override
  Future<void> startExternalVideoSource({
    required bool hasAudio,
  }) async {
    if (_isMicrophoneCapturing) {
      await stopAudioCapture();
    }

    _usesExternalVideo = true;
    await engine.getMediaEngine().setExternalVideoSource(
      enabled: true,
      useTexture: false,
    );

    if (hasAudio) {
      final trackID = await engine.getMediaEngine().createCustomAudioTrack(
        trackType: AudioTrackType.audioTrackDirect,
        config: const AudioTrackConfig(
          enableLocalPlayback: false,
          enableAudioProcessing: false,
        ),
      );
      if (trackID < 0 || trackID == 0xffffffff) {
        throw const XmaxError(
          code: XmaxErrorCode.rtcError,
          message: 'Could not create the external audio track',
        );
      }
      _externalAudioTrackID = trackID;
    }

    await engine.startPreview(
      sourceType: VideoSourceType.videoSourceCustom,
    );
  }

  /// Stops custom preview and releases audio before the engine lease is returned.
  @override
  Future<void> stopExternalVideoSource() async {
    isPublishingLocalMedia = false;

    if (_isClosed) {
      return;
    }

    final audio = _externalAudioTrackID;

    _externalAudioTrackID = null;
    try {
      await engine.stopPreview(
        sourceType: VideoSourceType.videoSourceCustom,
      );
    } finally {
      try {
        if (audio != null) {
          await engine.getMediaEngine().destroyCustomAudioTrack(audio);
        }
      } finally {
        await engine.enableLocalVideo(false);
        await engine.getMediaEngine().setExternalVideoSource(
          enabled: false,
          useTexture: false,
        );
        _usesExternalVideo = false;
      }
    }
  }

  /// Pushes custom pixels through the native media engine, retaining native scaling and rendering.
  ///
  /// See [RtcManaging.pushExternalVideoFrame] for the usage contract.
  @override
  Future<void> pushExternalVideoFrame(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  }) {
    final bgra = frame.pixelFormat == RealtimeExternalVideoPixelFormat.bgra;
    final stride = frame.rowBytes ~/ (bgra ? 4 : 1);

    return engine.getMediaEngine().pushVideoFrame(
      frame: ExternalVideoFrame(
        type: VideoBufferType.videoBufferRawData,
        format: bgra
            ? VideoPixelFormat.videoPixelBgra
            : VideoPixelFormat.videoPixelNv12,
        buffer: frame.data,
        stride: stride,
        height: frame.height,
        cropRight: stride - frame.width,
        rotation: 0,
        timestamp: timestamp.inMilliseconds,
        colorSpace: ColorSpace(
          range: bgra ? RangeID.rangeidFull : RangeID.rangeidLimited,
        ),
      ),
    );
  }

  /// Pushes opted-in audio without local playback or buffering while disconnected.
  ///
  /// See [RtcManaging.pushExternalAudioFrame] for the usage contract.
  @override
  Future<void> pushExternalAudioFrame(
    Uint8List data, {
    required Duration timestamp,
  }) async {
    final trackID = _externalAudioTrackID;

    if (!isPublishingLocalMedia || trackID == null) {
      return;
    }

    await engine.getMediaEngine().pushAudioFrame(
      frame: AudioFrame(
        type: AudioFrameType.frameTypePcm16,
        samplesPerChannel: 480,
        bytesPerSample: BytesPerSample.twoBytesPerSample,
        channels: 1,
        samplesPerSec: 48000,
        buffer: data,
        renderTimeMs: timestamp.inMilliseconds,
      ),
      trackId: trackID,
    );
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
      await check(() => engine.switchCamera());
      _position = position;
    }

    if (_encoding case final encoding?) {
      await configureVideoEncoding(encoding);
    }
  }

  /// Runs an RTC call and normalizes native failures and timeouts as SDK errors.
  ///
  /// Parameters:
  /// - [operation]: The asynchronous operation to execute.
  static Future<void> check(
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

  /// Closes callbacks before releasing the room and shared engine resources.
  @override
  Future<void> destroy() {
    if (_destroying case final pending?) {
      return pending;
    }

    _isClosed = true;
    _mediaObserverVersion++;
    _mediaObserver?.active = false;
    _mediaObserver = null;
    _eventListener = null;
    _cameraPreviewReadyListener = null;
    final future = _destroy();
    _destroying = future;

    return future;
  }

  /// Settles room cleanup and releases the engine even when room leave fails.
  Future<void> _destroy() async {
    try {
      await _room?.destroy();
    } finally {
      try {
        engine.unregisterEventHandler(_handler);
      } finally {
        _room = null;
        _encoding = null;
        _externalAudioTrackID = null;
        _isMicrophoneCapturing = false;
        isPublishingLocalMedia = false;
        await engine.release();
      }
    }
  }
}
