//
//  RtcEngineManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../errors/XmaxError.dart';
import 'RtcPlatform.dart';
import 'AgoraRtcPlatform.dart';

/// An exclusive RTC engine lease used to verify ownership during release.
final class RtcEngineLease {

  /// Creates an exclusive RTC engine lease.
  RtcEngineLease(
    this.engine,
  );

  /// The native RTC engine in use.
  final RtcPlatform engine;

  /// The unique identifier of the engine owner.
  final Object id = Object();
}

/// Allocates exclusive RTC engine leases in request order.
final class RtcEngineManager {

  /// Creates an allocator using the native RTC engine factory.
  RtcEngineManager._() : _createEngine = _createNativeEngine;

  /// Creates an allocator with an injected engine factory.
  ///
  /// Parameters:
  /// - [createEngine]: The factory that creates initialized platform resources for each lease.
  RtcEngineManager.internal({
    required Future<RtcPlatform> Function() createEngine,
  }) : _createEngine = createEngine;

  /// The process-wide exclusive RTC engine allocator.
  static final shared = RtcEngineManager._();

  /// The RTC application identifier expected by server credentials.
  static const defaultAppID = '5588dfe2e7874bd08ea28f4968ec2d40';

  /// The factory for native RTC engine resources.
  final Future<RtcPlatform> Function() _createEngine;

  /// Creates native RTC resources using the configured application identifier.
  ///
  /// Returns initialized platform resources with local capture disabled.
  static Future<RtcPlatform> _createNativeEngine() =>
      AgoraRtcPlatform.create(defaultAppID);

  /// The current exclusive engine lease.
  RtcEngineLease? _activeLease;

  /// The pending lease requests in arrival order.
  final List<_RtcEngineRequest> _requests = [];

  /// The error delivered when a pending lease request is cancelled.
  static const _cancelledError = XmaxError(
    code: XmaxErrorCode.cancelled,
    message: 'RTC engine acquisition was cancelled',
  );

  /// Acquires an exclusive RTC engine lease in request order.
  ///
  /// Parameters:
  /// - [cancellation]: Completes to withdraw this request without releasing another owner's lease.
  ///
  /// Returns the exclusive engine lease owned by this caller.
  /// Cancellation during native creation waits for that creation and its cleanup to settle.
  Future<RtcEngineLease> acquire({
    Future<void>? cancellation,
  }) async {
    final request = _RtcEngineRequest();

    _requests.add(request);
    if (cancellation == null) {
      unawaited(_fulfillNext());
    } else {
      unawaited(
        cancellation.then<void>(
          (
            _,
          ) => _cancelRequest(request),
          onError: (
            Object error,
            StackTrace stackTrace,
          ) => _cancelRequest(request),
        ),
      );
      // Deliver an already-completed cancellation before allocating native resources.
      unawaited(Future<void>.microtask(_fulfillNext));
    }

    try {
      final lease = await request.completion.future;

      if (request.isCancelled) {
        try {
          await release(lease);
        } catch (_) {
          // Release clears ownership even when native destruction fails.
        }
        throw _cancelledError;
      }

      return lease;
    } finally {
      request.acceptsCancellation = false;
    }
  }

  /// Removes a queued request or invalidates an acquisition that has not reached its caller.
  ///
  /// Parameters:
  /// - [request]: The lease request associated with the cancellation signal.
  void _cancelRequest(
    _RtcEngineRequest request,
  ) {
    if (!request.acceptsCancellation || request.isCancelled) {
      return;
    }

    request.isCancelled = true;
    if (_requests.remove(request)) {
      request.completion.completeError(_cancelledError);
    }
  }

  /// Releases only the matching active lease and serves waiting owners.
  ///
  /// Parameters:
  /// - [lease]: The exclusive RTC engine lease to release.
  Future<void> release(
    RtcEngineLease lease,
  ) async {
    if (!identical(
      _activeLease?.id,
      lease.id,
    )) {
      return;
    }

    try {
      await lease.engine.destroy();
    } finally {
      // Clears ownership even if native release fails so waiting managers can acquire the engine.
      _activeLease = null;
      unawaited(_fulfillNext());
    }
  }

  /// Creates an engine lease, rejecting initialization failures as RTC errors.
  ///
  /// Returns the exclusive engine lease owned by this caller.
  Future<RtcEngineLease> _createLease() async {
    try {
      final engine = await _createEngine();

      return RtcEngineLease(engine);
    } catch (error) {
      throw XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Failed to create RTC Engine: $error',
      );
    }
  }

  /// Serves queued requests when no active lease exists.
  Future<void> _fulfillNext() async {
    if (_creating) {
      return;
    }

    _creating = true;

    try {
      while (_activeLease == null && _requests.isNotEmpty) {
        final request = _requests.removeAt(0);

        try {
          final lease = await _createLease();

          if (request.isCancelled) {
            try {
              await lease.engine.destroy();
            } catch (_) {
              // Preserve cancellation and let the next queued owner proceed.
            }
            throw _cancelledError;
          }

          _activeLease = lease;
          request.completion.complete(lease);
        } catch (error, stackTrace) {
          request.completion.completeError(
            request.isCancelled ? _cancelledError : error,
            stackTrace,
          );
        }
      }
    } finally {
      _creating = false;
    }
  }

  /// Whether serialized RTC engine creation is active.
  bool _creating = false;
}

/// A pending exclusive engine acquisition and its cancellation validity.
final class _RtcEngineRequest {

  /// The continuation awaiting engine ownership.
  final Completer<RtcEngineLease> completion = Completer<RtcEngineLease>();

  /// Whether cancellation arrived before acquisition reached the caller.
  bool isCancelled = false;

  /// Whether the request still accepts cancellation rather than belonging to an active owner.
  bool acceptsCancellation = true;
}
