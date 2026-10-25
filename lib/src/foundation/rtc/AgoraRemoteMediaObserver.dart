//
//  AgoraRemoteMediaObserver.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../service/realtime/RealtimeMediaFrame.dart';

/// Copies only one selected remote user's decoded I420 and premixing PCM.
final class AgoraRemoteMediaObserver {

  /// Creates an observer for an immutable native channel and UID binding.
  AgoraRemoteMediaObserver({
    required this.channelID,
    required this.uid,
    required this.listener,
  }) {
    video = VideoFrameObserver(onRenderVideoFrame: _video);
    audio = AudioFrameObserver(onPlaybackAudioFrameBeforeMixing: _audio);
  }

  /// The selected RTC channel.
  final String channelID;

  /// The selected result user's numeric UID.
  final int uid;

  /// The receiver for copied media on the native rendering timeline.
  final void Function(
    RealtimeMediaFrameContent content,
  ) listener;

  /// The video observer registered only while output is requested.
  late final VideoFrameObserver video;

  /// The audio observer registered only while output is requested.
  late final AudioFrameObserver audio;

  /// Whether this binding still accepts native callbacks.
  bool active = true;

  /// Copies tightly packed I420 rows without per-pixel conversion.
  void _video(
    String channel,
    int remoteUID,
    VideoFrame frame,
  ) {
    if (!active || channel != channelID || remoteUID != uid) {
      return;
    }
    final width = frame.width ?? 0;
    final height = frame.height ?? 0;
    final time = frame.renderTimeMs ?? 0;
    final rotation = frame.rotation ?? 0;
    if (width <= 0 || height <= 0 || width * height > 16777216 ||
        time <= 0 || !const [0, 90, 180, 270].contains(rotation) ||
        frame.type != VideoPixelFormat.videoPixelI420) {
      return;
    }

    final cw = (width + 1) ~/ 2;
    final ch = (height + 1) ~/ 2;
    final planes = [
      (frame.yBuffer, frame.yStride ?? width, width, height),
      (frame.uBuffer, frame.uStride ?? cw, cw, ch),
      (frame.vBuffer, frame.vStride ?? cw, cw, ch),
    ];
    for (final (buffer, stride, columns, rows) in planes) {
      if (buffer == null || stride < columns ||
          buffer.length < (rows - 1) * stride + columns) {
        return;
      }
    }

    final data = Uint8List(width * height + 2 * cw * ch);
    var offset = 0;
    for (final (buffer, stride, columns, rows) in planes) {
      for (var row = 0; row < rows; row++) {
        data.setRange(
          offset,
          offset + columns,
          buffer!,
          row * stride,
        );
        offset += columns;
      }
    }
    listener(
      RealtimeVideoFrame(
        data: data.asUnmodifiableView(),
        width: width,
        height: height,
        rotation: rotation,
        presentationTimeStamp: Duration(milliseconds: time),
      ),
    );
  }

  /// Copies PCM before mixing without changing subscriptions or playback volume.
  void _audio(
    String channel,
    int remoteUID,
    AudioFrame frame,
  ) {
    if (!active || channel != channelID || remoteUID != uid) {
      return;
    }
    final data = frame.buffer;
    final samples = frame.samplesPerChannel ?? 0;
    final channels = frame.channels ?? 0;
    final rate = frame.samplesPerSec ?? 0;
    final time = frame.renderTimeMs ?? 0;
    if (data == null || time <= 0 || samples <= 0 || samples > 192000 ||
        rate < 8000 || rate > 192000 || channels < 1 || channels > 2 ||
        frame.bytesPerSample != BytesPerSample.twoBytesPerSample ||
        data.length != samples * channels * 2) {
      return;
    }
    listener(
      RealtimeAudioFrame(
        data: Uint8List.fromList(data).asUnmodifiableView(),
        sampleRate: rate,
        channels: channels,
        samplesPerChannel: samples,
        presentationTimeStamp: Duration(milliseconds: time),
      ),
    );
  }
}
