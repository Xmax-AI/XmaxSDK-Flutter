import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk/src/media/external/ExternalAudioFrameConverter.dart';

RealtimeExternalAudioFrame samples(
  int count, {
  int rate = 48000,
  int channels = 1,
  bool float = false,
}) {
  final bytes = ByteData(count * channels * (float ? 4 : 2));
  for (var index = 0; index < count * channels; index++) {
    if (float) {
      bytes.setFloat32(index * 4, 0.25, Endian.little);
    } else {
      bytes.setInt16(index * 2, 8192, Endian.little);
    }
  }
  return RealtimeExternalAudioFrame(
    data: bytes.buffer.asUint8List(),
    sampleRate: rate,
    channels: channels,
    sampleFormat: float
        ? RealtimeExternalAudioSampleFormat.float32
        : RealtimeExternalAudioSampleFormat.pcm16,
  );
}

void main() {
  test(
    'packetization spans buffers and timestamps originate at the first source sample',
    () {
      final converter = ExternalAudioFrameConverter();
      final output = <(Uint8List, Duration)>[];
      void emit(Uint8List data, Duration time) => output.add((data, time));
      converter.append(
        samples(240),
        timestamp: const Duration(seconds: 2),
        emit: emit,
      );
      expect(output, isEmpty);
      converter.append(
        samples(720),
        timestamp: const Duration(milliseconds: 2005),
        emit: emit,
      );
      expect(output.length, 2);
      expect(output.first.$2, const Duration(seconds: 2));
      expect(output.last.$2, const Duration(milliseconds: 2010));
      expect(
        ByteData.sublistView(output.first.$1).getInt16(0, Endian.little),
        8192,
      );
    },
  );

  test(
    'resamples stereo float PCM and carries interpolation between source buffers',
    () {
      final converter = ExternalAudioFrameConverter();
      final output = <Uint8List>[];
      for (var index = 0; index < 10; index++) {
        converter.append(
          samples(441, rate: 44100, channels: 2, float: true),
          timestamp: Duration(milliseconds: index * 10),
          emit: (data, _) => output.add(data),
        );
      }
      expect(output.length, 9);
      expect(output.every((data) => data.length == 960), isTrue);
      expect(
        ByteData.sublistView(output.last).getInt16(0, Endian.little),
        8192,
      );
    },
  );

  test(
    'overlapping timestamps are ignored; gaps discard partial packets without silence',
    () {
      final converter = ExternalAudioFrameConverter();
      final output = <Duration>[];
      void emit(Uint8List _, Duration time) => output.add(time);
      converter.append(samples(240), timestamp: Duration.zero, emit: emit);
      converter.append(samples(480), timestamp: Duration.zero, emit: emit);
      converter.append(
        samples(480),
        timestamp: const Duration(seconds: 1),
        emit: emit,
      );
      expect(output, [const Duration(seconds: 1)]);
    },
  );

  test('input format cannot change within a source attachment', () {
    final converter = ExternalAudioFrameConverter();
    converter.append(samples(480), timestamp: Duration.zero, emit: (_, _) {});
    expect(
      () => converter.append(
        samples(441, rate: 44100),
        timestamp: const Duration(milliseconds: 10),
        emit: (_, _) {},
      ),
      throwsA(isA<XmaxError>()),
    );
  });

  test(
    'invalid PCM and nonfinite samples fail while negative timestamps are ignored',
    () {
      final converter = ExternalAudioFrameConverter();
      converter.append(
        samples(480),
        timestamp: const Duration(microseconds: -1),
        emit: (_, _) => fail('Negative timestamp was emitted'),
      );
      final data = ByteData(4)..setFloat32(0, double.nan, Endian.little);
      expect(
        () => converter.append(
          RealtimeExternalAudioFrame(
            data: data.buffer.asUint8List(),
            sampleRate: 48000,
            channels: 1,
            sampleFormat: RealtimeExternalAudioSampleFormat.float32,
          ),
          timestamp: Duration.zero,
          emit: (_, _) {},
        ),
        throwsA(isA<XmaxError>()),
      );
    },
  );
}
