//
//  RealtimeExternalVideoSource.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../foundation/media/video/RealtimeExternalVideoFrame.dart';
import '../../foundation/media/audio/RealtimeExternalAudioFrame.dart';

/// Supplies video captured, decoded, or processed by your app, with optional PCM audio.
///
/// Your app owns permissions, capture devices, players, and their disposal. Source lifecycle
/// and sink calls run on the manager's isolate. Native producers must marshal frames to it.
abstract class RealtimeExternalVideoSource {

  /// The source dimensions, frame rate, and encoding settings, fixed until delivery stops.
  RealtimeVideoFormat get videoFormat;

  /// Whether the source supplies PCM audio; disabled by default.
  ///
  /// Audio and video must share one monotonic timeline. Submitted audio is not played locally.
  bool get hasAudio => false;

  /// Starts frame delivery without waiting for generation or the first frame.
  ///
  /// Continue delivering frames while disconnected to keep preview running.
  /// Orient and mirror pixels before submission, and pace delivery using [videoFormat].
  /// Failed or cancelled startup is followed by [stop].
  ///
  /// [sink] receives frames for this attachment only.
  Future<void> start({
    required RealtimeExternalFrameSink sink,
  });

  /// Ends frame delivery and releases the sink reference.
  ///
  /// Must be safe to call repeatedly. Your app decides when to dispose its devices and players.
  Future<void> stop();
}

/// Receives frames for one external source attachment.
///
/// Calls after detachment or source failure are ignored. Submission futures provide backpressure;
/// await them before submitting more data of the same media kind.
abstract interface class RealtimeExternalFrameSink {

  /// The model-bounded, four-pixel-aligned format used for encoding and quality baselines.
  ///
  /// Submit the original source dimensions; transport scales frames to the resolved format.
  RealtimeVideoFormat get videoFormat;

  /// Whether frames are accepted, including during disconnected local preview.
  bool get isRequestingFrames;

  /// Submits upright BGRA or video-range NV12 pixels for preview and generation.
  ///
  /// The buffer is copied before this call returns. Negative, duplicate, or decreasing
  /// timestamps are ignored. A busy sink drops video input rather than accumulating frames.
  ///
  /// Parameters:
  /// - [frame]: Pixels matching the source's declared dimensions.
  /// - [timestamp]: A nonnegative, strictly increasing monotonic presentation time.
  Future<void> pushVideo(
    RealtimeExternalVideoFrame frame, {
    required Duration timestamp,
  });

  /// Converts interleaved PCM to 48 kHz mono PCM16 in 10 ms packets for RTC upload.
  ///
  /// Requires the source's hasAudio opt-in. No local playback or reconnection backlog is created.
  /// Concurrent audio submissions are ignored; await each submission before sending another.
  /// Input format must remain fixed. Overlapping or negative timestamps are ignored;
  /// a gap starts a new segment without inserting silence. Buffers are copied before returning.
  ///
  /// Parameters:
  /// - [frame]: Ready, uncompressed PCM samples.
  /// - [timestamp]: The first sample's presentation time on the video's monotonic timeline.
  Future<void> pushAudio(
    RealtimeExternalAudioFrame frame, {
    required Duration timestamp,
  });

  /// Reports an unrecoverable source failure, ending the connection and local stream.
  ///
  /// [error] describes the capture, decoding, or processing failure.
  void reportError(
    Object error,
  );
}
