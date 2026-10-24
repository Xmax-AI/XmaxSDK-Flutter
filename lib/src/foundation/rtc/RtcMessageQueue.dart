//
//  RtcMessageQueue.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../errors/XmaxError.dart';

/// Encodes UTF-8 room signaling as one packet or server-reassemblable fragments.
abstract final class RtcMessageCodec {

  /// Encodes complete UTF-8 signaling, rejecting messages beyond the size limits.
  ///
  /// Parameters:
  /// - [message]: The complete UTF-8 room message to encode.
  ///
  /// Returns ordered packets with fragment metadata required for reassembly.
  static List<Uint8List> encode(
    String message,
  ) {
    final bytes = utf8.encode(message);

    if (bytes.isEmpty || bytes.length > 256 * 1024) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'RTC room message must contain between 1 and 262144 bytes',
      );
    }

    if (bytes.length <= 800) {
      return [bytes];
    }

    final chunks = <String>[];
    var chunk = StringBuffer();
    var length = 0;

    for (final rune in message.runes) {
      final scalar = String.fromCharCode(rune);
      final encodedLength = utf8.encode(jsonEncode(scalar)).length - 2;

      if (length + encodedLength > 600) {
        chunks.add(chunk.toString());
        chunk = StringBuffer();
        length = 0;
      }

      chunk.write(scalar);
      length += encodedLength;
    }

    if (chunk.isNotEmpty) {
      chunks.add(chunk.toString());
    }

    if (chunks.length > 512) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'RTC room message contains too many fragments',
      );
    }

    final random = Random.secure();
    final id = List.generate(
      16,
      (
        _,
      ) => random.nextInt(256).toRadixString(16).padLeft(
        2,
        '0',
      ),
    ).join();

    return [
      for (var index = 0; index < chunks.length; index++)
        utf8.encode(
          jsonEncode({
            'event': '__agora_chunk__',
            'eventId': id,
            'index': index,
            'count': chunks.length,
            'data': chunks[index],
          }),
        ),
    ];
  }
}

/// Serializes signaling, coalesces pending trajectories, and retains DataStream quota headroom.
final class RtcMessageQueue {

  /// Creates a serial signaling queue and starts its rate-limit clock.
  ///
  /// Parameters:
  /// - [send]: The function submitting one encoded packet.
  /// - [onFailure]: The callback for reportable send failures.
  /// - [now]: The monotonic elapsed time provider; defaults to the internal stopwatch.
  /// - [delay]: The rate-limit delay function; defaults to Future.delayed.
  RtcMessageQueue({
    required this.send,
    this.onFailure,
    Duration Function()? now,
    Future<void> Function(
      Duration,
    )?
    delay,
  }) : _clock = Stopwatch()..start(),
       _now = now,
       _delay = delay ?? Future<void>.delayed;

  /// The function that submits an encoded packet to RTC.
  final Future<void> Function(
    Uint8List packet,
  )
  send;

  /// The operation failure handler.
  final void Function(
    Object error,
  )?
  onFailure;

  /// The monotonic clock used to measure elapsed time.
  final Stopwatch _clock;

  /// The rate-limit clock provider, or null to use the internal stopwatch.
  final Duration Function()? _now;

  /// The function used to wait for sending quota.
  final Future<void> Function(
    Duration,
  )
  _delay;

  /// The signaling messages that have not started sending.
  final _pending = <_Message>[];

  /// The send times and byte counts within the one-second sliding window.
  final _window = <(Duration, int)>[];

  /// Whether the queue is closed and rejects new messages.
  bool _closed = false;

  /// Whether the queue is actively draining.
  bool _draining = false;

  /// The active message and its complete fragment set.
  _Message? _active;

  /// The transport error preventing later control messages from sending.
  Object? _fatalError;

  /// The notification used to interrupt rate-limit waits when the queue closes.
  Completer<void>? _wake;

  /// The monotonic elapsed time used for rate limiting.
  Duration get _time => _now?.call() ?? _clock.elapsed;

  /// Enqueues a complete message, replacing pending content with the same coalescing key.
  ///
  /// Completes after all fragments send, or with an error if discarded, closed, or failed.
  ///
  /// Parameters:
  /// - [message]: The complete UTF-8 room message to submit.
  /// - [replacingPendingMessage]: The coalescing key; null queues independently, otherwise only the
  ///   latest pending content is retained.
  /// - [reportFailure]: Whether failures fault the queue; false rejects only this operation.
  Future<void> enqueue(
    String message, {
    String? replacingPendingMessage,
    bool reportFailure = true,
  }) {
    if (_closed) {
      return Future.error(_cancelled);
    }

    final packets = RtcMessageCodec.encode(message);

    if (replacingPendingMessage != null) {
      for (final pending in _pending) {
        if (pending.key == replacingPendingMessage) {
          pending.packets = packets;

          return pending.done.future;
        }
      }
    }

    if (_pending.length + (_draining ? 1 : 0) >= 64) {
      return Future.error(
        const XmaxError(
          code: XmaxErrorCode.rtcError,
          message: 'RTC room message queue is full',
        ),
      );
    }

    final pending = _Message(
      packets,
      replacingPendingMessage,
      reportFailure,
    );

    _pending.add(pending);
    if (!_draining) {
      unawaited(_drain());
    }

    return pending.done.future;
  }

