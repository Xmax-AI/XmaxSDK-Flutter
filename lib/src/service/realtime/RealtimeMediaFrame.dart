//
//  RealtimeMediaFrame.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:typed_data';

/// An owned audio or video payload on the receiver rendering timeline.
sealed class RealtimeMediaFrameContent {

  /// Creates a remote media payload.
  const RealtimeMediaFrameContent();

  /// The presentation time shared by audio and video; it need not start at zero.
  Duration get presentationTimeStamp;

  /// The audio duration or suggested video duration, if known.
  Duration? get duration;

  /// The retained media size, in bytes.
  int get byteLength;
}

/// An owned packet of signed, little-endian, interleaved 16-bit remote PCM.
final class RealtimeAudioFrame extends RealtimeMediaFrameContent {

  /// Creates an owned PCM packet; treat [data] as read-only.
  const RealtimeAudioFrame({
    required this.data,
    required this.sampleRate,
    required this.channels,
    required this.samplesPerChannel,
    required this.presentationTimeStamp,
  });

  /// The copied PCM bytes, safe to retain after delivery.
  final Uint8List data;

  /// The samples per second in each channel.
  final int sampleRate;

  /// The number of interleaved channels.
  final int channels;

  /// The sample count in each channel.
  final int samplesPerChannel;

  /// The first sample's time on the receiver rendering timeline.
  @override
  final Duration presentationTimeStamp;

  /// The packet duration derived from sample count and rate.
  @override
  Duration get duration => Duration(
    microseconds: samplesPerChannel * Duration.microsecondsPerSecond ~/ sampleRate,
  );

  /// The retained PCM size, in bytes.
  @override
  int get byteLength => data.length;
}

/// An owned decoded video frame in packed, planar I420 format.
///
/// Pixels are read-only. Y is followed by U and V; each plane has tightly packed
/// rows. Chroma dimensions round up for odd source dimensions. Apply [rotation]
/// clockwise when displaying or recording the frame. No RGB conversion is performed.
final class RealtimeVideoFrame extends RealtimeMediaFrameContent {

  /// Creates an owned I420 frame.
  const RealtimeVideoFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.presentationTimeStamp,
    this.rotation = 0,
    this.duration,
  });

  /// The copied Y, U, and V planes, safe to retain after delivery.
  final Uint8List data;

  /// The unrotated pixel width.
  final int width;

  /// The unrotated pixel height.
  final int height;

  /// The clockwise display rotation: 0, 90, 180, or 270 degrees.
  final int rotation;

  /// The decoded frame's time on the receiver rendering timeline.
  @override
  final Duration presentationTimeStamp;

  /// The suggested duration, or null when not supplied by transport.
  @override
  final Duration? duration;

  /// The retained I420 size, in bytes.
  @override
  int get byteLength => data.length;
}

/// One remote audio or video packet with a shared stream identity and time basis.
///
/// Delivery order is not cross-track presentation order. Schedule both tracks by
/// their timestamps, using one recording origin. An event is not an audio/video pair.
final class RealtimeMediaFrame {

  /// Creates an output event.
  const RealtimeMediaFrame({
    required this.streamID,
    required this.isDiscontinuous,
    required this.content,
  });

  /// An opaque identity shared by both tracks for one result-stream binding.
  final String streamID;

  /// Whether this track begins a run, changes format or clock, or follows dropped output.
  final bool isDiscontinuous;

  /// The owned PCM packet or decoded I420 frame.
  final RealtimeMediaFrameContent content;

  /// The packet's presentation time on the shared receiver timeline.
  Duration get presentationTimeStamp => content.presentationTimeStamp;

  /// The audio duration or suggested video duration, if known.
  Duration? get duration => content.duration;
}

/// Receives remote media serially on the manager's isolate.
///
/// Return a future for asynchronous work to apply backpressure. Never perform
/// blocking encoding or file I/O here; move expensive work to native code or an isolate.
typedef RealtimeMediaFrameListener = FutureOr<void> Function(
  RealtimeMediaFrame frame,
);
