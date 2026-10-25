import 'dart:async';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEngineManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/AgoraRtcPlatform.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

const _configuration = RoomJoinConfiguration(
  roomID: 'room',
  userID: 'user',
  token: 'token',
);

void main() {
  test(
    'camera microphone publication is opt-in and stops without restarting preview',
    () async {
      final platform = _Platform();
      final engine = platform.engine..autoCompleteLeave = true;
      final manager = _manager(platform);
      await manager.initialize();
      await manager.startVideoCapture(width: 1024, height: 1920, frameRate: 30);
      await manager.joinRoom(configuration: _configuration);
      ChannelMediaOptions options() =>
          engine.calls
                  .lastWhere(
                    (call) => call.memberName == #updateChannelMediaOptionsEx,
                  )
                  .namedArguments[#options]
              as ChannelMediaOptions;
      await manager.publishLocalVideo(publish: true);
      expect(options().publishCameraTrack, isTrue);
      expect(options().publishMicrophoneTrack, isFalse);
      await manager.publishLocalVideo(publish: false);

      await manager.startAudioCapture();
      await manager.startAudioCapture();
      expect(
        engine.calls
            .where((call) => call.memberName == #enableLocalAudio)
            .map((call) => call.positionalArguments.single),
        [true],
      );
      await manager.publishLocalVideo(publish: true);
      expect(options().publishMicrophoneTrack, isTrue);
      expect(options().enableAudioRecordingOrPlayout, isTrue);
      expect(options().publishCustomAudioTrack, isFalse);
      await manager.stopAudioCapture();
      await manager.publishLocalVideo(publish: false);
      expect(options().publishMicrophoneTrack, isFalse);
      expect(options().enableAudioRecordingOrPlayout, isTrue);
      await manager.leaveRoom();
      expect(engine.previewStarts, 1);
      expect(engine.previewStops, 0);
      expect(engine.localVideoChanges, [true]);
      expect(
        engine.calls
            .where((call) => call.memberName == #enableLocalAudio)
            .map((call) => call.positionalArguments.single),
        [true, false],
      );
      await manager.startAudioCapture();
      await manager.joinRoom(configuration: _configuration);
      await manager.publishLocalVideo(publish: true);
      expect(options().publishMicrophoneTrack, isTrue);
      await manager.stopAudioCapture();
      await manager.destroy();
    },
  );

  test(
    'microphone errors retain cleanup eligibility and do not enable publication',
    () async {
      final platform = _Platform();
      final engine = platform.engine..autoCompleteLeave = true;
      final manager = _manager(platform);
      await manager.initialize();
      engine.rejectAudioStart = true;
      await expectLater(manager.startAudioCapture(), throwsA(isA<XmaxError>()));
      expect(platform.isMicrophoneCapturing, isFalse);
      await manager.stopAudioCapture();
      engine.rejectAudioStart = false;
      await manager.startAudioCapture();
      engine.rejectAudioStop = true;
      await expectLater(manager.stopAudioCapture(), throwsA(isA<XmaxError>()));
      expect(platform.isMicrophoneCapturing, isTrue);
      engine.rejectAudioStop = false;
      await manager.stopAudioCapture();
      expect(platform.isMicrophoneCapturing, isFalse);
      await manager.destroy();
    },
  );

  test(
    'external audio excludes microphone capture and stops any previous microphone',
    () async {
      final platform = _Platform();
      final manager = _manager(platform);
      await manager.initialize();
      await manager.startAudioCapture();
      await manager.startExternalVideoSource(hasAudio: true);
      expect(platform.isMicrophoneCapturing, isFalse);
      expect(platform.externalAudioTrackID, 12);
      await expectLater(manager.startAudioCapture(), throwsA(isA<XmaxError>()));
      expect(platform.isMicrophoneCapturing, isFalse);
      await manager.stopExternalVideoSource();
      await manager.destroy();
    },
  );

  test('released platform suppresses stale engine callbacks', () async {
    final platform = _Platform();
    final manager = _manager(platform);
    var frames = 0;
    var failures = 0;
    manager.setCameraPreviewReadyListener(() => frames++);
    manager.setEventListener(RtcEventListener(onError: (_) => failures++));
    await manager.initialize();
    final handler = platform.engine.handlers.single;
    handler.onFirstLocalVideoFrame!(
      VideoSourceType.videoSourceCamera,
      640,
      480,
      0,
    );
    expect(frames, 1);
    await manager.destroy();
    handler.onFirstLocalVideoFrame!(
      VideoSourceType.videoSourceCamera,
      640,
      480,
      0,
    );
    handler.onError!(ErrorCodeType.errFailed, 'late failure');
    expect(frames, 1);
    expect(failures, 0);
    expect(platform.engine.handlers, isEmpty);
  });

  test(
    'external input publishes custom tracks and preserves preview after leaving',
    () async {
      final platform = _Platform();
      final engine = platform.engine..autoCompleteLeave = true;
      final manager = _manager(platform);
      await manager.initialize();
      await manager.startExternalVideoSource(hasAudio: true);
      await manager.pushExternalAudioFrame(
        Uint8List(960),
        timestamp: Duration.zero,
      );
      expect(engine.media.audioPackets, 0);
      await manager.joinRoom(configuration: _configuration);
      await manager.publishLocalVideo(publish: true);
      final publication = engine.calls.lastWhere(
        (call) => call.memberName == #updateChannelMediaOptionsEx,
      );
      final options =
          publication.namedArguments[#options] as ChannelMediaOptions;
      expect(options.publishCameraTrack, isFalse);
      expect(options.publishMicrophoneTrack, isFalse);
      expect(options.publishCustomVideoTrack, isTrue);
      expect(options.customVideoTrackId, 0);
      expect(options.publishCustomAudioTrack, isTrue);
      expect(options.publishCustomAudioTrackId, 12);
      await manager.pushExternalAudioFrame(
        Uint8List(960),
        timestamp: const Duration(seconds: 1),
      );
      expect(engine.media.audioPackets, 1);
      expect(engine.media.lastAudio!.samplesPerChannel, 480);
      expect(engine.media.lastAudio!.channels, 1);
      expect(engine.media.lastAudio!.samplesPerSec, 48000);
      expect(engine.media.lastAudio!.renderTimeMs, 1000);
      await manager.publishLocalVideo(publish: false);
      await manager.leaveRoom();
      await manager.pushExternalVideoFrame(
        RealtimeExternalVideoFrame(
          data: Uint8List(16),
          width: 2,
          height: 2,
          pixelFormat: RealtimeExternalVideoPixelFormat.bgra,
        ),
        timestamp: const Duration(seconds: 2),
      );
      await manager.pushExternalAudioFrame(
        Uint8List(960),
        timestamp: const Duration(seconds: 2),
      );
      expect(engine.media.audioPackets, 1);
      expect(engine.media.videoPackets, 1);
      expect(engine.previewStarts, 1);
      expect(engine.previewStops, 0);
      expect(engine.captureConfigurations, 0);
      expect(engine.localVideoChanges, isEmpty);
      expect(
        engine.calls
            .singleWhere((call) => call.memberName == #startPreview)
            .namedArguments[#sourceType],
        VideoSourceType.videoSourceCustom,
      );
      await manager.stopExternalVideoSource();
      expect(engine.localVideoChanges, [false]);
      expect(
        engine.calls
            .singleWhere((call) => call.memberName == #stopPreview)
            .namedArguments[#sourceType],
        VideoSourceType.videoSourceCustom,
      );
      expect(engine.media.destroyedTracks, [12]);
      expect(engine.media.audioConfiguration!.enableLocalPlayback, isFalse);
      await manager.destroy();
    },
  );

  test('external encoding is not mirrored and audio remains opt-in', () async {
    final platform = _Platform();
    final engine = platform.engine;
    final manager = _manager(platform);
    await manager.initialize();
    await manager.startExternalVideoSource(hasAudio: false);
    await manager.configureVideoEncoding(
      const VideoEncodingConfiguration(width: 640, height: 480, frameRate: 30),
    );
    final encoding =
        engine.calls
                .lastWhere(
                  (call) => call.memberName == #setVideoEncoderConfiguration,
                )
                .positionalArguments
                .single
            as VideoEncoderConfiguration;
    expect(encoding.mirrorMode, VideoMirrorModeType.videoMirrorModeDisabled);
    expect(engine.media.audioConfiguration, isNull);
    await manager.stopExternalVideoSource();
    await manager.destroy();
  });

  test('transport and public video formats default to frame-rate priority', () {
    expect(
      const VideoEncodingConfiguration(
        width: 1080,
        height: 1920,
        frameRate: 30,
      ).encoderPreference,
      RealtimeVideoEncoderPreference.maintainFramerate,
    );
    expect(
      const RealtimeVideoFormat(
        width: 1080,
        height: 1920,
        fps: 30,
      ).encoderPreference,
      RealtimeVideoEncoderPreference.maintainFramerate,
    );
  });
  setUp(XmaxLogger.reset);
  tearDown(XmaxLogger.reset);

  test(
    'capture format update does not stop, enable, or remount the preview',
    () async {
      final platform = _Platform();
      final manager = _manager(platform);
      await manager.initialize();
      await manager.startVideoCapture(width: 1080, height: 1920, frameRate: 30);
      platform.engine.calls.clear();
      await manager.updateVideoCapture(
        width: 1408,
        height: 1408,
        frameRate: 24,
      );
      expect(platform.engine.calls.map((call) => call.memberName), [
        #setCameraCapturerConfiguration,
      ]);
      final config =
          platform.engine.calls.single.positionalArguments.single
              as CameraCapturerConfiguration;
      expect(
        (config.format!.width, config.format!.height, config.format!.fps),
        (1408, 1408, 24),
      );
      expect(config.followEncodeDimensionRatio, isFalse);
      await manager.destroy();
    },
  );

  test('publication and adaptation configure the actual Ex encoder', () async {
    final platform = _Platform();
    final engine = platform.engine..autoCompleteLeave = true;
    final manager = _manager(platform);
    const initial = VideoEncodingConfiguration(
      width: 1024,
      height: 1920,
      frameRate: 30,
      minimumBitrate: 100,
      maximumBitrate: 3600,
      encoderPreference: RealtimeVideoEncoderPreference.maintainFramerate,
    );
    await manager.initialize();
    await manager.configureVideoEncoding(initial);
    expect(_encodingCalls(engine, #setVideoEncoderConfiguration), hasLength(1));
    expect(_encodingCalls(engine, #setVideoEncoderConfigurationEx), isEmpty);

    await manager.joinRoom(configuration: _configuration);
    await manager.publishLocalVideo(publish: true);
    final published = _encodingCalls(
      engine,
      #setVideoEncoderConfigurationEx,
    ).single;
    _expectEncoder(published, initial, 1);
    expect(
      engine.calls.indexOf(published),
      greaterThan(
        engine.calls.indexWhere(
          (call) => call.memberName == #updateChannelMediaOptionsEx,
        ),
      ),
    );

    const adapted = VideoEncodingConfiguration(
      width: 832,
      height: 1560,
      frameRate: 24,
      minimumBitrate: 100,
      maximumBitrate: 2400,
      encoderPreference: RealtimeVideoEncoderPreference.maintainQuality,
    );
    await manager.configureVideoEncoding(adapted);
    _expectEncoder(
      _encodingCalls(engine, #setVideoEncoderConfigurationEx).last,
      adapted,
      1,
    );
    expect(_encodingCalls(engine, #setVideoEncoderConfiguration), hasLength(1));
    await manager.switchCamera(position: CameraPosition.back);
    final switched = _encodingCalls(
      engine,
      #setVideoEncoderConfigurationEx,
    ).last;
    _expectEncoder(switched, adapted, 1);
    expect(
      (switched.namedArguments[#config] as VideoEncoderConfiguration)
          .mirrorMode,
      VideoMirrorModeType.videoMirrorModeDisabled,
    );
    final appliedCount = _encodingCalls(
      engine,
      #setVideoEncoderConfigurationEx,
    ).length;
    await manager.publishLocalVideo(publish: false);
    await manager.leaveRoom();
    expect(
      _encodingCalls(engine, #setVideoEncoderConfigurationEx),
      hasLength(appliedCount),
    );
    expect(engine.previewStarts, 0);
    expect(engine.previewStops, 0);
    await manager.destroy();
  });

  test('rejoining reapplies cached encoding to the new local UID', () async {
    final platform = _Platform();
    final engine = platform.engine..autoCompleteLeave = true;
    final manager = _manager(platform);
    const configuration = VideoEncodingConfiguration(
      width: 1024,
      height: 1920,
      frameRate: 30,
      minimumBitrate: 100,
      maximumBitrate: 3600,
    );
    await manager.initialize();
    await manager.configureVideoEncoding(configuration);
    await manager.joinRoom(configuration: _configuration);
    await manager.publishLocalVideo(publish: true);
    await manager.leaveRoom();
    engine.assignedLocalUid = 42;
    await manager.joinRoom(configuration: _configuration);
    await manager.publishLocalVideo(publish: true);
    final calls = _encodingCalls(engine, #setVideoEncoderConfigurationEx);
    expect(calls, hasLength(2));
    _expectEncoder(calls.first, configuration, 1);
    _expectEncoder(calls.last, configuration, 42);
    expect(_encodingCalls(engine, #setVideoEncoderConfiguration), hasLength(1));
    await manager.destroy();
  });

  test(
    'rejected Ex encoding does not overwrite the last accepted target',
    () async {
      final platform = _Platform();
      final engine = platform.engine..autoCompleteLeave = true;
      final manager = _manager(platform);
      const accepted = VideoEncodingConfiguration(
        width: 1024,
        height: 1920,
        frameRate: 30,
        minimumBitrate: 100,
        maximumBitrate: 3600,
      );
      await manager.initialize();
      await manager.configureVideoEncoding(accepted);
      await manager.joinRoom(configuration: _configuration);
      engine.rejectEncoding = true;
      await expectLater(
        manager.configureVideoEncoding(
          const VideoEncodingConfiguration(
            width: 512,
            height: 960,
            frameRate: 16,
            minimumBitrate: 100,
            maximumBitrate: 1000,
          ),
        ),
        throwsA(isA<XmaxError>()),
      );
      engine.rejectEncoding = false;
      await manager.publishLocalVideo(publish: true);
      _expectEncoder(
        _encodingCalls(engine, #setVideoEncoderConfigurationEx).last,
        accepted,
        1,
      );
      await manager.destroy();
    },
  );

  test(
    'local camera state logs report native values without restarting capture',
    () async {
      final platform = _Platform();
      final manager = _manager(platform);
      final messages = <String>[];
      XmaxLogger.configure(
        options: XmaxLoggerOption.business,
        environment: XmaxEnvironment.global,
      );
      XmaxLogger.setSink((_, message) => messages.add(message));
      await manager.initialize();
      platform.engine.handlers.single.onLocalVideoStateChanged!(
        VideoSourceType.videoSourceCameraPrimary,
        LocalVideoStreamState.localVideoStreamStateCapturing,
        LocalVideoStreamReason.localVideoStreamReasonOk,
      );
      expect(messages.single, contains('Local Video State'));
      expect(
        messages.single,
        contains('State: localVideoStreamStateCapturing'),
      );
      expect(messages.single, contains('Reason: localVideoStreamReasonOk'));
      expect(platform.engine.previewStarts, 0);
      expect(platform.engine.localVideoChanges, isEmpty);
      await manager.destroy();
    },
  );

  test(
    'leaving does not stop, restart, or reconfigure the local camera',
    () async {
      final platform = _Platform();
      final manager = _manager(platform);
      await manager.initialize();
      await manager.startVideoCapture(width: 832, height: 1472, frameRate: 30);
      await manager.joinRoom(configuration: _configuration);
      await manager.publishLocalVideo(publish: true);
      await manager.publishLocalVideo(publish: false);

      var left = false;
      final leaving = manager.leaveRoom().then((_) => left = true);
      await platform.engine.leaveRequested.future;
      await _flush();
      expect(left, isFalse);
      expect(platform.engine.previewStarts, 1);
      platform.engine.completeLeave('another-room');
      await _flush();
      expect(left, isFalse);
      platform.engine.completeLeave('room', 99);
      await _flush();
      expect(left, isFalse);

      platform.engine.completeLeave();
      await leaving;
      expect(platform.engine.previewStarts, 1);
      expect(platform.engine.localVideoEnabled, isTrue);
      expect(platform.engine.localVideoChanges, [true]);
      expect(platform.engine.cameraPublished, isFalse);
      expect(platform.engine.previewStops, 0);
      expect(platform.engine.captureConfigurations, 1);
      await manager.destroy();
    },
  );

  test('stopping the camera during leave keeps the camera stopped', () async {
    final platform = _Platform();
    final manager = _manager(platform);
    await manager.initialize();
    await manager.startVideoCapture(width: 832, height: 1472, frameRate: 30);
    await manager.joinRoom(configuration: _configuration);
    final leaving = manager.leaveRoom();
    await platform.engine.leaveRequested.future;
    await manager.stopVideoCapture();
    platform.engine.completeLeave();
    await leaving;
    expect(platform.engine.previewStarts, 1);
    expect(platform.engine.localVideoEnabled, isFalse);
    expect(platform.engine.localVideoChanges, [true, false]);
    expect(platform.engine.previewStops, 1);
    await manager.destroy();
  });

  test('leaving without a local camera does not start preview', () async {
    final platform = _Platform();
    final manager = _manager(platform);
    await manager.initialize();
    await manager.joinRoom(configuration: _configuration);
    final leaving = manager.leaveRoom();
    await platform.engine.leaveRequested.future;
    platform.engine.completeLeave();
    await leaving;
    expect(platform.engine.previewStarts, 0);
    await manager.destroy();
  });

  test('reconnecting waits for leave without restarting the camera', () async {
    final platform = _Platform();
    final manager = _manager(platform);
    await manager.initialize();
    await manager.startVideoCapture(width: 832, height: 1472, frameRate: 30);
    await manager.joinRoom(configuration: _configuration);
    final leaving = manager.leaveRoom();
    await platform.engine.leaveRequested.future;
    final joining = manager.joinRoom(configuration: _configuration);
    await _flush();
    expect(platform.engine.joinCount, 1);
    expect(platform.engine.leaveCount, 1);
    platform.engine.completeLeave();
    await leaving;
    await joining;
    expect(platform.engine.joinCount, 2);
    expect(platform.engine.previewStarts, 1);
    expect(platform.engine.previewStops, 0);
    expect(platform.engine.captureConfigurations, 1);
    expect(platform.engine.localVideoChanges, [true]);
    platform.engine.autoCompleteLeave = true;
    await manager.destroy();
  });

  test(
    'media publication, subscription and volume use the same Ex connection',
    () async {
      final platform = _Platform();
      final engine = platform.engine;
      final manager = _manager(platform);
      await manager.initialize();
      await manager.joinRoom(configuration: _configuration);
      await manager.publishLocalVideo(publish: true);
      await manager.subscribeRemoteVideo(streamID: 'bot', subscribe: true);
      await manager.subscribeRemoteAudio(streamID: 'bot', subscribe: true);
      await manager.setRemoteAudioVolume(streamID: 'bot', volume: 50);
      await manager.sendRoomMessage('{"event":"start","uid":"task"}');
      await manager.subscribeRemoteVideo(streamID: 'bot', subscribe: false);
      await manager.subscribeRemoteAudio(streamID: 'bot', subscribe: false);
      await manager.publishLocalVideo(publish: false);
      for (final name in [
        #createDataStreamEx,
        #updateChannelMediaOptionsEx,
        #muteRemoteVideoStreamEx,
        #muteRemoteAudioStreamEx,
        #adjustUserPlaybackSignalVolumeEx,
        #getUserInfoByUserAccountEx,
        #sendStreamMessageEx,
      ]) {
        final calls = engine.calls.where((call) => call.memberName == name);
        expect(calls, isNotEmpty);
        for (final call in calls) {
          final connection = call.namedArguments[#connection] as RtcConnection;
          expect(connection.channelId, 'room');
          expect(connection.localUid, 1);
        }
      }
      engine.autoCompleteLeave = true;
      await manager.destroy();
      expect(engine.previewStarts, 0);
      expect(engine.previewStops, 0);
    },
  );

  test('destroy during leave does not restart camera preview', () async {
    final platform = _Platform();
    final manager = _manager(platform);
    await manager.initialize();
    await manager.startVideoCapture(width: 832, height: 1472, frameRate: 30);
    await manager.joinRoom(configuration: _configuration);
    final leaving = manager.leaveRoom();
    await platform.engine.leaveRequested.future;
    final destroying = manager.destroy();
    await _flush();
    platform.engine.completeLeave();
    await leaving;
    await destroying;
    expect(platform.engine.previewStarts, 1);
    expect(platform.destroyCount, 1);
  });

  test('failed join does not lose an early native leave completion', () async {
    final platform = _Platform();
    final engine = platform.engine
      ..rejectJoin = true
      ..autoCompleteLeave = true;
    final manager = _manager(platform);
    await manager.initialize();
    await expectLater(
      manager
          .joinRoom(configuration: _configuration)
          .timeout(const Duration(seconds: 1)),
      throwsA(isA<XmaxError>()),
    );
    expect(engine.leaveCount, 1);
    await manager.destroy();
    expect(engine.leaveCount, 1);
    expect(platform.destroyCount, 1);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

List<Invocation> _encodingCalls(_Engine engine, Symbol method) =>
    engine.calls.where((call) => call.memberName == method).toList();

void _expectEncoder(
  Invocation call,
  VideoEncodingConfiguration target,
  int localUid,
) {
  final config = call.namedArguments[#config] as VideoEncoderConfiguration;
  final connection = call.namedArguments[#connection] as RtcConnection;
  expect(connection.channelId, 'room');
  expect(connection.localUid, localUid);
  expect(config.dimensions?.width, target.width);
  expect(config.dimensions?.height, target.height);
  expect(config.frameRate, target.frameRate);
  expect(config.minBitrate, target.minimumBitrate);
  expect(config.bitrate, target.maximumBitrate);
  expect(config.degradationPreference, switch (target.encoderPreference) {
    RealtimeVideoEncoderPreference.maintainFramerate =>
      DegradationPreference.maintainFramerate,
    RealtimeVideoEncoderPreference.maintainQuality =>
      DegradationPreference.maintainQuality,
    _ => DegradationPreference.maintainAuto,
  });
}

RtcManager _manager(_Platform platform) => RtcManager(
  engineManager: RtcEngineManager.internal(createEngine: () async => platform),
);

class _Platform extends AgoraRtcPlatform {
  _Platform() : this._(_Engine());

  _Platform._(super.engine);

  @override
  _Engine get engine => super.engine as _Engine;
  int destroyCount = 0;

  @override
  Future<void> destroy() async {
    destroyCount++;
    await super.destroy();
  }
}

class _Engine implements RtcEngineEx {
  bool rejectAudioStart = false;
  bool rejectAudioStop = false;
  final media = _MediaEngine();
  @override
  MediaEngine getMediaEngine() => media;
  final calls = <Invocation>[];
  final handlers = <RtcEngineEventHandler>{};
  final leaveRequested = Completer<void>();
  int previewStarts = 0;
  int previewStops = 0;
  int captureConfigurations = 0;
  int joinCount = 0;
  int leaveCount = 0;
  bool localVideoEnabled = false;
  final localVideoChanges = <bool>[];
  bool cameraPublished = false;
  bool autoCompleteLeave = false;
  bool rejectJoin = false;
  bool rejectEncoding = false;
  int assignedLocalUid = 1;

  void completeLeave([String roomID = 'room', int? localUid]) {
    for (final handler in handlers.toList()) {
      handler.onLeaveChannel?.call(
        RtcConnection(
          channelId: roomID,
          localUid: localUid ?? assignedLocalUid,
        ),
        const RtcStats(),
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation call) {
    calls.add(call);
    switch (call.memberName) {
      case #enableLocalAudio:
        final enabled = call.positionalArguments.single as bool;
        if (enabled ? rejectAudioStart : rejectAudioStop) {
          return Future<void>.error(
            AgoraRtcException(code: -2, message: 'audio rejected'),
          );
        }
      case #joinChannelWithUserAccount:
      case #leaveChannel:
      case #createDataStream:
      case #sendStreamMessage:
      case #updateChannelMediaOptions:
      case #muteRemoteVideoStream:
      case #muteRemoteAudioStream:
      case #adjustUserPlaybackSignalVolume:
      case #getUserInfoByUserAccount:
        throw StateError('Unexpected unscoped RTC call: ${call.memberName}');
      case #registerEventHandler:
        handlers.add(call.positionalArguments.single as RtcEngineEventHandler);
        return null;
      case #unregisterEventHandler:
        handlers.remove(call.positionalArguments.single);
        return null;
      case #joinChannelWithUserAccountEx:
        joinCount++;
        if (rejectJoin) return Future<void>.error(StateError('join rejected'));
        for (final handler in handlers.toList()) {
          handler.onJoinChannelSuccess?.call(
            RtcConnection(channelId: 'room', localUid: assignedLocalUid),
            0,
          );
        }
      case #createDataStreamEx:
        return Future<int>.value(1);
      case #setVideoEncoderConfigurationEx:
        if (rejectEncoding) {
          return Future<void>.error(
            AgoraRtcException(code: -2, message: 'encoder rejected'),
          );
        }
      case #getUserInfoByUserAccountEx:
        return Future<UserInfo>.value(
          const UserInfo(uid: 7, userAccount: 'bot'),
        );
      case #leaveChannelWithUserAccountEx:
        leaveCount++;
        if (!leaveRequested.isCompleted) leaveRequested.complete();
        if (autoCompleteLeave) completeLeave();
      case #startPreview:
        previewStarts++;
      case #stopPreview:
        previewStops++;
      case #enableLocalVideo:
        localVideoEnabled = call.positionalArguments.single as bool;
        localVideoChanges.add(localVideoEnabled);
      case #setCameraCapturerConfiguration:
        captureConfigurations++;
      case #updateChannelMediaOptionsEx:
        final options = call.namedArguments[#options] as ChannelMediaOptions;
        cameraPublished = options.publishCameraTrack ?? cameraPublished;
    }
    return Future<void>.value();
  }
}

class _MediaEngine implements MediaEngine {
  AudioFrame? lastAudio;
  AudioTrackConfig? audioConfiguration;
  int audioPackets = 0, videoPackets = 0;
  final destroyedTracks = <int>[];
  @override
  Future<void> setExternalVideoSource({
    required bool enabled,
    required bool useTexture,
    ExternalVideoSourceType sourceType = ExternalVideoSourceType.videoFrame,
    SenderOptions encodedVideoOption = const SenderOptions(),
  }) async {}
  @override
  Future<int> createCustomAudioTrack({
    required AudioTrackType trackType,
    required AudioTrackConfig config,
  }) async {
    audioConfiguration = config;
    return 12;
  }

  @override
  Future<void> destroyCustomAudioTrack(int trackId) async =>
      destroyedTracks.add(trackId);
  @override
  Future<void> pushVideoFrame({
    required ExternalVideoFrame frame,
    int videoTrackId = 0,
  }) async {
    videoPackets++;
  }

  @override
  Future<void> pushAudioFrame({
    required AudioFrame frame,
    int trackId = 0,
  }) async {
    lastAudio = frame;
    audioPackets++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected native media call: ${invocation.memberName}',
  );
}
