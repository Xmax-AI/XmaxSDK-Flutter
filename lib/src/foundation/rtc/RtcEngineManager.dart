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
  final List<Completer<RtcEngineLease>> _requests =
      <Completer<RtcEngineLease>>[];

  /// Acquires an exclusive RTC engine lease in request order.
  ///
  /// Returns the exclusive engine lease owned by this caller.
  Future<RtcEngineLease> acquire() async {
    final completer = Completer<RtcEngineLease>();

    _requests.add(completer);
    unawaited(_fulfillNext());

    return completer.future;
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
      await _fulfillNext();
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

          _activeLease = lease;
          request.complete(lease);
        } catch (error, stackTrace) {
          request.completeError(
            error,
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
