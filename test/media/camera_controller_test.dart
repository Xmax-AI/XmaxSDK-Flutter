import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/media/camera/CameraPosition.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/permissions/PermissionManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcQualityListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RoomJoinConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/src/media/camera/CameraController.dart';
import 'package:xmax_sdk/src/media/MediaController.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderBinding.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderRegistry.dart';
import 'package:xmax_sdk/src/service/media/MediaServicing.dart';
import 'package:xmax_sdk/src/service/media/MediaService.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoFormat.dart';
import 'package:xmax_sdk/xmax_sdk.dart' show RealtimeModel;
import 'package:xmax_sdk/src/service/media/RealtimeMediaSource.dart';

void main() {
  test(
    'format updates retain the track and render binding without restarting capture',
    () async {
      final rtc = _FakeRtc();
      final camera = CameraController(
        rtcManager: rtc,
        permissionManager: const _AllowedPermissions(),
      );
      final initial = RealtimeModel.x2_1_1_preview_cn.defaultCameraVideoFormat;
      final stream = await camera.createLocalCameraStream(
        videoFormat: initial,
        position: CameraPosition.front,
      );
      final track = stream.videoTrack!;
      final handle = VideoRenderRegistry.handleFor(track);
      final target = initial.resized(width: 1920, height: 1024);
      await camera.updateVideoFormat(target);
      expect(camera.currentTrack, same(track));
      expect(track.videoFormat, target);
      expect(VideoRenderRegistry.handleFor(track), same(handle));
      expect(rtc.captureStarts, 1);
      expect(rtc.captureStops, 0);
      expect(rtc.lastCaptureSize, const Size(1920, 1024));
      rtc.formatError = StateError('native configuration rejected');
      await expectLater(camera.updateVideoFormat(initial), throwsStateError);
      expect(track.videoFormat, target);
      await expectLater(
        camera.updateVideoFormat(initial.resized(width: 800, height: 800)),
        throwsA(isA<XmaxError>()),
      );
      expect(track.videoFormat, target);
      await camera.stopLocalCameraStream();
    },
  );

  test(
    'capture stop failure still destroys engine and clears source ownership',
    () async {
      final rtc = _FakeRtc();
      final camera = CameraController(
        rtcManager: rtc,
        permissionManager: const _AllowedPermissions(),
        mediaService: const _IdentityMediaService(),
      );
      final media = MediaController(
        rtcManager: rtc,
        cameraController: camera,
        interactionListener: (_, _) async {},
      );
      const format = RealtimeVideoFormat(width: 832, height: 1472, fps: 30);
      final local = await media.createLocalCameraStream(
        videoFormat: format,
        position: CameraPosition.front,
      );
      rtc.stopError = StateError('capture stop failed');
      rtc.destroyError = StateError('engine destroy failed');
      await media.stopLocalStream();
      expect(rtc.destroyCount, 1);
      expect(media.currentTrack, isNull);
      expect(media.owns(local), isFalse);
      expect(VideoRenderRegistry.handleFor(local.videoTrack!), isNull);
      rtc.stopError = null;
      rtc.destroyError = null;
      await media.createLocalCameraStream(
        videoFormat: format,
        position: CameraPosition.front,
      );
      await media.stopLocalStream();
      expect(rtc.destroyCount, 2);
    },
  );

  test('preview listener survives an RTC destroy and camera restart', () async {
    final rtc = _FakeRtc();
    final camera = CameraController(
      rtcManager: rtc,
      permissionManager: const _AllowedPermissions(),
      mediaService: const _IdentityMediaService(),
    );
    var readyCount = 0;
    camera.setPreviewReadyListener(() => readyCount += 1);

    await camera.createLocalCameraStream(
      videoFormat: const RealtimeVideoFormat(width: 832, height: 1472, fps: 24),
      position: CameraPosition.front,
    );
    rtc.notifyPreviewReady();
    expect(readyCount, 0);
    _attachPreview(camera);
    expect(readyCount, 1);

    await camera.stopLocalCameraStream();
    await rtc.destroy();
    expect(rtc.previewReadyListener, isNull);

    await camera.createLocalCameraStream(
      videoFormat: const RealtimeVideoFormat(width: 832, height: 1472, fps: 24),
      position: CameraPosition.front,
    );
    _attachPreview(camera);
    expect(readyCount, 1);
    rtc.notifyPreviewReady();

    expect(readyCount, 2);
    await camera.stopLocalCameraStream();
  });

  test(
    'stale capture and preview callbacks cannot ready a new camera',
    () async {
      final rtc = _FakeRtc();
      final camera = CameraController(
        rtcManager: rtc,
        permissionManager: const _AllowedPermissions(),
        mediaService: const _IdentityMediaService(),
      );
      var readyCount = 0;
      camera.setPreviewReadyListener(() => readyCount += 1);

      await camera.createLocalCameraStream(
        videoFormat: const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 30,
        ),
        position: CameraPosition.front,
      );
      final oldCapture = rtc.previewReadyListener;
      final oldBinding =
          VideoRenderRegistry.handleFor(camera.currentTrack!)!.value
              as LocalVideoRenderBinding;
      await camera.stopLocalCameraStream();

      await camera.createLocalCameraStream(
        videoFormat: const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 30,
        ),
        position: CameraPosition.front,
      );
      oldCapture?.call();
      oldBinding.onPreviewAttached?.call();
      expect(readyCount, 0);

      rtc.notifyPreviewReady();
      _attachPreview(camera);
      expect(readyCount, 1);
      _attachPreview(camera);
      expect(readyCount, 1);
      await camera.stopLocalCameraStream();
    },
  );

  test(
    'camera switch normalizes RTC failures and preserves position',
    () async {
      final rtc = _FakeRtc();
      final camera = CameraController(
        rtcManager: rtc,
        permissionManager: const _AllowedPermissions(),
        mediaService: const _IdentityMediaService(),
      );
      final stream = await camera.createLocalCameraStream(
        videoFormat: const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 24,
        ),
        position: CameraPosition.front,
      );
      rtc.switchError = StateError('native switch failed');

      await expectLater(
        camera.switchCamera(),
        throwsA(
          isA<XmaxError>().having(
            (error) => error.code,
            'code',
            XmaxErrorCode.internalError,
          ),
        ),
      );
      expect(stream.videoTrack?.position, CameraPosition.front);
    },
  );

  test('preview model camera preserves its bucket and 30 fps', () async {
    final rtc = _FakeRtc();
    final camera = CameraController(
      rtcManager: rtc,
      permissionManager: const _AllowedPermissions(),
      mediaService: MediaService(model: RealtimeModel.x2_1_1_preview_cn),
    );
    final format = RealtimeModel.x2_1_1_preview_cn.defaultCameraVideoFormat;

    final stream = await camera.createLocalCameraStream(
      videoFormat: format,
      position: CameraPosition.front,
    );

    expect(stream.videoTrack?.videoFormat, format);
    expect(rtc.lastCaptureSize, const Size(1024, 1920));
    expect(rtc.lastCaptureFrameRate, 30);
    await camera.stopLocalCameraStream();
  });

  test('preview model camera rejects an unsupported input size', () async {
    final rtc = _FakeRtc();
    final camera = CameraController(
      rtcManager: rtc,
      permissionManager: const _AllowedPermissions(),
      mediaService: MediaService(model: RealtimeModel.x2_1_1_preview_cn),
    );

    await expectLater(
      camera.createLocalCameraStream(
        videoFormat: const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 24,
        ),
        position: CameraPosition.front,
      ),
      throwsA(
        isA<XmaxError>().having(
          (error) => error.code,
          'code',
          XmaxErrorCode.invalidConfiguration,
        ),
      ),
    );
    expect(rtc.lastCaptureSize, isNull);
  });

  test(
    'camera resize preserves bitrate bounds and encoder preference',
    () async {
      final rtc = _FakeRtc();
      final camera = CameraController(
        rtcManager: rtc,
        permissionManager: const _AllowedPermissions(),
        mediaService: const _ResizingMediaService(),
      );

      final stream = await camera.createLocalCameraStream(
        videoFormat: const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 30,
          minimumBitrate: 900,
          maximumBitrate: 3000,
          encoderPreference: RealtimeVideoEncoderPreference.maintainFramerate,
        ),
        position: CameraPosition.front,
      );

      expect(
        stream.videoTrack?.videoFormat,
        const RealtimeVideoFormat(
          width: 800,
          height: 1408,
          fps: 30,
          minimumBitrate: 900,
          maximumBitrate: 3000,
          encoderPreference: RealtimeVideoEncoderPreference.maintainFramerate,
        ),
      );
      await camera.stopLocalCameraStream();
    },
  );
}

