//
//  OperationCancellation.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../errors/XmaxError.dart';

/// A scoped cancellation signal with detachable resource observers and passive waits.
final class OperationCancellation {

  /// Creates an operation bound to an optional parent cancellation signal.
  OperationCancellation({
    Future<void>? cancellation,
  }) {
    if (cancellation != null) {
      unawaited(
        cancellation.then<void>(
          (
            _,
          ) => cancel(),
          onError: (
            Object error,
            StackTrace stackTrace,
          ) => cancel(),
        ),
      );
    }
  }

  /// The error delivered when an operation accepts cancellation.
  static const error = XmaxError(
    code: XmaxErrorCode.cancelled,
    message: 'The operation was cancelled',
  );

  /// The cancellation signal forwarded to nested operations.
  final Completer<void> _signal = Completer<void>();

  /// The active resource cancellation observers.
  final Set<void Function()> _observers = {};

  /// Whether the operation has stopped accepting cancellation.
  bool _isFinished = false;

  /// Whether cancellation was accepted before completion.
  bool get isCancelled => _signal.isCompleted;

  /// Whether the operation has returned or admitted an irreversible commit.
  bool get isFinished => _isFinished;

  /// Completes when this operation accepts cancellation.
  Future<void> get signal => _signal.future;

  /// Requests cancellation once, notifying every resource observer.
  void cancel() {
    if (_isFinished || isCancelled) {
      return;
    }

    _signal.complete();
    final observers = _observers.toList();
    _observers.clear();

    for (final observer in observers) {
      try {
        observer();
      } catch (_) {
        // One resource must not prevent other resources from receiving cancellation.
      }
    }
  }

  /// Registers resource cancellation without retaining observers after their work finishes.
  ///
  /// Parameters:
  /// - [observer]: The synchronous handler that aborts an owned request or interrupts a wait.
  ///
  /// Returns a function that removes this observer.
  void Function() observe(
    void Function() observer,
  ) {
    if (isCancelled) {
      observer();
    } else if (!_isFinished) {
      _observers.add(observer);
    }

    return () {
      _observers.remove(observer);
    };
  }

  /// Rejects work after cancellation has been accepted.
  void check() {
    if (isCancelled) {
      throw error;
    }
  }

  /// Interrupts a passive wait while continuing to observe late errors.
  ///
  /// Resource-producing futures must arrange their own late cleanup. Filesystem writes and
  /// irreversible commits must settle rather than be abandoned through this method.
  ///
  /// Parameters:
  /// - [pending]: The passive operation to await.
  /// - [timeout]: The inactivity deadline for this wait, or null to wait until result or cancellation.
  ///
  /// Returns the operation result, or completes with cancellation or timeout.
  Future<T> wait<T>(
    Future<T> pending, {
    Duration? timeout,
  }) async {
    pending.ignore();
    check();

    final interrupted = Completer<T>();
    final detach = observe(() => interrupted.completeError(error));

    try {
      final result = Future.any<T>([
        pending,
        interrupted.future,
      ]);
      final value = await (timeout == null ? result : result.timeout(timeout));

      check();
      return value;
    } finally {
      detach();
    }
  }

  /// Detaches resource observers and ignores late cancellation from the parent.
  void finish() {
    _isFinished = true;
    _observers.clear();
  }
}
