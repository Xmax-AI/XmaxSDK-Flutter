//
//  RemoteAudioTimeline.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeMediaFrame.dart';

/// Advances PCM by sample count while retaining its offset from the native video clock.
final class RemoteAudioTimeline {

  /// The rendering clock anchor for the current continuous sample run.
  int? _anchor;

  /// The accumulated sample count since the anchor.
  int _samples = 0;

  /// The current PCM sample rate.
  int? _rate;

  /// The current PCM channel count.
  int? _channels;

  /// Clears continuity after listener or stream replacement.
  void reset() {
    _anchor = null;
    _samples = 0;
    _rate = null;
    _channels = null;
  }

  /// Resolves sample-based time, re-anchoring on format changes or clock jumps over 100 ms.
  ///
  /// [frame] contains copied PCM and its native rendering timestamp.
  ///
  /// Returns the normalized packet and continuity flag, or null for invalid input.
  (RealtimeAudioFrame, bool)? resolve(
    RealtimeAudioFrame frame,
  ) {
    if (frame.presentationTimeStamp.inMicroseconds <= 0 ||
        frame.sampleRate < 8000 || frame.sampleRate > 192000 ||
        frame.channels < 1 || frame.channels > 2 ||
        frame.samplesPerChannel <= 0 || frame.samplesPerChannel > 192000 ||
        frame.data.length != frame.samplesPerChannel * frame.channels * 2) {
      reset();
      return null;
    }

    final native = frame.presentationTimeStamp.inMicroseconds;
    final next = _anchor == null || _rate == null
        ? native
        : _anchor! + _samples * Duration.microsecondsPerSecond ~/ _rate!;
    final discontinuous = _anchor == null ||
        _rate != frame.sampleRate || _channels != frame.channels ||
        (native - next).abs() > 100000;
    if (discontinuous) {
      _anchor = native;
      _samples = 0;
    }

    final pts = discontinuous ? native : next;
    _rate = frame.sampleRate;
    _channels = frame.channels;
    _samples += frame.samplesPerChannel;

    return (
      RealtimeAudioFrame(
        data: frame.data,
        sampleRate: frame.sampleRate,
        channels: frame.channels,
        samplesPerChannel: frame.samplesPerChannel,
        presentationTimeStamp: Duration(microseconds: pts),
      ),
      discontinuous,
    );
  }
}
