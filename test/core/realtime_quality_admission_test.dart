import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeConnectionManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeErrorManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeGenerationManager.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeManager.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/src/media/MediaControlling.dart';
import 'package:xmax_sdk/src/render/RenderControlling.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSession.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionConnection.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeTiming.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeMediaStream.dart';
import 'package:xmax_sdk/src/stream/StreamController.dart';
import 'package:xmax_sdk/src/stream/room/RoomControlling.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

final _cancelled = isA<XmaxError>().having(
  (e) => e.code,
  'code',
  XmaxErrorCode.cancelled,
);
final _conflict = isA<XmaxError>().having(
  (e) => e.code,
  'code',
  XmaxErrorCode.invalidConfiguration,
);
const _remote = RemoteStream(roomID: 'room', userID: 'bot', streamID: 'bot');
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({}),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test(
    'disabled adaptation retains public samples and manual directional controls',
    () async {
      final d = _Fixture(adaptive: false);
      addTearDown(d.manager.close);
      await d.start();
      expect(await d.manager.uplinkQualityLevel, RealtimeQualityLevel.l1);
      final observed = <RealtimeNetworkQuality>[];
      await d.manager.setNetworkQualityListener(observed.add);
      final writes = d.rtc.formats.length;
      await d.poorSamples();
      expect(observed, hasLength(3));
      expect(d.rtc.formats, hasLength(writes));
      expect(d.room.targetWrites, 0);

      await d.manager.setUplinkQualityLevel(RealtimeQualityLevel.l5);
      final format = d.rtc.formats.last;
      expect((format.width, format.height, format.frameRate), (512, 960, 16));
      await d.manager.setDownlinkQualityLevel(RealtimeQualityLevel.l5);
      expect(d.connection.currentTargetSize, const Size(512, 960));
      expect(
        d.stream.qualityConfiguration!.baseline,
        d.media.currentVideoFormat,
      );
      await d.manager.startGeneration(
        context: RealtimeContext(prompt: 'updated'),
      );
      expect(d.room.conditions, 1);
      expect(d.room.conditionTarget, isNull);
      expect(d.room.starts, 1);
    },
  );

  test(
    'automatic directional adjustments use Core sizing without changing capture',
    () async {
      final d = _Fixture();
      addTearDown(d.manager.close);
      await d.start();
      expect(d.connection.currentTargetSize, const Size(896, 1680));
      final track = d.connection.currentRemoteStream!.videoTrack!;
      expect(
        (track.videoFormat!.width, track.videoFormat!.height),
        (896, 1680),
      );
      final baseline = d.media.currentVideoFormat;
      await d.poorSamples();
      expect(await d.manager.uplinkQualityLevel, RealtimeQualityLevel.l3);
      expect(await d.manager.downlinkQualityLevel, RealtimeQualityLevel.l3);
      expect(d.connection.currentTargetSize, const Size(768, 1440));
      expect(d.connection.currentRemoteStream!.videoTrack, same(track));
      expect(
        (track.videoFormat!.width, track.videoFormat!.height),
        (768, 1440),
      );
      expect(d.media.currentVideoFormat, baseline);
      expect(d.rtc.formats.last.width, 768);
      expect(d.room.starts, 1);
    },
  );

  test(
    'failed manual writes retain accepted levels and permit retry',
    () async {
      final d = _Fixture();
      addTearDown(d.manager.close);
      await d.start();
      d.rtc.encodingError = StateError('rejected encoder');
      await expectLater(
        d.manager.setUplinkQualityLevel(RealtimeQualityLevel.l1),
        throwsA(isA<XmaxError>()),
      );
      expect(await d.manager.uplinkQualityLevel, RealtimeQualityLevel.l2);
      d.rtc.encodingError = null;
      final previous = d.connection.currentTargetSize;
      d.room.targetError = StateError('rejected signal');
      await expectLater(
        d.manager.setDownlinkQualityLevel(RealtimeQualityLevel.l5),
        throwsA(isA<XmaxError>()),
      );
      expect(d.connection.currentTargetSize, previous);
      expect(await d.manager.downlinkQualityLevel, RealtimeQualityLevel.l2);
      d.room.targetError = null;
      await d.manager.setDownlinkQualityLevel(RealtimeQualityLevel.l5);
      expect(await d.manager.downlinkQualityLevel, RealtimeQualityLevel.l5);
      expect(
        (await d.manager.currentState).connectionState,
        RealtimeConnectionState.generating,
      );
    },
  );

  test(
    'manual configuration rejects conflicting foreground work and close waits for the write',
    () async {
      final d = _Fixture();
      await d.start();
      d.room.targetGate = Completer<void>();
      final manual = d.manager.setDownlinkQualityLevel(RealtimeQualityLevel.l5);
      final rejected = expectLater(manual, throwsA(_cancelled));
      await d.room.targetStarted.future;
      await expectLater(
        d.manager.startGeneration(context: RealtimeContext(prompt: 'conflict')),
        throwsA(_conflict),
      );
      await expectLater(
        d.manager.setUplinkQualityLevel(RealtimeQualityLevel.l1),
        throwsA(_conflict),
      );
      final closing = d.manager.close();
      await _settle();
      expect(d.sessions.closed, 0);
      expect(d.media.stops, 0);
      d.room.targetGate!.complete();
      await Future.wait([closing, rejected]);
      expect(d.sessions.closed, 1);
      expect(d.media.stops, 1);
      expect(d.connection.currentTargetSize, isNull);
      expect(d.stream.qualityConfiguration, isNull);
    },
  );

  test(
    'foreground conditions wait for admitted background adaptation',
    () async {
      final d = _Fixture();
      addTearDown(d.manager.close);
      await d.start();
      d.room.targetGate = Completer<void>();
      await d.poorSamples();
      await d.room.targetStarted.future;
      final update = d.manager.startGeneration(
        context: RealtimeContext(prompt: 'next'),
      );
      await _settle();
      expect(d.room.conditions, 0);
      d.room.targetGate!.complete();
      await update;
      expect(d.room.conditions, 1);
      expect(d.room.conditionTarget, isNull);
      expect(d.connection.currentTargetSize, const Size(768, 1440));
      expect(d.room.starts, 1);
    },
  );

  test(
    'disconnect invalidates a background target write before cleanup',
    () async {
      final d = _Fixture();
      await d.start();
      d.room.targetGate = Completer<void>();
      await d.poorSamples();
      await d.room.targetStarted.future;
      final disconnect = d.manager.disconnect();
      await _settle();
      expect(d.sessions.closed, 0);
      d.room.targetGate!.complete();
      await disconnect;
      expect(d.connection.currentTargetSize, isNull);
      expect(d.stream.qualityConfiguration, isNull);
      expect(d.media.stops, 0);
      expect(
        (await d.manager.currentState).connectionState,
        RealtimeConnectionState.ready,
      );
      await d.manager.close();
    },
  );

  test(
    'close during camera switching prevents generation restoration',
    () async {
      final d = _Fixture();
      await d.start();
      d.media.switchGate = Completer<void>();
      final switching = d.manager.switchCamera();
      final rejected = expectLater(switching, throwsA(_cancelled));
      await d.media.switchStarted.future;
      final closing = d.manager.close();
      await _settle();
      expect(d.media.stops, 0);
      d.media.switchGate!.complete();
      await Future.wait([closing, rejected]);
      expect(d.room.starts, 1);
      expect(
        (await d.manager.currentState).connectionState,
        RealtimeConnectionState.idle,
      );
    },
  );

  test('a state callback can immediately start the next operation', () async {
    final d = _Fixture();
    addTearDown(d.manager.close);
    await d.prepare();
    Future<RealtimeMediaStream?>? generation;
    await d.manager.setStateListener((state) {
      if (state.connectionState == RealtimeConnectionState.connected) {
        generation ??= d.manager.startGeneration(
          context: RealtimeContext(prompt: 'reentrant'),
        );
      }
    });
    await d.manager.connect(localStream: d.media.stream!);
    await generation;
    expect(d.room.starts, 1);
    expect(
      (await d.manager.currentState).connectionState,
      RealtimeConnectionState.generating,
    );
  });
}

