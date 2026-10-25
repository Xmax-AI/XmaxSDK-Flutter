//
//  RealtimeMediaFrameDispatcher.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import '../../service/realtime/RealtimeMediaFrame.dart';
import 'RemoteAudioTimeline.dart';

/// Serializes bounded media delivery without blocking transport or video rendering.
final class RealtimeMediaFrameDispatcher {

  /// Creates a bounded output queue.
  RealtimeMediaFrameDispatcher({
    this.maximumPendingFrames = 256,
    this.maximumPendingBytes = 32 * 1024 * 1024,
  });

  /// The packet limit, including the callback currently running.
  final int maximumPendingFrames;

  /// The media byte limit, including the callback currently running.
  final int maximumPendingBytes;

  /// The current application callback.
  RealtimeMediaFrameListener? _listener;

  /// The token for the current result binding.
  String? _streamID;

  /// The revision rejecting queued packets from previous listeners.
  int _version = 0;

  /// The sample-based PCM timeline.
  final _audioTimeline = RemoteAudioTimeline();

  /// Pending callbacks and their listener revisions.
  final _queue = ListQueue<(int, RealtimeMediaFrame)>();

  /// The number of retained packets across revisions.
  int _pendingFrames = 0;

  /// The retained media bytes across revisions.
  int _pendingBytes = 0;

  /// Whether one serial delivery loop is active.
  bool _draining = false;

  /// Whether the next audio event must report a gap.
  bool _audioDiscontinuous = true;

  /// Whether the next video event must report a gap.
  bool _videoDiscontinuous = true;

  /// The previous video presentation time.
  Duration? _lastVideoPTS;

  /// The previous video dimensions and rotation.
  (int, int, int)? _videoFormat;

  /// Whether an application requests media output.
  bool get hasListener => _listener != null;

  /// The current stream token, or null while unbound.
  String? get streamID => _streamID;

  /// Replaces the listener and discards its queued output.
  ///
  /// [listener] is the serial callback, or null to stop delivery immediately.
  void setListener(
    RealtimeMediaFrameListener? listener,
  ) {
    _listener = listener;
    _reset();
  }

  /// Starts a new result binding and invalidates old producers.
  ///
  /// [active] indicates whether a result stream is bound.
  ///
  /// Returns the new opaque stream identity, or null when unbound.
  String? setStream(
    bool active,
  ) {
    final random = Random.secure();
    _streamID = active ? List.generate(
      16,
      (
        _,
      ) => random.nextInt(256).toRadixString(16).padLeft(
        2,
        '0',
      ),
    ).join() : null;
    _reset();
    return _streamID;
  }

  /// Normalizes and admits one current producer's owned packet.
  ///
  /// Parameters:
  /// - [content]: The copied PCM or decoded video payload.
  /// - [streamID]: The token captured when the producer was attached.
  void dispatch(
    RealtimeMediaFrameContent content, {
    required String streamID,
  }) {
    if (_listener == null || streamID != _streamID) {
      return;
    }

    final bool discontinuous;
    if (content is RealtimeAudioFrame) {
      final resolved = _audioTimeline.resolve(content);
      if (resolved == null) {
        _audioDiscontinuous = true;
        return;
      }
      content = resolved.$1;
      discontinuous = _audioDiscontinuous || resolved.$2;
    } else if (content is RealtimeVideoFrame) {
      final format = (content.width, content.height, content.rotation);
      discontinuous = _videoDiscontinuous ||
          (_lastVideoPTS != null && content.presentationTimeStamp <= _lastVideoPTS!) ||
          (_videoFormat != null && _videoFormat != format);
      _lastVideoPTS = content.presentationTimeStamp;
      _videoFormat = format;
    } else {
      return;
    }

    final accepted = _pendingFrames < maximumPendingFrames &&
        content.byteLength <= maximumPendingBytes - _pendingBytes;
    if (content is RealtimeAudioFrame) {
      _audioDiscontinuous = !accepted;
    } else {
      _videoDiscontinuous = !accepted;
    }
    if (!accepted) {
      return;
    }

    _queue.add((
      _version,
      RealtimeMediaFrame(
        streamID: streamID,
        isDiscontinuous: discontinuous,
        content: content,
      ),
    ));
    _pendingFrames++;
    _pendingBytes += content.byteLength;
    if (!_draining) {
      _draining = true;
      Timer.run(_drain);
    }
  }

  /// Invalidates queued work and resets continuity without cancelling an active callback.
  void _reset() {
    _version++;
    for (final (_, frame) in _queue) {
      _pendingFrames--;
      _pendingBytes -= frame.content.byteLength;
    }
    _queue.clear();
    _audioTimeline.reset();
    _audioDiscontinuous = true;
    _videoDiscontinuous = true;
    _lastVideoPTS = null;
    _videoFormat = null;
  }

  /// Delivers packets serially, isolating application failures and yielding between batches.
  Future<void> _drain() async {
    var delivered = 0;
    while (_queue.isNotEmpty) {
      final (version, frame) = _queue.removeFirst();
      try {
        final listener = _listener;
        if (version == _version && frame.streamID == _streamID && listener != null) {
          await listener(frame);
        }
      } catch (_) {
        // Application observers must not interrupt RTC or later packet delivery.
      } finally {
        _pendingFrames--;
        _pendingBytes -= frame.content.byteLength;
      }
      if (++delivered % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    _draining = false;
  }
}
