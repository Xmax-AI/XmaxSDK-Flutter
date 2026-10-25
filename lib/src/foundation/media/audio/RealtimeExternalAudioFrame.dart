//
//  RealtimeExternalAudioFrame.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

/// Interleaved, little-endian PCM sample representations.
enum RealtimeExternalAudioSampleFormat {

  /// Signed 16-bit integer samples.
  pcm16,

  /// Finite 32-bit floating-point samples, nominally in the range -1 to 1.
  float32,
}

/// Ready interleaved PCM samples supplied by an external source.
final class RealtimeExternalAudioFrame {

  /// Creates an audio frame referencing caller-owned samples until sink submission copies them.
  const RealtimeExternalAudioFrame({
    required this.data,
    required this.sampleRate,
    required this.channels,
    this.sampleFormat = RealtimeExternalAudioSampleFormat.pcm16,
  });

  /// The contiguous interleaved PCM samples.
  final Uint8List data;

  /// The source sample rate, in Hz, from 1 to 384000.
  final int sampleRate;

  /// The number of interleaved channels, from 1 to 32.
  final int channels;

  /// The representation of each PCM sample.
  final RealtimeExternalAudioSampleFormat sampleFormat;
}