class _Fixture {
  _Fixture({bool adaptive = true}) {
    room = _Room(rtc);
    stream = StreamController(
      rtcManager: rtc,
      roomController: room,
      monotonicTime: () => now,
      remoteStreamListener: render.setRemoteStream,
    );
    final timing = RealtimeTiming();
    connection = XmaxRealtimeConnectionManager(
      sessionService: sessions,
      interactionController: media,
      renderController: render,
      streamController: stream,
      timing: timing,
    );
    generation = XmaxRealtimeGenerationManager(
      interactionController: media,
      streamController: stream,
      renderController: render,
      timing: timing,
    );
    manager = XmaxRealtimeManager.internal(
      options: RealtimeConfiguration(
        model: RealtimeModel.x2_1_1_preview_cn,
        isAdaptiveQualityEnabled: adaptive,
      ),
      mediaController: media,
      streamController: stream,
      connectionManager: connection,
      generationManager: generation,
      errorManager: XmaxRealtimeErrorManager(),
    );
  }
  final rtc = _Rtc(),
      media = _Media(),
      render = _Render(),
      sessions = _Sessions();
  double now = 0;
  late final _Room room;
  late final StreamController stream;
  late final XmaxRealtimeConnectionManager connection;
  late final XmaxRealtimeGenerationManager generation;
  late final XmaxRealtimeManager manager;
  Future<void> prepare() async {
    await manager.createLocalCameraStream();
    media.preview?.call();
  }

