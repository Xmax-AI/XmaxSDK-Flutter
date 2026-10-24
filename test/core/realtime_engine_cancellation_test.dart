import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeConnectionManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeErrorManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeGenerationManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEngineManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcPlatform.dart';
import 'package:xmax_sdk/src/media/MediaController.dart';
import 'package:xmax_sdk/src/media/camera/CameraControlling.dart';
import 'package:xmax_sdk/src/render/RenderController.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeMediaStream.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';
import 'package:xmax_sdk/src/stream/StreamController.dart' as transport;
import 'package:xmax_sdk/xmax_sdk.dart';

final _cancelled = throwsA(
  isA<XmaxError>().having(
    (error) => error.code,
    'code',
    XmaxErrorCode.cancelled,
  ),
);
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'closing a queued realtime manager preserves the current camera owner and can retry',
    () async {
      final platforms = <_Platform>[];
      final pool = RtcEngineManager.internal(
        createEngine: () async {
          final platform = _Platform();
          platforms.add(platform);
          return platform;
        },
      );
      final holder = _Fixture(pool);
      final waiting = _Fixture(pool);
      addTearDown(holder.manager.close);
      addTearDown(waiting.manager.close);
      final local = await holder.manager.createLocalCameraStream();
      final rejected = expectLater(
        waiting.manager.createLocalCameraStream(),
        _cancelled,
      );
      await _settle();
      expect(
        (await waiting.manager.currentState).connectionState,
        RealtimeConnectionState.preparing,
      );
      final close = waiting.manager.close();
      await close.timeout(const Duration(seconds: 1));
      await rejected;
      expect(
        (await waiting.manager.currentState).connectionState,
        RealtimeConnectionState.idle,
      );
      expect(waiting.camera.creations, 0);
      expect(platforms, hasLength(1));
      expect(platforms.single.destroyed, 0);
      expect(holder.media.currentTrack, same(local.videoTrack));
      expect(
        (await holder.manager.currentState).connectionState,
        RealtimeConnectionState.ready,
      );

      await holder.manager.close();
      await _settle();
      expect(platforms, hasLength(1));
      await waiting.manager.createLocalCameraStream();
      expect(waiting.camera.creations, 1);
      expect(platforms, hasLength(2));
      expect(
        (await waiting.manager.currentState).connectionState,
        RealtimeConnectionState.ready,
      );
      await waiting.manager.close();
      expect(platforms.last.destroyed, 1);
    },
  );

  test(
    'close during native creation waits for cleanup without starting the camera',
    () async {
      final created = Completer<RtcPlatform>();
      final started = Completer<void>();
      final platform = _Platform();
      final pool = RtcEngineManager.internal(
        createEngine: () {
          started.complete();
          return created.future;
        },
      );
      final fixture = _Fixture(pool);
      final rejected = expectLater(
        fixture.manager.createLocalCameraStream(),
        _cancelled,
      );
      await started.future;
      var closed = false;
      final closing = fixture.manager.close().then((_) => closed = true);
      await _settle();
      expect(closed, isFalse);
      expect(fixture.camera.creations, 0);
      created.complete(platform);
      await closing.timeout(const Duration(seconds: 1));
      await rejected;
      expect(platform.destroyed, 1);
      expect(fixture.camera.creations, 0);
      expect(fixture.media.currentTrack, isNull);
      expect(
        (await fixture.manager.currentState).connectionState,
        RealtimeConnectionState.idle,
      );
    },
  );

  test(
    'media and realtime operations delegate to the camera interface without concrete capture',
    () async {
      final pool = RtcEngineManager.internal(
        createEngine: () async => _Platform(),
      );
      final fixture = _Fixture(pool);
      addTearDown(fixture.manager.close);
      final local = await fixture.manager.createLocalCameraStream();
      final track = local.videoTrack!;
      final landscape = track.videoFormat!.resized(width: 1920, height: 1024);
      await fixture.manager.updateCameraFormat(videoFormat: landscape);
      final switched = await fixture.manager.switchCamera();
      expect(fixture.camera.formats, [landscape]);
      expect(fixture.camera.switches, 1);
      expect(fixture.camera.creations, 1);
      expect(switched.videoTrack, same(track));
      expect(track.videoFormat, landscape);
      expect(track.position, CameraPosition.back);
      await fixture.manager.close();
      expect(fixture.camera.stops, 1);
      expect(fixture.media.currentTrack, isNull);
    },
  );
}

class _Fixture {
  _Fixture(RtcEngineManager pool) {
    final rtc = RtcManager(engineManager: pool);
    media = MediaController(
      rtcManager: rtc,
      cameraController: camera,
      interactionListener: (_, _) async {},
    );
    final render = RenderController();
    final stream = transport.StreamController(rtcManager: rtc);
    manager = XmaxRealtimeManager.internal(
      options: const RealtimeConfiguration(
        model: RealtimeModel.x2_1_1_preview_cn,
      ),
      mediaController: media,
      streamController: stream,
      connectionManager: XmaxRealtimeConnectionManager(
        sessionService: _UnusedSessions(),
        interactionController: media,
        renderController: render,
        streamController: stream,
      ),
      generationManager: XmaxRealtimeGenerationManager(
        interactionController: media,
        streamController: stream,
        renderController: render,
      ),
      errorManager: XmaxRealtimeErrorManager(),
    );
  }
  final camera = _Camera();
  late final MediaController media;
  late final XmaxRealtimeManager manager;
}

class _Camera implements CameraControlling {
  int creations = 0, stops = 0, switches = 0;
  final formats = <RealtimeVideoFormat>[];
  RealtimeCameraPreviewReadyListener? preview;
  RealtimeMediaStream? stream;
  @override
  RealtimeVideoTrack? get currentTrack => stream?.videoTrack;
  @override
  void setPreviewReadyListener(RealtimeCameraPreviewReadyListener? listener) {
    preview = listener;
  }

  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
  }) async {
    creations++;
    stream = createRealtimeMediaStream(
      id: 'camera',
      videoTrack: createRealtimeVideoTrack(
        id: 'local',
        videoFormat: videoFormat,
        position: position,
      ),
    );
    preview?.call();
    return stream!;
  }

  @override
  Future<void> stopLocalCameraStream() async {
    stops++;
    stream = null;
  }

  @override
  Future<RealtimeMediaStream> switchCamera() async {
    switches++;
    updateRealtimeVideoTrack(
      track: currentTrack!,
      position: CameraPosition.back,
    );
    return stream!;
  }

  @override
  Future<void> updateVideoFormat(RealtimeVideoFormat videoFormat) async {
    formats.add(videoFormat);
    updateRealtimeVideoTrack(track: currentTrack!, videoFormat: videoFormat);
  }
}

class _Platform implements RtcPlatform {
  @override
  final engine = _Engine();
  int destroyed = 0;
  @override
  Future<void> destroy() async => destroyed++;
}

class _Engine implements RtcEngineEx {
  @override
  void registerEventHandler(RtcEngineEventHandler handler) {}
  @override
  void unregisterEventHandler(RtcEngineEventHandler handler) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedSessions implements RealtimeSessionServicing {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
