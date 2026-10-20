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

/// 将 UTF-8 房间信令编码为单包或服务端可重组的分片。
abstract final class RtcMessageCodec {

  /// 将完整 UTF-8 信令转换为单包或可重组分片，超出大小限制时抛出配置错误。
  ///
  /// - [message]：待编码的完整 UTF-8 房间信令文本。
  ///
  /// 返回按发送顺序排列的完整数据包；分片包含重组所需的元数据。
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

    if (bytes.length <= 800) return [bytes];

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

    if (chunk.isNotEmpty) chunks.add(chunk.toString());

    if (chunks.length > 512) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'RTC room message contains too many fragments',
      );
    }

    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
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

/// 串行发送完整信令，合并待发轨迹，并保留 DataStream 限额余量。
final class RtcMessageQueue {

  /// 创建串行信令队列，并启动限速计时。
  ///
  /// - [send]：提交单个编码数据包的发送函数。
  /// - [onFailure]：需要上报的发送失败通知。
  /// - [now]：单调经过时长；默认使用内部 Stopwatch。
  /// - [delay]：限速等待函数；默认使用 Future.delayed。
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

  /// 将单个编码数据包提交给 RTC 的函数。
  final Future<void> Function(
    Uint8List packet,
  )
  send;

  /// 操作失败时的处理回调。
  final void Function(
    Object error,
  )?
  onFailure;

  /// 计算相对耗时的单调时钟。
  final Stopwatch _clock;

  /// 计算限速时间的函数；未指定时使用内部 Stopwatch。
  final Duration Function()? _now;

  /// 等待限速额度恢复的函数，可由调用方替换。
  final Future<void> Function(
    Duration,
  )
  _delay;

  /// 尚未开始发送的信令队列。
  final _pending = <_Message>[];

  /// 一秒滑动窗口内已发送数据包的时间及字节数。
  final _window = <(Duration, int)>[];

  /// 队列是否已关闭；关闭后拒绝新消息。
  bool _closed = false;

  /// 是否正在发送队列中的消息。
  bool _draining = false;

  /// 正在发送的消息，包含该消息的全部分片。
  _Message? _active;

  /// 阻止后续控制消息继续发送的传输错误。
  Object? _fatalError;

  /// 队列关闭时，用于提前结束限速等待的通知。
  Completer<void>? _wake;

  /// 发送限速使用的单调经过时长。
  Duration get _time => _now?.call() ?? _clock.elapsed;

  /// 串行排队发送完整信令；同键待发消息可由新内容替换。
  ///
  /// - [message]：待提交的完整 UTF-8 房间信令文本。
  /// - [replacingPendingMessage]：合并键；同键待发消息只保留最新内容，null 表示独立排队。
  /// - [reportFailure]：是否将失败上报为队列故障，默认启用；false 时仅使本次调用失败。
  ///
  /// 全部分片发送完成后结束；消息被丢弃、队列关闭或发送失败时以异常结束。
  Future<void> enqueue(
    String message, {
    String? replacingPendingMessage,
    bool reportFailure = true,
  }) {
    if (_closed) return Future.error(_cancelled);

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

    final pending = _Message(packets, replacingPendingMessage, reportFailure);

    _pending.add(pending);
    if (!_draining) unawaited(_drain());

    return pending.done.future;
  }

  /// 丢弃尚未开始发送的可合并消息，不影响控制消息及已发送的分片。
  ///
  /// - [key]：信令合并键；同键尚未发送时可以替换内容。省略时清理所有尚未发送的可合并消息。
  void discardPendingMessages({
    String? key,
  }) {
    final removed = _pending
        .where(
          (entry) => entry.key != null && (key == null || entry.key == key),
        )
        .toList();

    _pending.removeWhere(removed.contains);
    for (final entry in removed) {
      // 更新生成条件时主动丢弃旧轨迹，不算传输失败；其他控制消息仍按原顺序发送。
      if (!entry.done.isCompleted) entry.done.complete();
    }
  }

  /// 关闭发送队列，并使尚未完成的发送任务以取消错误结束。
  void close() {
    _closed = true;
    for (final entry in _pending) {
      if (!entry.done.isCompleted) entry.done.completeError(_cancelled);
    }

    _pending.clear();

    final active = _active;

    if (active != null && !active.done.isCompleted) {
      active.done.completeError(_cancelled);
    }

    if (_wake case final wake? when !wake.isCompleted) wake.complete();
  }

  /// 等待发送额度恢复，确保最近一秒内的包数和字节数不超过限制。
  ///
  /// - [length]：下一个数据包的字节数。
  Future<void> _waitForBudget(
    int length,
  ) async {
    while (true) {
      if (_closed) throw _cancelled;

      final now = _time;

      _window.removeWhere(
        (entry) => now - entry.$1 >= const Duration(seconds: 1),
      );

      final bytes = _window.fold(0, (total, entry) => total + entry.$2);

      if (_window.length < 58 && bytes + length <= 29000) return;

      final wake = Completer<void>();

      _wake = wake;
      await Future.any([
        _delay(const Duration(seconds: 1) - (now - _window.first.$1)),
        wake.future,
      ]);
      if (identical(_wake, wake)) _wake = null;
    }
  }

  /// 按顺序发送队列中的消息，并分别通知发送结果。
  Future<void> _drain() async {
    _draining = true;

    try {
      while (_pending.isNotEmpty && !_closed) {
        // 等待发送额度恢复时，保留待发消息的可替换状态。
        final entry = _pending.first;

        try {
          if (_fatalError != null) throw _fatalError!;

          await _waitForBudget(entry.packets.first.length);
          if (!_pending.contains(entry)) continue;

          final packets = entry.packets;

          _pending.remove(entry);
          _active = entry;
          for (final packet in packets) {
            await _waitForBudget(packet.length);
            await send(packet);
            if (_closed) throw _cancelled;

            _window.add((_time, packet.length));
          }

          if (!entry.done.isCompleted) entry.done.complete();
        } catch (error, stack) {
          _pending.remove(entry);
          if (!entry.done.isCompleted) entry.done.completeError(error, stack);

          if (!_closed && entry.reportFailure) {
            _fatalError = error;
            onFailure?.call(error);
          }
        } finally {
          if (identical(_active, entry)) _active = null;
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// 主动取消操作对应的 SDK 错误。
  static const _cancelled = XmaxError(
    code: XmaxErrorCode.cancelled,
    message: 'RTC room message cancelled',
  );
}

/// 一条待发信令，包含分片、合并键和发送结果。
final class _Message {

  /// 创建待发消息，并接收无人等待时产生的异常。
  ///
  /// - [packets]：按顺序发送的数据包。
  /// - [key]：消息合并键；用于替换尚未发送的同类消息。
  /// - [reportFailure]：是否将发送失败上报为队列故障。
  _Message(
    this.packets,
    this.key,
    this.reportFailure,
  ) {
    done.future.ignore();
  }

  /// 同一信令按发送顺序排列的数据包。
  List<Uint8List> packets;

  /// 信令合并键；同键尚未发送时可以替换内容。
  final String? key;

  /// 发送失败时是否上报连接故障；设为 false 时仅使本次调用失败。
  final bool reportFailure;

  /// 接收消息发送结果的完成器。
  final done = Completer<void>();
}