  Future<void> start() async {
    await prepare();
    await manager.startGeneration(
      localStream: media.stream,
      context: RealtimeContext(prompt: 'initial'),
    );
  }

  Future<void> poorSamples() async {
    for (var i = 5; i <= 7; i++) {
      now = i.toDouble();
      rtc.listener!.onNetworkQuality!(
        const RealtimeNetworkQuality(
          uplink: RealtimeNetworkQualityLevel.bad,
          downlink: RealtimeNetworkQualityLevel.bad,
        ),
      );
      await _settle();
    }
    await _settle();
  }
}

class _Rtc implements RtcManaging {
  RtcEventListener? listener;
  Object? encodingError;
  final formats = <VideoEncodingConfiguration>[];
  @override
  void setEventListener(RtcEventListener? value) => listener = value;
  @override
  Future<void> configureVideoEncoding(VideoEncodingConfiguration value) async {
    if (encodingError != null) throw encodingError!;
    formats.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation call) => Future<void>.value();
}

class _Room implements RoomControlling {
  _Room(this.rtc);
  final _Rtc rtc;
  int starts = 0, conditions = 0, targetWrites = 0;
  Size? conditionTarget;
  Object? targetError;
  Completer<void>? targetGate;
  final targetStarted = Completer<void>();
  @override
  Future<void> startGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
  }) async {
    starts++;
    rtc.listener!.onRemoteVideoPublished!(_remote, true);
  }

  @override
  Future<void> changeGenerationCondition({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
  }) async {
    conditions++;
    conditionTarget = targetSize;
  }

  @override
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  }) async {
    ensureActive();
    if (!targetStarted.isCompleted) targetStarted.complete();
    await targetGate?.future;
    ensureActive();
    if (targetError != null) throw targetError!;
    targetWrites++;
  }

  @override
  dynamic noSuchMethod(Invocation call) => Future<void>.value();
}

class _Media implements MediaControlling {
  RealtimeMediaStream? stream;
  VoidCallback? preview;
  int stops = 0;
  Completer<void>? switchGate;
  final switchStarted = Completer<void>();
  @override
  RealtimeVideoTrack? get currentTrack => stream?.videoTrack;
  @override
  RealtimeVideoFormat? get currentVideoFormat => currentTrack?.videoFormat;
  @override
  bool owns(RealtimeMediaStream value) => identical(value, stream);
  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
    Future<void>? cancellation,
  }) async {
    stream = createRealtimeMediaStream(
      id: 'local',
      videoTrack: createRealtimeVideoTrack(
        id: 'camera',
        videoFormat: videoFormat,
        position: position,
      ),
    );
    return stream!;
  }

  @override
  void setCameraPreviewReadyListener(VoidCallback? value) => preview = value;
  @override
  Future<void> stopLocalStream() async {
    stops++;
    stream = null;
  }

  @override
  Future<RealtimeMediaStream> switchCamera() async {
    switchStarted.complete();
    await switchGate?.future;
    return stream!;
  }

  @override
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  }) {}
  @override
  void stopInteraction() {}
  @override
  dynamic noSuchMethod(Invocation call) => Future<void>.value();
}

class _Render implements RenderControlling {
  @override
  void setRemoteStream(RemoteStream? value) {}
  @override
  void resetRemoteTrack(RealtimeVideoTrack? value) {}
  @override
  dynamic noSuchMethod(Invocation call) => Future<void>.value();
}

class _Sessions implements RealtimeSessionServicing {
  int closed = 0;
  @override
  Future<RealtimeSession> createSession({required RealtimeModel model}) async =>
      const RealtimeSession(
        id: 'session',
        connection: RealtimeSessionConnection(
          roomID: 'room',
          userID: 'user',
          token: 'token',
          botName: 'bot',
        ),
      );
  @override
  Future<void> closeSession({required String sessionID}) async {
    closed++;
  }

  @override
  void startHeartbeat({
    required String sessionID,
    required RealtimeSessionHeartbeatFailureHandler onFailure,
  }) {}
  @override
  void stopHeartbeat() {}
}
