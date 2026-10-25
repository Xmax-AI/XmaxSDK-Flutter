import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_audio_controls.dart';

void main() {
  test(
    'reads the SDK volume and restores the selected value after muting',
    () async {
      var stored = 0.63;
      final controls = RealtimeAudioControls(
        readVolume: () async => stored,
        writeVolume: (value) async => stored = value,
        onError: (error) => fail('$error'),
      );
      addTearDown(controls.dispose);
      expect(await controls.refresh(), isTrue);
      expect(controls.value, 0.63);
      await controls.toggleMute();
      expect(stored, 0);
      expect(controls.isMuted, isTrue);
      await controls.refresh();
      await controls.toggleMute();
      expect(stored, 0.63);
      expect(controls.isMuted, isFalse);
    },
  );

  test(
    'slider writes retain only the latest waiting value and run in order',
    () async {
      final gate = Completer<void>();
      final writes = <double>[];
      final controls = RealtimeAudioControls(
        readVolume: () async => 0,
        writeVolume: (value) async {
          writes.add(value);
          if (writes.length == 1) await gate.future;
        },
        onError: (error) => fail('$error'),
      );
      addTearDown(controls.dispose);
      final first = controls.setVolume(0.1);
      unawaited(controls.setVolume(0.2));
      unawaited(controls.setVolume(0.754));
      expect(controls.value, 0.75);
      expect(writes, [0.1]);
      gate.complete();
      await first;
      expect(writes, [0.1, 0.75]);
    },
  );

  test(
    'failed writes restore the last applied volume and report the failure',
    () async {
      final errors = <Object>[];
      final controls = RealtimeAudioControls(
        readVolume: () async => 0.4,
        writeVolume: (_) async => throw StateError('rejected'),
        onError: errors.add,
      );
      addTearDown(controls.dispose);
      await controls.refresh();
      await controls.setVolume(0.7);
      expect(controls.value, 0.4);
      expect(errors, hasLength(1));
    },
  );

  test(
    'source reset discards queued values and ignores stale completion errors',
    () async {
      final gate = Completer<void>();
      final errors = <Object>[];
      final writes = <double>[];
      final controls = RealtimeAudioControls(
        readVolume: () async => 0,
        writeVolume: (value) async {
          writes.add(value);
          await gate.future;
          throw StateError('old source');
        },
        onError: errors.add,
      );
      addTearDown(controls.dispose);
      final first = controls.setVolume(0.1);
      unawaited(controls.setVolume(0.9));
      controls.reset(0);
      gate.complete();
      await first;
      expect(writes, [0.1]);
      expect(controls.value, 0);
      expect(errors, isEmpty);
    },
  );

  test(
    'disposing while a read is pending does not notify or display an error',
    () async {
      final gate = Completer<double>();
      final errors = <Object>[];
      final controls = RealtimeAudioControls(
        readVolume: () => gate.future,
        writeVolume: (_) async {},
        onError: errors.add,
      );
      final refresh = controls.refresh();
      await Future<void>.delayed(Duration.zero);
      controls.dispose();
      gate.completeError(StateError('closed'));
      expect(await refresh, isFalse);
      expect(errors, isEmpty);
    },
  );
}
