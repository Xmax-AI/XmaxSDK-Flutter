//
//  RoomCommandController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:math';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/tasks/OperationCancellation.dart';

/// Commands with service receipts and a bounded background retry schedule.
enum RoomCommandKind {

  /// Starts a generation task.
  start,

  /// Updates generation conditions.
  changeCondition,

  /// Updates returned video dimensions.
  changeTargetSize;

  /// The service event name used in signaling logs.
  String get event => switch (this) {
    start => 'start',
    changeCondition => 'change_condition',
    changeTargetSize => 'change_target_size',
  };
}

/// Retries logical commands independently of transport completion and generation readiness.
final class RoomCommandController {

  /// Creates a scheduler for independently cancellable transport attempts.
  ///
  /// Parameters:
  /// - [sendMessage]: The transport for an individual command attempt.
  /// - [retryEnabled]: Whether to retry commands until acknowledged or the deadline expires.
  RoomCommandController({
    required this.sendMessage,
    bool retryEnabled = true,
  }) : _retryEnabled = retryEnabled;

  /// Submits frozen signaling with cancellation scoped to one transport attempt.
  final Future<void> Function(
    String message,
    Future<void> cancellation,
  ) sendMessage;

  /// Whether commands use the background retry schedule.
  final bool _retryEnabled;

  /// Commands retained until receipt, deadline, or explicit cancellation.
  final Map<String, _Command> _pending = {};

  /// Orders initial sends without waiting for receipts or retry deadlines.
  Future<void>? _sendTail;

  /// Whether this room lifetime permanently rejects new commands.
  bool _closed = false;

  /// Freezes a new command and returns its first successful complete transport submission.
  ///
  /// Receipts stop retries without completing this future. Initial transport failure rejects
  /// the future unless another attempt has already succeeded. Retry expiry only stops retries.
  ///
  /// Parameters:
  /// - [kind]: The command category; a new start supersedes every pending command.
  /// - [taskID]: The generation task owning this command.
  /// - [createMessage]: Serializes once using the identifier shared by every attempt.
  /// - [ensureCurrent]: Rejects obsolete operations before their first successful submission.
  Future<void> send({
    required RoomCommandKind kind,
    required String taskID,
    required String Function(
      String xid,
    ) createMessage,
    void Function()? ensureCurrent,
  }) {
    if (_closed) {
      throw OperationCancellation.error;
    }

    ensureCurrent?.call();
    final xid = _createXID();
    final message = createMessage(xid);

    for (final command in _pending.values.toList()) {
      if (kind == RoomCommandKind.start ||
          (command.kind == kind && command.taskID == taskID)) {
        _cancel(command);
      }
    }

    final command = _Command(
      kind,
      taskID,
      xid,
      message,
      ensureCurrent,
    );
    _pending[xid] = command;
    final previous = _sendTail;

    // Retain earlier barriers even when an intermediate queued command is superseded.
    _sendTail = () async {
      await previous;
      if (!command.cancelled) {
        _begin(command);
      }
      await command.done.future.onError((
        _,
        _,
      ) {});
    }();

    return command.done.future;
  }

  /// Stops redundant sends for a valid service receipt without confirming generation readiness.
  ///
  /// Parameters:
  /// - [xid]: The logical command identifier returned by the service.
  /// - [count]: The positive service receipt count, limited to a JSON-safe integer.
  void acknowledge({
    required String xid,
    required int count,
  }) {
    final command = _pending[xid];
    if (count <= 0 || count > 9007199254740991 || command == null ||
        !command.retrying || command.attempts == 0) {
      return;
    }

    try {
      if (!command.sent) {
        command.ensureCurrent?.call();
      }
      XmaxLogger.info(
        category: XmaxLoggerCategory.room,
        message: '接收房间信令 (Inbound Room Signaling)\n'
            '├─ ${XmaxLogger.localized('类型：', 'Type: ')}xid_ack\n'
            '├─ ${XmaxLogger.localized('命令：', 'Command: ')}${command.kind.event}\n'
            '├─ xid: $xid\n'
            '├─ count: $count\n'
            '└─ ${XmaxLogger.localized('发送次数：', 'Attempts: ')}${command.attempts}',
      );
      _stopRetries(command);
    } catch (error) {
      _cancel(
        command,
        error,
      );
    }
  }

  /// Cancels an ended task, or every room command when [taskID] is omitted.
  void cancel({
    String? taskID,
  }) {
    for (final command in _pending.values.toList()) {
      if (taskID == null || command.taskID == taskID) {
        _cancel(command);
      }
    }
    if (taskID == null) {
      _sendTail = null;
    }
  }

  /// Permanently invalidates this scheduler before the native room can be reused.
  void close() {
    _closed = true;
    cancel();
  }

  /// Starts [command] and schedules retries when enabled.
  void _begin(
    _Command command,
  ) {
    if (_retryEnabled) {
      _scheduleRetries(command);
    }

    _attempt(
      command,
      true,
    );
  }

