import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_video_recorder.dart';

class _Manager implements XmaxRealtimeManaging {
  RealtimeMediaFrameListener? listener;
  @override
  Future<void> setRemoteMediaFrameListener(
    RealtimeMediaFrameListener? value,
  ) async => listener = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = RealtimeVideoRecorder.channel;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'stop' ? 'saved.mp4' : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'records SDK output timestamps and detaches before saving without changing audio volume',
    () async {
      final manager = _Manager();
      final errors = <Object>[];
      var saved = 0;
      final recorder = RealtimeVideoRecorder(
        manager: manager,
        onError: errors.add,
        onSaved: () => saved++,
      );
      addTearDown(recorder.dispose);
      await recorder.toggle();
      expect(recorder.state, RealtimeRecordingState.recording);
      await manager.listener!(
        RealtimeMediaFrame(
          streamID: 'result',
          isDiscontinuous: true,
          content: RealtimeVideoFrame(
            data: Uint8List(6),
            width: 2,
            height: 2,
            presentationTimeStamp: const Duration(microseconds: 1250000),
            rotation: 90,
          ),
        ),
      );
      await manager.listener!(
        RealtimeMediaFrame(
          streamID: 'result',
          isDiscontinuous: true,
          content: RealtimeAudioFrame(
            data: Uint8List(960),
            sampleRate: 48000,
            channels: 1,
            samplesPerChannel: 480,
            presentationTimeStamp: const Duration(microseconds: 1400000),
          ),
        ),
      );
      await recorder.stop();
      expect(manager.listener, isNull);
      expect(saved, 1);
      expect(errors, isEmpty);
      expect(calls.map((call) => call.method), [
        'start',
        'append',
        'append',
        'stop',
      ]);
      final video = calls[1].arguments as Map,
          audio = calls[2].arguments as Map;
      expect(video['ptsUs'], 1250000);
      expect(video['rotation'], 90);
      expect(audio['ptsUs'], 1400000);
      expect(audio['sampleRate'], 48000);
      expect(video['id'], audio['id']);
    },
  );

  test(
    'stop during permission or preparation cancels without enabling late recording',
    () async {
      final start = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'start') await start.future;
            return null;
          });
      final manager = _Manager();
      final recorder = RealtimeVideoRecorder(
        manager: manager,
        onError: (_) => fail('unexpected failure'),
        onSaved: () => fail('unexpected save'),
      );
      addTearDown(recorder.dispose);
      final pending = recorder.toggle();
      await Future<void>.delayed(Duration.zero);
      final stopping = recorder.stop();
      start.complete();
      await pending;
      await stopping;
      expect(recorder.state, RealtimeRecordingState.idle);
      expect(manager.listener, isNull);
      expect(calls.map((call) => call.method), ['start', 'cancel']);
    },
  );

  test(
    'encoding failure removes the SDK callback and cancels native resources',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'append') {
              throw PlatformException(code: 'record.bufferFull');
            }
            return null;
          });
      final manager = _Manager(), errors = <Object>[];
      final recorder = RealtimeVideoRecorder(
        manager: manager,
        onError: errors.add,
        onSaved: () {},
      );
      addTearDown(recorder.dispose);
      await recorder.toggle();
      await manager.listener!(
        RealtimeMediaFrame(
          streamID: 'result',
          isDiscontinuous: true,
          content: RealtimeVideoFrame(
            data: Uint8List(6),
            width: 2,
            height: 2,
            presentationTimeStamp: const Duration(seconds: 1),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(recorder.state, RealtimeRecordingState.idle);
      expect(manager.listener, isNull);
      expect(errors, hasLength(1));
      expect(calls.last.method, 'cancel');
    },
  );
}
