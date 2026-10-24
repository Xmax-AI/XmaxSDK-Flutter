//
//  XmaxRealtimeErrorManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/ErrorMessageFormatter.dart';
import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';

/// The resources affected by a realtime failure.
enum RealtimeFailureScope {

  /// Remote connection resources, retaining local media.
  connection,

  /// Local media and remote connection resources.
  all,
}

/// An asynchronous handler for failures in the current realtime lifecycle.
///
/// Parameters:
/// - [error]: The operation error.
/// - [scope]: The resources affected by the failure.
/// - [isCurrent]: A check that the operation still belongs to the current lifecycle.
typedef RealtimeFailureHandler =
    Future<void> Function(
      XmaxError error,
      RealtimeFailureScope scope,
      bool Function() isCurrent,
    );

/// Logs realtime errors and forwards runtime failures for coordinated lifecycle termination.
final class XmaxRealtimeErrorManager {

  /// The failure handler for the current lifecycle.
  RealtimeFailureHandler? _failureHandler;

  /// The revision used to reject failures from previous media bindings.
  int _mediaRevision = 0;

  /// The revision used to reject failures from previous connections.
  int _connectionRevision = 0;

  /// Sets the failure handler for the current lifecycle.
  ///
  /// Parameters:
  /// - [handler]: The failure handler, or null to stop forwarding failures.
  void setFailureHandler(
    RealtimeFailureHandler? handler,
  ) {
    _failureHandler = handler;
  }

  /// Invalidates earlier callbacks so they cannot close newly created connections or media.
  ///
  /// Parameters:
  /// - [scope]: The affected resources; defaults to both local media and the connection.
  void invalidatePendingFailures({
    RealtimeFailureScope scope = RealtimeFailureScope.all,
  }) {
    _connectionRevision += 1;
    if (scope == RealtimeFailureScope.all) {
      _mediaRevision += 1;
    }
  }

  /// Captures a resource revision for validating asynchronous callbacks.
  ///
  /// Parameters:
  /// - [scope]: The resources whose validity is checked.
  ///
  /// Returns a check that becomes false after the resources are rebuilt or closed.
  bool Function() captureValidity(
    RealtimeFailureScope scope,
  ) {
    final revision = _revision(scope);

    return () => revision == _revision(scope);
  }

  /// Reads the lifecycle revision for a resource scope.
  ///
  /// Parameters:
  /// - [scope]: The resources affected by the failure.
  ///
  /// Returns the current resource revision.
  int _revision(
    RealtimeFailureScope scope,
  ) => scope == RealtimeFailureScope.all ? _mediaRevision : _connectionRevision;

  /// Normalizes and logs an SDK error.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns the normalized SDK error.
  XmaxError report(
    Object error,
  ) {
    final xmaxError = XmaxError.from(error);

    _log(xmaxError);

    return xmaxError;
  }

  /// Forwards a runtime failure only while its source lifecycle remains valid.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  /// - [scope]: The affected resources; defaults to the connection while retaining local media.
  void forward(
    XmaxError error, {
    RealtimeFailureScope scope = RealtimeFailureScope.connection,
  }) {
    final isCurrent = captureValidity(scope);
    final handler = _failureHandler;
    // Check lifecycle ownership before dispatching errors so stale failures cannot close newer resources.
    Future<void>.microtask(() async {
      if (!isCurrent()) {
        return;
      }

      _log(error);
      await handler?.call(
        error,
        scope,
        isCurrent,
      );
    }).catchError((
      Object failure,
    ) {
      _log(XmaxError.from(failure));
    });
  }

  /// Logs an SDK error without letting logging failures suppress error propagation.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  void _log(
    XmaxError error,
  ) {
    try {
      XmaxLogger.error(
        category: XmaxLoggerCategory.realtime,
        message:
            '实时操作失败 (Realtime Operation Failed)\n'
            '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}${ErrorMessageFormatter.format(error)}',
      );
    } catch (_) {
      // Logging failures must not suppress the original error.
    }
  }
}