  /// Discards pending coalescible messages without affecting control messages or sent fragments.
  ///
  /// Parameters:
  /// - [key]: The coalescing key to clear; omitting it discards all pending coalescible messages.
  void discardPendingMessages({
    String? key,
  }) {
    final removed = _pending
        .where(
          (
            entry,
          ) => entry.key != null && (key == null || entry.key == key),
        )
        .toList();

    _pending.removeWhere(removed.contains);
    for (final entry in removed) {
      // Discarding stale trajectories for new conditions is not a transport failure; control messages retain order.
      if (!entry.done.isCompleted) {
        entry.done.complete();
      }
    }
  }

  /// Closes the queue and rejects unfinished sends with a cancellation error.
  void close() {
    _closed = true;
    for (final entry in _pending) {
      if (!entry.done.isCompleted) {
        entry.done.completeError(_cancelled);
      }
    }

    _pending.clear();

    final active = _active;

    if (active != null && !active.done.isCompleted) {
      active.done.completeError(_cancelled);
    }

    if (_wake case final wake? when !wake.isCompleted) {
      wake.complete();
    }
  }

  /// Waits until the one-second packet and byte budgets permit sending.
  ///
  /// Parameters:
  /// - [length]: The next packet's byte count.
  Future<void> _waitForBudget(
    int length,
  ) async {
    while (true) {
      if (_closed) {
        throw _cancelled;
      }

      final now = _time;

      _window.removeWhere(
        (
          entry,
        ) => now - entry.$1 >= const Duration(seconds: 1),
      );

      final bytes = _window.fold(
        0,
        (
          total,
          entry,
        ) => total + entry.$2,
      );

      if (_window.length < 58 && bytes + length <= 29000) {
        return;
      }

      final wake = Completer<void>();

      _wake = wake;
      await Future.any([
        _delay(const Duration(seconds: 1) - (now - _window.first.$1)),
        wake.future,
      ]);
      if (identical(
        _wake,
        wake,
      )) {
        _wake = null;
      }
    }
  }

  /// Drains messages in order and completes each send result independently.
  Future<void> _drain() async {
    _draining = true;

    try {
      while (_pending.isNotEmpty && !_closed) {
        // Keeps pending content replaceable while waiting for sending quota.
        final entry = _pending.first;

        try {
          if (_fatalError != null) {
            throw _fatalError!;
          }

          await _waitForBudget(entry.packets.first.length);
          if (!_pending.contains(entry)) {
            continue;
          }

          final packets = entry.packets;

          _pending.remove(entry);
          _active = entry;
          for (final packet in packets) {
            await _waitForBudget(packet.length);
            await send(packet);
            if (_closed) {
              throw _cancelled;
            }

            _window.add((_time, packet.length));
          }

          if (!entry.done.isCompleted) {
            entry.done.complete();
          }
        } catch (error, stack) {
          _pending.remove(entry);
          if (!entry.done.isCompleted) {
            entry.done.completeError(
              error,
              stack,
            );
          }

          if (!_closed && entry.reportFailure) {
            _fatalError = error;
            onFailure?.call(error);
          }
        } finally {
          if (identical(
            _active,
            entry,
          )) {
            _active = null;
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// The operation was cancelled.
  static const _cancelled = XmaxError(
    code: XmaxErrorCode.cancelled,
    message: 'RTC room message cancelled',
  );
}

/// A pending signaling message with fragments, a coalescing key, and a send result.
final class _Message {

  /// Creates a pending message and handles errors before a caller begins awaiting it.
  ///
  /// Parameters:
  /// - [packets]: The packets in send order.
  /// - [key]: The key used to replace a matching pending message.
  /// - [reportFailure]: Whether a send failure faults the queue.
  _Message(
    this.packets,
    this.key,
    this.reportFailure,
  ) {
    done.future.ignore();
  }

  /// The ordered packets belonging to this message.
  List<Uint8List> packets;

  /// The coalescing key used to replace matching pending content.
  final String? key;

  /// Whether send failure reports a connection fault; false rejects only this call.
  final bool reportFailure;

  /// The completer for the message send result.
  final done = Completer<void>();
}
