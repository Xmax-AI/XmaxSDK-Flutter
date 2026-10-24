import 'dart:async';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcEventListener.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionConnection.dart';
import 'package:xmax_sdk/src/stream/StreamController.dart';
import 'package:xmax_sdk/src/stream/room/RoomControlling.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

const _remote = RemoteStream(roomID: 'room', userID: 'bot', streamID: 'bot');
const _format = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30);
Future<void> _settle() => Future<void>.delayed(Duration.zero);
Future<StreamController> _controller(
  _Rtc rtc, {
  _Room? room,
  void Function(RemoteStream?)? render,
  void Function(RemoteStream)? ready,
  void Function(Object)? error,
  Duration generationTimeout = const Duration(seconds: 1),
}) async {
  final stream = StreamController(
    rtcManager: rtc,
    roomController: room ?? _Room(),
    remoteStreamListener: render,
    remoteFrameReadyListener: ready,
    errorListener: error,
    generationTimeout: generationTimeout,
  );
  await stream.connect(
    connection: const RealtimeSessionConnection(
      roomID: 'room',
      userID: 'user',
      token: 'token',
      botName: 'bot',
    ),
    ensureActive: () {},
  );
  return stream;
}

void main() {
  test(
    'quality preparation leaves encoder and returned dimensions to Core',
    () async {
      final rtc = _Rtc();
      final stream = await _controller(rtc);
      addTearDown(stream.disconnect);
      await stream.prepareQuality(
        baseline: _format,
        model: 'preview',
        isAdaptiveQualityEnabled: false,
      );
      expect(stream.qualityConfiguration!.uplinkLevel, RealtimeQualityLevel.l1);
      expect(rtc.configurations, isEmpty);
    },
  );

  test(
    'internal and public network listeners receive independent samples',
    () async {
      final rtc = _Rtc();
      final actual = await _controller(rtc);
      addTearDown(actual.disconnect);
      final observed = <RealtimeNetworkQuality>[],
          internal = <RealtimeNetworkQuality>[];
      actual.setNetworkQualityListener(observed.add);
      actual.setAdaptiveQualityListener((value, time) {
        expect(time, greaterThanOrEqualTo(0));
        internal.add(value);
      });
      const sample = RealtimeNetworkQuality(
        uplink: RealtimeNetworkQualityLevel.bad,
        downlink: RealtimeNetworkQualityLevel.good,
      );
      rtc.listener!.onNetworkQuality!(sample);
      expect(observed, [sample]);
      expect(internal, [sample]);
      actual.setAdaptiveQualityListener(null);
      rtc.listener!.onNetworkQuality!(sample);
      expect(observed, hasLength(2));
      expect(internal, hasLength(1));
    },
  );

  test(
    'operation cancellation interrupts a pending generation signaling wait',
    () async {
      final rtc = _Rtc(), room = _Room()..startGate = Completer<void>();
      final stream = await _controller(rtc, room: room);
      addTearDown(stream.disconnect);
      final cancelled = Completer<void>();
      final pending = stream.beginGeneration(
        taskID: 'task',
        videoFormat: _format,
        context: RealtimeContext(prompt: 'a'),
        cancellation: cancelled.future,
      );
      final rejected = expectLater(
        pending,
        throwsA(
          isA<XmaxError>().having(
            (e) => e.code,
            'code',
            XmaxErrorCode.cancelled,
          ),
        ),
      );
      await _settle();
      cancelled.complete();
      await rejected;
      room.startGate!.complete();
      rtc.listener!.onRemoteVideoPublished!(_remote, true);
      await _settle();
      expect(stream.hasGenerationTask, isFalse);
    },
  );

  test('generation deadline includes a pending signaling send', () async {
    final rtc = _Rtc(), room = _Room()..startGate = Completer<void>();
    final rendered = <RemoteStream?>[];
    final stream = await _controller(
      rtc,
      room: room,
      render: rendered.add,
      generationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(stream.disconnect);
    await expectLater(
      stream.beginGeneration(
        taskID: 'task',
        videoFormat: _format,
        context: RealtimeContext(prompt: 'a'),
      ),
      throwsA(
        isA<XmaxError>().having((e) => e.code, 'code', XmaxErrorCode.timeout),
      ),
    );
    room.startGate!.complete();
    rtc.listener!.onRemoteVideoPublished!(_remote, true);
    await _settle();
    expect(rendered.whereType<RemoteStream>(), isEmpty);
    expect(stream.hasGenerationTask, false);
  });
  test('published video waits for completed start signaling', () async {
    final rtc = _Rtc(), room = _Room()..startGate = Completer<void>();
    final rendered = <RemoteStream?>[];
    final stream = await _controller(rtc, room: room, render: rendered.add);
    addTearDown(stream.disconnect);
    final pending = stream.beginGeneration(
      taskID: 'task',
      videoFormat: _format,
      context: RealtimeContext(prompt: 'animate'),
    );
    rtc.listener!.onRemoteVideoPublished!(_remote, true);
    await _settle();
    expect(rendered, isEmpty);
    room.startGate!.complete();
    final generation = await pending;
    await generation.value;
    expect(rendered, [_remote]);
  });
  for (final early in [true, false]) {
    test(
      'decoded frame is retained around publication confirmation (early=$early)',
      () async {
        final rtc = _Rtc();
        final ready = <RemoteStream>[];
        final stream = await _controller(rtc, ready: ready.add);
        addTearDown(stream.disconnect);
        if (early) rtc.listener!.onFirstRemoteVideoFrameDecoded!(_remote);
        final generation = await stream.beginGeneration(
          taskID: 'task',
          videoFormat: _format,
          context: RealtimeContext(prompt: 'animate'),
        );
        rtc.listener!.onRemoteVideoPublished!(_remote, true);
        await generation.value;
        if (!early) {
          expect(ready, isEmpty);
          rtc.listener!.onFirstRemoteVideoFrameDecoded!(_remote);
        }
        expect(ready, [_remote]);
        await stream.stopGeneration(taskID: 'task');
        rtc.listener!.onRemoteVideoPublished!(_remote, false);
        ready.clear();
        final next = await stream.beginGeneration(
          taskID: 'next',
          videoFormat: _format,
          context: RealtimeContext(prompt: 'next'),
        );
        rtc.listener!.onRemoteVideoPublished!(_remote, true);
        await next.value;
        expect(ready, isEmpty);
      },
    );
  }
  test('unrelated room or publisher cannot confirm a generation', () async {
    final rtc = _Rtc();
    final rendered = <RemoteStream?>[];
    final stream = await _controller(rtc, render: rendered.add);
    addTearDown(stream.disconnect);
    final generation = await stream.beginGeneration(
      taskID: 'task?os=flutter-ios',
      videoFormat: _format,
      context: RealtimeContext(prompt: 'a'),
    );
    rtc.listener!.onRemoteVideoPublished!(
      const RemoteStream(roomID: 'other', userID: 'bot', streamID: 'bot'),
      true,
    );
    rtc.listener!.onRemoteVideoPublished!(
      const RemoteStream(roomID: 'room', userID: 'other', streamID: 'other'),
      true,
    );
    await _settle();
    expect(rendered, isEmpty);
    rtc.listener!.onRemoteVideoPublished!(_remote, true);
    await generation.value;
    expect(rendered, [_remote]);
  });
  test('cancelled confirmation cannot bind a late result', () async {
    final rtc = _Rtc();
    final rendered = <RemoteStream?>[];
    final stream = await _controller(rtc, render: rendered.add);
    addTearDown(stream.disconnect);
    final generation = await stream.beginGeneration(
      taskID: 'old',
      videoFormat: _format,
      context: RealtimeContext(prompt: 'a'),
    );
    final cancelled = expectLater(generation.value, throwsA(isA<XmaxError>()));
    generation.cancel();
    await cancelled;
    await stream.stopGeneration(taskID: 'old');
    rendered.clear();
    rtc.listener!.onRemoteVideoPublished!(_remote, true);
    await _settle();
    expect(rendered, isEmpty);
    final next = await stream.beginGeneration(
      taskID: 'new',
      videoFormat: _format,
      context: RealtimeContext(prompt: 'b'),
    );
    await next.value;
    expect(rendered, [_remote]);
  });
  test(
    'audio applies saved volume before subscription and retains it on failed writes',
    () async {
      final rtc = _Rtc();
      final stream = await _controller(rtc);
      addTearDown(stream.disconnect);
      await stream.setRemoteAudioVolume(0.634);
      rtc.listener!.onRemoteAudioPublished!(_remote, true);
      final generation = await stream.beginGeneration(
        taskID: 'task',
        videoFormat: _format,
        context: RealtimeContext(prompt: 'a'),
      );
      rtc.listener!.onRemoteVideoPublished!(_remote, true);
      await generation.value;
      expect(rtc.audioSubscriptions, isEmpty);
      await stream.activateRemoteAudio();
      expect(rtc.audioVolumes.last, 63);
      expect(rtc.audioSubscriptions, [true]);
      rtc.volumeError = StateError('volume failed');
      await expectLater(stream.setRemoteAudioVolume(.8), throwsStateError);
      expect(stream.remoteAudioVolume, .63);
      rtc.volumeError = null;
      await stream.stopGeneration(taskID: 'task');
      expect(rtc.audioSubscriptions.last, false);
    },
  );
  test(
    'audio activation finishing after stop unsubscribes the stale stream',
    () async {
      final rtc = _Rtc();
      final stream = await _controller(rtc);
      addTearDown(stream.disconnect);
      rtc.listener!.onRemoteAudioPublished!(_remote, true);
      final generation = await stream.beginGeneration(
        taskID: 'task',
        videoFormat: _format,
        context: RealtimeContext(prompt: 'a'),
      );
      rtc.listener!.onRemoteVideoPublished!(_remote, true);
      await generation.value;
      rtc.audioGate = Completer<void>();
      final activation = expectLater(
        stream.activateRemoteAudio(),
        throwsA(isA<XmaxError>()),
      );
      await _settle();
      await stream.stopGeneration(taskID: 'task');
      rtc.audioGate!.complete();
      await activation;
      expect(rtc.audioSubscriptions.last, false);
    },
  );
  test('subscription failure rejects pending generation once', () async {
    final rtc = _Rtc()..videoError = StateError('subscribe failed');
    final errors = <Object>[];
    final stream = await _controller(rtc, error: errors.add);
    addTearDown(stream.disconnect);
    final generation = await stream.beginGeneration(
      taskID: 'task',
      videoFormat: _format,
      context: RealtimeContext(prompt: 'a'),
    );
    final failure = expectLater(generation.value, throwsA(isA<XmaxError>()));
    rtc.listener!.onRemoteVideoPublished!(_remote, true);
    await failure;
    expect(errors, isEmpty);
  });
  test('send failure does not emit an unobserved completer error', () async {
    final stream = await _controller(
      _Rtc(),
      room: _Room()..startError = StateError('send failed'),
    );
    addTearDown(stream.disconnect);
    await expectLater(
      stream.beginGeneration(
        taskID: 'task',
        videoFormat: _format,
        context: RealtimeContext(prompt: 'a'),
      ),
      throwsStateError,
    );
    await _settle();
    expect(stream.hasGenerationTask, isFalse);
  });
  test(
    'statistics filter unrelated users and clear on stop and disconnect',
    () async {
      final rtc = _Rtc();
      final stream = await _controller(rtc);
      addTearDown(stream.disconnect);
      final up = <UplinkVideoStatistics?>[],
          down = <DownlinkVideoStatistics?>[];
      stream.setUplinkVideoStatisticsListener(up.add);
      stream.setDownlinkVideoStatisticsListener(down.add);
      rtc.listener!.onUplinkVideoStatistics!(
        const UplinkVideoStatistics(bitrateKbps: 123),
      );
      expect(up.single?.bitrateKbps, 123);
      rtc.listener!.onDownlinkVideoStatistics!(
        const DownlinkVideoStatistics(userID: 'other'),
      );
      expect(down, isEmpty);
      final generation = await stream.beginGeneration(
        taskID: 'task',
        videoFormat: _format,
        context: RealtimeContext(prompt: 'a'),
      );
      rtc.listener!.onRemoteVideoPublished!(_remote, true);
      await generation.value;
      rtc.listener!.onDownlinkVideoStatistics!(
        const DownlinkVideoStatistics(userID: 'bot', renderFrameRate: 24),
      );
      expect(down.last?.renderFrameRate, 24);
      await stream.stopGeneration(taskID: 'task');
      expect(down.last, isNull);
      await stream.disconnect();
      expect(up.last, isNull);
    },
  );
}

class _Rtc implements RtcManaging {
  Object? encodingError;
  final configurations = <VideoEncodingConfiguration>[];
  @override
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  ) async {
    if (encodingError case final error?) throw error;
    configurations.add(configuration);
  }

  RtcEventListener? listener;
  Object? volumeError, videoError;
  Completer<void>? audioGate;
  final audioSubscriptions = <bool>[], audioVolumes = <int>[];
  @override
  void setEventListener(RtcEventListener? listener) => this.listener = listener;
  @override
  Future<void> subscribeRemoteVideo({
    required String streamID,
    required bool subscribe,
  }) async {
    if (subscribe && videoError != null) throw videoError!;
  }

  @override
  Future<void> subscribeRemoteAudio({
    required String streamID,
    required bool subscribe,
  }) async {
    audioSubscriptions.add(subscribe);
    if (subscribe) await audioGate?.future;
  }

  @override
  Future<void> setRemoteAudioVolume({
    required String streamID,
    required int volume,
  }) async {
    if (volumeError != null) throw volumeError!;
    audioVolumes.add(volume);
  }

  @override
  dynamic noSuchMethod(Invocation call) => Future<void>.value();
}

class _Room implements RoomControlling {
  bool? startPadding, conditionPadding;
  Object? targetError;
  Completer<void>? targetGate;
  final targetStarted = Completer<void>();
  Size? conditionTarget;
  @override
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  }) async {
    ensureActive();
    if (targetError case final error?) throw error;
    if (!targetStarted.isCompleted) targetStarted.complete();
    await targetGate?.future;
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
    conditionTarget = targetSize;
    conditionPadding = paddingContain;
  }

  Completer<void>? startGate;
  Object? startError;
  @override
  Future<void> startGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool paddingContain = false,
  }) async {
    if (startError != null) throw startError!;
    startPadding = paddingContain;
    await startGate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation call) => Future<void>.value();
}
