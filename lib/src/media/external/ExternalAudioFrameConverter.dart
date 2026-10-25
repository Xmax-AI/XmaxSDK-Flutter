//
//  ExternalAudioFrameConverter.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/media/audio/RealtimeExternalAudioFrame.dart';

/// Converts a contiguous external PCM stream to timestamped 48 kHz mono packets.
final class ExternalAudioFrameConverter {

  /// The fixed input rate, channel count, and sample representation for this binding.
  (int, int, RealtimeExternalAudioSampleFormat)? _format;

  /// The next expected source timestamp, in microseconds.
  double? _nextInputTime;

  /// The segment's monotonic origin, in microseconds.
  int _anchor = 0;

  /// The mono samples retained for streaming interpolation.
  final List<double> _samples = [];

  /// The absolute source index of the first retained sample.
  int _sampleBase = 0;

  /// The number of converted samples in this segment.
  int _outputSamples = 0;

  /// Less than one 10 ms packet of converted PCM samples.
  final List<int> _pending = [];

  /// Validates and converts an audio buffer, preserving resampling state between calls.
  ///
  /// Parameters:
  /// - [frame]: Interleaved PCM with the binding's unchanged input format.
  /// - [timestamp]: The first source sample's monotonic presentation time.
  /// - [emit]: The receiver for 960-byte PCM16 packets and their first-sample timestamps.
  void append(
    RealtimeExternalAudioFrame frame, {
    required Duration timestamp,
    required void Function(
      Uint8List data,
      Duration timestamp,
    ) emit,
  }) {
    if (timestamp.isNegative) {
      return;
    }

    final bytes = frame.sampleFormat == RealtimeExternalAudioSampleFormat.pcm16 ? 2 : 4;
    final stride = bytes * frame.channels;
    if (frame.sampleRate <= 0 || frame.sampleRate > 384000 ||
        frame.channels <= 0 || frame.channels > 32 ||
        frame.data.isEmpty || frame.data.length % stride != 0) {
      throw _error('External audio requires complete interleaved PCM samples');
    }
    final format = (frame.sampleRate, frame.channels, frame.sampleFormat);
    if (_format != null && _format != format) {
      throw _error('External PCM format cannot change during a binding');
    }
    _format = format;

    final time = timestamp.inMicroseconds;
    final expected = _nextInputTime;
    final tolerance = 500000 / frame.sampleRate;
    if (expected != null && time < expected - tolerance) {
      return;
    }
    if (expected == null || time > expected + tolerance) {
      _anchor = time;
      _sampleBase = 0;
      _outputSamples = 0;
      _samples.clear();
      _pending.clear();
    }

    final input = ByteData.sublistView(frame.data);
    final count = frame.data.length ~/ stride;
    for (var sample = 0; sample < count; sample += 1) {
      var mono = 0.0;
      for (var channel = 0; channel < frame.channels; channel += 1) {
        final offset = sample * stride + channel * bytes;
        final value = bytes == 2
            ? input.getInt16(
              offset,
              Endian.little,
            ) / 32768
            : input.getFloat32(
              offset,
              Endian.little,
            );
        if (!value.isFinite) {
          throw _error('External PCM samples must be finite');
        }
        mono += value;
      }
      _samples.add(mono / frame.channels);
    }

    while (true) {
      final numerator = _outputSamples * frame.sampleRate;
      final sourceIndex = numerator ~/ 48000;
      final fraction = numerator % 48000;
      final index = sourceIndex - _sampleBase;
      if (index >= _samples.length ||
          (fraction != 0 && index + 1 >= _samples.length)) {
        break;
      }
      final left = _samples[index];
      final right = fraction == 0 ? left : _samples[index + 1];
      final value = left + (right - left) * fraction / 48000;
      _pending.add((value * 32768).round().clamp(
        -32768,
        32767,
      ));
      _outputSamples += 1;

      if (_pending.length == 480) {
        final data = ByteData(960);
        for (var index = 0; index < 480; index += 1) {
          data.setInt16(
            index * 2,
            _pending[index],
            Endian.little,
          );
        }
        emit(
          data.buffer.asUint8List(),
          Duration(microseconds: _anchor + (_outputSamples - 480) * 1000000 ~/ 48000),
        );
        _pending.clear();
      }
    }

    final nextIndex = _outputSamples * frame.sampleRate ~/ 48000;
    final discard = (nextIndex - _sampleBase).clamp(
      0,
      _samples.length,
    );
    if (discard > 0) {
      _samples.removeRange(
        0,
        discard,
      );
      _sampleBase += discard;
    }
    _nextInputTime = time + count * 1000000 / frame.sampleRate;
  }

  /// Creates a source-format or PCM conversion failure.
  ///
  /// [message] describes the invalid source input.
  ///
  /// Returns a media error suitable for the binding's failure handler.
  static XmaxError _error(
    String message,
  ) => XmaxError(
    code: XmaxErrorCode.mediaError,
    message: message,
  );
}