  /// Schedules two send rounds and the six-second receipt deadline for [command].
  void _scheduleRetries(
    _Command command,
  ) {
    for (final offset in [300, 1000, 3000, 3300, 4000, 6000]) {
      command.timers.add(Timer(
        Duration(milliseconds: offset),
        () {
          if (command.cancelled || !command.retrying) {
            return;
          }
          if (offset == 6000) {
            final detail = XmaxLogger.localized(
              'RTC 命令 6000 ms 内未收到 ACK，停止重发',
              'RTC command ACK not received after 6000 ms; retries stopped',
            );
            XmaxLogger.warn(
              category: XmaxLoggerCategory.room,
              message: '$detail: ${command.kind.event}, xid: ${command.xid}',
            );
            _stopRetries(command);
          } else {
            _attempt(
              command,
              false,
            );
          }
        },
      ));
    }
  }

  /// Submits [command], retaining cancellation until the [initial] or redundant attempt settles.
  void _attempt(
    _Command command,
    bool initial,
  ) {
    if (command.cancelled || !command.retrying) {
      return;
    }
    try {
      if (!command.sent) {
        command.ensureCurrent?.call();
      }
    } catch (error) {
      _cancel(
        command,
        error,
      );
      return;
    }

    final attempt = _Attempt(initial);
    command.transports.add(attempt);
    command.attempts += 1;
    unawaited(() async {
      try {
        await sendMessage(
          command.message,
          attempt.cancellation.future,
        );
        if (!command.cancelled) {
          command.sent = true;
          if (!command.done.isCompleted) {
            command.done.complete();
          }
          if (!_retryEnabled || !command.retrying) {
            _pending.remove(command.xid);
          }
        }
      } catch (error) {
        if (command.cancelled) {
          return;
        }
        if (initial && !command.sent) {
          if (command.kind == RoomCommandKind.start) {
            for (final dependent in _pending.values.toList()) {
              if (dependent != command && dependent.taskID == command.taskID) {
                _cancel(dependent);
              }
            }
          }
          _cancel(
            command,
            error,
          );
        } else if (command.retrying &&
            XmaxError.from(error).code != XmaxErrorCode.cancelled) {
          final detail = XmaxLogger.localized(
            'RTC 命令重发失败',
            'RTC command retry send failed',
          );
          XmaxLogger.warn(
            category: XmaxLoggerCategory.room,
            message: '$detail: ${command.kind.event}, xid: ${command.xid}',
          );
        }
      } finally {
        command.transports.remove(attempt);
      }
    }());
  }

  /// Stops redundant work while preserving an unresolved original submission for [command].
  void _stopRetries(
    _Command command,
  ) {
    command.retrying = false;
    for (final timer in command.timers) {
      timer.cancel();
    }
    command.timers.clear();
    for (final attempt in command.transports) {
      if (!attempt.initial || command.sent) {
        attempt.cancel();
      }
    }
    if (command.sent) {
      _pending.remove(command.xid);
    }
  }

  /// Invalidates [command], cancels every attempt, and preserves an optional initial [error].
  void _cancel(
    _Command command, [
    Object? error,
  ]) {
    command.cancelled = true;
    _stopRetries(command);
    for (final attempt in command.transports) {
      attempt.cancel();
    }
    if (!command.done.isCompleted) {
      command.done.completeError(XmaxError.from(error ?? OperationCancellation.error));
    }
    _pending.remove(command.xid);
  }

  /// Creates a random UUID shared by all attempts of one logical command.
  static String _createXID() {
    final random = Random.secure();
    final bytes = List.generate(
      16,
      (
        _,
      ) => random.nextInt(256),
    );
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((
      value,
    ) => value.toRadixString(16).padLeft(
      2,
      '0',
    )).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// One frozen logical command and its independently managed transport attempts.
final class _Command {

  /// Creates pending command state and observes cancellation before callers await its result.
  _Command(
    this.kind,
    this.taskID,
    this.xid,
    this.message,
    this.ensureCurrent,
  ) {
    done.future.ignore();
  }

  /// The logical generation operation.
  final RoomCommandKind kind;

  /// The generation task owning this command.
  final String taskID;

  /// The identifier shared by the original and every redundant attempt.
  final String xid;

  /// The immutable serialized payload retained until cancellation or receipt.
  final String message;

  /// Rejects obsolete configuration until its first successful submission.
  final void Function()? ensureCurrent;

  /// The caller-visible result independent of the receipt deadline.
  final Completer<void> done = Completer<void>();

  /// The redundant-send timers and final deadline.
  final List<Timer> timers = [];

  /// Native attempts retained so queued fragments can be cancelled.
  final Set<_Attempt> transports = {};

  /// The number of attempts submitted to the transport.
  int attempts = 0;

  /// Whether further redundant attempts may be submitted.
  bool retrying = true;

  /// Whether any complete attempt has succeeded.
  bool sent = false;

  /// Whether a lifecycle or supersession boundary invalidated the command.
  bool cancelled = false;
}

/// A native submission with cancellation scoped to its remaining packets.
final class _Attempt {

  /// Creates an original or redundant transport attempt.
  _Attempt(
    this.initial,
  );

  /// Whether this attempt is the original submission preserved after an early receipt.
  final bool initial;

  /// The signal cancelling queued or partially submitted fragments.
  final Completer<void> cancellation = Completer<void>();

  /// Requests cancellation once without waiting for a native packet already in flight.
  void cancel() {
    if (!cancellation.isCompleted) {
      cancellation.complete();
    }
  }
}