void _attachPreview(CameraController camera) {
  final binding =
      VideoRenderRegistry.handleFor(camera.currentTrack!)!.value
          as LocalVideoRenderBinding;
  binding.onPreviewAttached?.call();
}

final class _AllowedPermissions implements PermissionManaging {
  const _AllowedPermissions();

  @override
  Future<void> ensureCameraPermission() async {}

  @override
  Future<void> ensureMicrophonePermission() async {}
}

final class _IdentityMediaService implements MediaServicing {
  const _IdentityMediaService();

  @override
  RealtimeModel get model => RealtimeModel.x2_1_1_preview_cn;

  @override
  Size resolveMediaSize(Size size, {required RealtimeMediaSource source}) =>
      size;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ResizingMediaService implements MediaServicing {
  const _ResizingMediaService();

  @override
  RealtimeModel get model => RealtimeModel.x2_1_1_preview_cn;

  @override
  Size resolveMediaSize(Size size, {required RealtimeMediaSource source}) =>
      const Size(800, 1408);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeRtc implements RtcManaging {
  int captureStarts = 0;
  int captureStops = 0;
  Object? formatError;

  @override
  Future<void> updateVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) async {
    if (formatError case final error?) throw error;
    lastCaptureSize = Size(width.toDouble(), height.toDouble());
    lastCaptureFrameRate = frameRate;
  }

  Object? stopError;
  Object? destroyError;
  int destroyCount = 0;
  void Function()? previewReadyListener;
  Object? switchError;
  Size? lastCaptureSize;
  int? lastCaptureFrameRate;

  void notifyPreviewReady() => previewReadyListener?.call();

  @override
  Future<void> destroy() async {
    destroyCount++;
    previewReadyListener = null;
    if (destroyError case final error?) throw error;
  }

  @override
  void setCameraPreviewReadyListener(void Function()? listener) {
    previewReadyListener = listener;
  }

  @override
  Future<void> initialize({Future<void>? cancellation}) async {}

  @override
  void setQualityListener(RtcQualityListener? listener) {}

  @override
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  ) async {}

  @override
  Future<void> joinRoom({required RoomJoinConfiguration configuration}) async {}

  @override
  Future<void> leaveRoom() async {}

  @override
  Future<void> publishLocalVideo({required bool publish}) async {}

  @override
  Future<void> sendRoomMessage(String message) async {}

  @override
  void setEventListener(RtcEventListener? listener) {}

  @override
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String streamID,
  }) async {}

  @override
  Future<void> startVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  }) async {
    captureStarts++;
    lastCaptureSize = Size(width.toDouble(), height.toDouble());
    lastCaptureFrameRate = frameRate;
  }

  @override
  Future<void> stopVideoCapture() async {
    captureStops++;
    if (stopError case final error?) throw error;
  }

  @override
  Future<void> subscribeRemoteAudio({
    required String streamID,
    required bool subscribe,
  }) async {}

  @override
  Future<void> subscribeRemoteVideo({
    required String streamID,
    required bool subscribe,
  }) async {}

  @override
  Future<void> switchCamera({required CameraPosition position}) async {
    final error = switchError;
    if (error != null) throw error;
  }
}
