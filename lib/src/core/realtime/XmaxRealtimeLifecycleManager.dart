//
//  XmaxRealtimeLifecycleManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../service/realtime/RealtimeState.dart';
import 'XmaxRealtimeErrorManager.dart';

/// The kinds of mutually coordinated media and realtime operations.
enum RealtimeOperationKind {

  /// Creates, stops, or reconfigures local media.
  media,

  /// Establishes a realtime connection.
  connection,

  /// Starts generation and waits for its first frame.
  generation,

  /// Switches cameras and resumes generation when needed.
  cameraSwitch,

  /// Changes conditions or transport settings without restarting generation.
  configuration,
}

/// The resources released by termination, ordered from narrowest to broadest.
enum RealtimeTerminationScope {

  /// Releases the task while retaining the connection and local media.
  generation,

  /// Releases the connection and task while retaining local media.
  connection,

  /// Releases the connection, task, and local media.
  all;

  /// Whether this scope includes [kind]'s resources.
  bool affects(
    RealtimeOperationKind kind,
  ) => switch (this) {
    RealtimeTerminationScope.generation =>
      kind != RealtimeOperationKind.media && kind != RealtimeOperationKind.connection,
    RealtimeTerminationScope.connection => kind != RealtimeOperationKind.media,
    RealtimeTerminationScope.all => true,
  };
}

/// The session identifier and local media availability after cleanup.
final class RealtimeCleanupResult {

  /// Creates a cleanup result.
  const RealtimeCleanupResult({
    this.sessionID,
    this.hasLocalMedia = false,
  });

  /// The session identifier involved in cleanup, if any.
  final String? sessionID;

  /// Whether usable local media remains after cleanup.
  final bool hasLocalMedia;
}

/// Guards operation validity and defines its failure cleanup.
///
/// Resource-changing futures must settle before checking ownership. [wait] is
/// reserved for passive readiness waits whose producers are released by cleanup.
final class RealtimeOperationToken {

  /// Creates a token with optional failure cleanup.
  RealtimeOperationToken._(
    this._failureScope,
  );

  /// The resources released if this operation fails.
  RealtimeTerminationScope? _failureScope;

  /// The cancellation signal, completed once when ownership is invalidated.
  final Completer<void> _cancelled = Completer<void>();

  /// The first runtime failure associated with invalidation.
  XmaxError? _failure;

  /// Whether this operation still owns its resources.
  bool get isCurrent => !_cancelled.isCompleted;

  /// The cancellation signal supplied to cancellable signaling waits.
  Future<void> get cancellation => _cancelled.future;

  /// Sets the resources released if the operation fails or is cancelled.
  ///
  /// Parameters:
  /// - [scope]: The failure cleanup scope.
  void setFailureScope(
    RealtimeTerminationScope scope,
  ) {
    ensureCurrent();
    _failureScope = scope;
  }

  /// Rejects cancelled work, preserving its originating runtime failure.
  void ensureCurrent() {
    if (!isCurrent) {
      throw _failure ?? XmaxRealtimeLifecycleManager.cancelledError();
    }
  }

  /// Waits for [readiness] or cancellation and returns the validated result.
  Future<T> wait<T>(
    Future<T> readiness,
  ) async {
    // A producer may fail during cancellation cleanup before the race is installed.
    readiness.ignore();
    ensureCurrent();
    final result = await Future.any<T>([
      readiness,
      _cancelled.future.then<T>((
        _,
      ) => throw _failure ?? XmaxRealtimeLifecycleManager.cancelledError()),
    ]);
    ensureCurrent();
    return result;
  }

  /// Invalidates ownership while retaining the first supplied [error].
  void _invalidate(
    XmaxError? error,
  ) {
    _failure ??= error;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

/// Owns operation admission, lifecycle state, and scoped termination.
///
/// Foreground work takes priority over adaptation. Generation requests replace
/// unfinished predecessors after their resource work and cleanup settle.
/// Resource owners execute cleanup through the injected handler.
final class XmaxRealtimeLifecycleManager {

  /// Creates a lifecycle coordinator.
  ///
  /// Parameters:
  /// - [errorManager]: The shared runtime failure manager.
  /// - [cleanup]: Releases scoped resources after affected workers settle.
  XmaxRealtimeLifecycleManager({
    required XmaxRealtimeErrorManager errorManager,
    required Future<RealtimeCleanupResult> Function(
      RealtimeTerminationScope scope,
      String taskID,
    ) cleanup,
  }) : _errorManager = errorManager,
       _cleanup = cleanup;

  /// The shared failure reporter.
  final XmaxRealtimeErrorManager _errorManager;

  /// The resource owners' scoped cleanup handler.
  final Future<RealtimeCleanupResult> Function(
    RealtimeTerminationScope scope,
    String taskID,
  ) _cleanup;

  /// The state exposed to your app.
  RealtimeState _state = const RealtimeState(connectionState: RealtimeConnectionState.idle);

  /// The current state listener.
  RealtimeStateListener? _stateListener;

  /// The operation currently owning resource admission.
  _RealtimeOperation? _activeOperation;

  /// The latest generation request, including one awaiting its predecessor.
  _GenerationRequest? _generationRequest;

  /// The merged cleanup request currently in progress.
  _RealtimeTermination? _termination;

  /// The number of pending or executing foreground calls.
  int _foregroundRequests = 0;

  /// The current connection and generation state.
  RealtimeState get currentState => _state;

  /// Replaces [listener] and immediately delivers the current state.
  void setStateListener(
    RealtimeStateListener? listener,
  ) {
    _stateListener = listener;
    listener?.call(_state);
  }

  /// Admits an operation or replaces an unfinished generation request.
  ///
  /// Parameters:
  /// - [kind]: The requested operation kind.
  /// - [failureScope]: The cleanup scope, or null to retain resources on failure.
  /// - [operation]: The body, which validates ownership across asynchronous boundaries.
  ///
  /// Returns the result after resource admission has been released.
  Future<T> run<T>({
    required RealtimeOperationKind kind,
    RealtimeTerminationScope? failureScope,
    required Future<T> Function(
      RealtimeOperationToken token,
    ) operation,
  }) async {
    _foregroundRequests++;
    try {
      if (kind == RealtimeOperationKind.generation) {
        return await _runGeneration(
          failureScope: failureScope,
          operation: operation,
        );
      }
      return await _runOperation(
        kind: kind,
        failureScope: failureScope,
        operation: operation,
      );
    } finally {
      _foregroundRequests--;
    }
  }

  /// Runs [operation] only when no foreground call owns or awaits admission.
  ///
  /// Returns false when busy, or true after the admitted update finishes.
  Future<bool> runAdaptiveConfiguration(
    Future<void> Function(
      RealtimeOperationToken token,
    ) operation,
  ) async {
    if (_termination != null || _activeOperation != null ||
        _generationRequest != null || _foregroundRequests > 0 ||
        _state.connectionState != RealtimeConnectionState.generating) {
      return false;
    }
    await _runOperation(
      kind: RealtimeOperationKind.configuration,
      operation: operation,
      background: true,
    );
    return true;
  }

  /// Publishes intermediate state while retaining operation admission.
  ///
  /// Parameters:
  /// - [state]: The intermediate snapshot.
  /// - [token]: The operation owning this state.
  void commit(
    RealtimeState state, {
    required RealtimeOperationToken token,
  }) {
    token.ensureCurrent();
    final active = _activeOperation;
    if (active?.token != token) {
      throw cancelledError();
    }
    if (state.connectionState == RealtimeConnectionState.preparing &&
        active!.kind == RealtimeOperationKind.media) {
      active.didBeginMediaPreparation = true;
    }
    _setState(state);
  }

  /// Stages final state for delivery after operation admission is released.
  ///
  /// Parameters:
  /// - [state]: The successful completion state.
  /// - [token]: The operation owning this completion.
  void complete(
    RealtimeState state, {
    required RealtimeOperationToken token,
  }) {
    token.ensureCurrent();
    final active = _activeOperation;
    if (active?.token != token) {
      throw cancelledError();
    }
    active!.completionState = state;
  }

  /// Marks current local media ready after capture and preview mounting complete.
  void markPreviewReady() {
    if (_state.connectionState != RealtimeConnectionState.preparing) {
      return;
    }
    const ready = RealtimeState(connectionState: RealtimeConnectionState.ready);
    final active = _activeOperation;
    if (active?.kind == RealtimeOperationKind.media) {
      active!.completionState = ready;
    } else {
      _setState(ready);
    }
  }

  /// Disconnects connection resources while preserving local media.
  ///
  /// Parameters:
  /// - [reason]: The reason delivered with the final state.
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  }) {
    final active = _activeOperation;
    if (_termination == null && _generationRequest == null &&
        (active == null || !RealtimeTerminationScope.connection.affects(active.kind)) &&
        (_state.connectionState == RealtimeConnectionState.idle ||
            _state.connectionState == RealtimeConnectionState.preparing ||
            _state.connectionState == RealtimeConnectionState.ready)) {
      return Future<void>.value();
    }
    return terminate(
      RealtimeTerminationScope.connection,
      reason: reason,
    );
  }

  /// Releases scoped resources, merging overlapping cleanup requests.
  ///
  /// Parameters:
  /// - [scope]: The resources to release.
  /// - [reason]: The reason delivered with the terminal state.
  Future<void> terminate(
    RealtimeTerminationScope scope, {
    RealtimeReason reason = RealtimeReason.normal,
  }) => _requestTermination(
    scope,
    reason: reason,
  );

  /// Routes a current runtime failure to scoped cleanup.
  ///
  /// Parameters:
  /// - [error]: The runtime failure.
  /// - [scope]: The affected resources.
  /// - [isCurrent]: Verifies that the source still belongs to this lifecycle.
  Future<void> handleFailure(
    XmaxError error,
    RealtimeFailureScope scope,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent() || _state.connectionState == RealtimeConnectionState.idle) {
      return;
    }
    final pending = _termination;
    if (pending != null && pending.scope != RealtimeTerminationScope.generation &&
        scope != RealtimeFailureScope.all) {
      return;
    }
    await _requestTermination(
      scope == RealtimeFailureScope.all
          ? RealtimeTerminationScope.all : RealtimeTerminationScope.connection,
      error: error,
      reason: RealtimeReason.failure(error),
    );
  }

  /// Replaces a generation request and waits for its resource completion.
  ///
  /// Parameters:
  /// - [failureScope]: The cleanup required on failure.
  /// - [operation]: The generation body.
  ///
  /// Returns the latest request's result.
  Future<T> _runGeneration<T>({
    required RealtimeTerminationScope? failureScope,
    required Future<T> Function(
      RealtimeOperationToken token,
    ) operation,
  }) async {
    final active = _activeOperation;
    if ((_termination != null && _generationRequest == null) ||
        (active != null && !active.background && active.request == null)) {
      throw _conflict();
    }
    final previous = _generationRequest;
    final request = _GenerationRequest();
    _generationRequest = request;
    if (previous != null) {
      previous.cancelled = true;
      if (active?.request == previous) {
        active!.token._invalidate(null);
      }
    }

    try {
      await previous?.completion.future;
      if (request.cancelled || _generationRequest != request) {
        throw cancelledError();
      }
      return await _runOperation(
        kind: RealtimeOperationKind.generation,
        failureScope: failureScope,
        request: request,
        operation: operation,
      );
    } finally {
      request.finish();
      if (_generationRequest == request) {
        _generationRequest = null;
      }
    }
  }

  /// Executes an admitted body, settling resource writes before cleanup.
  ///
  /// Parameters:
  /// - [kind]: The operation kind.
  /// - [failureScope]: The optional failure cleanup scope.
  /// - [request]: The owning generation request, if any.
  /// - [operation]: The resource work.
  /// - [background]: Whether foreground requests may wait for this configuration.
  ///
  /// Returns the completed body result.
  Future<T> _runOperation<T>({
    required RealtimeOperationKind kind,
    RealtimeTerminationScope? failureScope,
    _GenerationRequest? request,
    required Future<T> Function(
      RealtimeOperationToken token,
    ) operation,
    bool background = false,
  }) async {
    final preceding = _activeOperation;
    if (preceding != null && preceding.background) {
      await preceding.completion.future;
    }
    if (request != null && (request.cancelled || _generationRequest != request)) {
      throw cancelledError();
    }
    if (_termination != null || _activeOperation != null ||
        (request == null && _generationRequest != null)) {
      throw _conflict();
    }

    final admitted = _RealtimeOperation(
      kind: kind == RealtimeOperationKind.generation &&
          _state.connectionState == RealtimeConnectionState.generating
          ? RealtimeOperationKind.configuration : kind,
      token: RealtimeOperationToken._(failureScope),
      request: request,
      background: background,
    );
    _activeOperation = admitted;
    try {
      late final T result;
      try {
        result = await operation(admitted.token);
      } finally {
        admitted.workerFinished.complete();
      }
      admitted.token.ensureCurrent();
      final completionState = admitted.completionState;
      _finish(admitted);
      if (completionState != null) {
        _setState(completionState);
      }
      return result;
    } catch (error) {
      return await _handleOperationFailure(
        error,
        admitted,
      );
    } finally {
      _finish(admitted);
    }
  }

  /// Performs failure cleanup and throws the preserved terminal error.
  ///
  /// Parameters:
  /// - [error]: The body or ownership failure.
  /// - [operation]: The operation whose worker has settled.
  Future<Never> _handleOperationFailure(
    Object error,
    _RealtimeOperation operation,
  ) async {
    final token = operation.token;
    final resolved = token._failure ?? XmaxError.from(error);
    final cancelled = !token.isCurrent || resolved.code == XmaxErrorCode.cancelled;
    final scope = token._failureScope;
    final configuration = operation.kind == RealtimeOperationKind.configuration;

    if (cancelled && (configuration || scope == null) &&
        operation.termination == null && _termination == null) {
      _finish(operation);
      _restoreIdleAfterPreparation(operation);
      throw token._failure ?? cancelledError();
    }
    if (cancelled || (!configuration && scope != null)) {
      var cleanup = operation.termination?.completion.future ?? _termination?.completion.future;
      if (cleanup == null) {
        final replacement = operation.request != null && _generationRequest != null &&
            operation.request != _generationRequest;
        cleanup = _requestTermination(
          cancelled && replacement && _state.connectionState == RealtimeConnectionState.connected
              ? RealtimeTerminationScope.generation
              : scope ?? RealtimeTerminationScope.connection,
          error: cancelled ? null : resolved,
          reason: cancelled ? RealtimeReason.normal : RealtimeReason.failure(resolved),
          origin: operation,
        );
      }
      await cleanup;
      throw token._failure ?? (cancelled ? cancelledError() : resolved);
    }

    _finish(operation);
    _restoreIdleAfterPreparation(operation);
    throw _errorManager.report(resolved);
  }

  /// Rolls back an incomplete media preparation without altering newer state.
  ///
  /// Parameters:
  /// - [operation]: The failed media operation.
  void _restoreIdleAfterPreparation(
    _RealtimeOperation operation,
  ) {
    if (operation.didBeginMediaPreparation &&
        _state.connectionState == RealtimeConnectionState.preparing) {
      _setState(const RealtimeState(connectionState: RealtimeConnectionState.idle));
    }
  }

  /// Installs cleanup ownership before delivering disconnection callbacks.
  ///
  /// Parameters:
  /// - [scope]: The required cleanup scope.
  /// - [error]: The first runtime failure to retain.
  /// - [reason]: The requested terminal reason.
  /// - [origin]: A settled worker requesting its own cleanup.
  ///
  /// Returns the shared cleanup barrier.
  Future<void> _requestTermination(
    RealtimeTerminationScope scope, {
    XmaxError? error,
    RealtimeReason reason = RealtimeReason.normal,
    _RealtimeOperation? origin,
  }) {
    if (origin == null) {
      _generationRequest?.cancelled = true;
      _generationRequest = null;
    }
    final pending = _termination ?? _RealtimeTermination(
      scope: scope,
      reason: reason,
      error: error,
    );
    final fresh = _termination == null;
    _termination = pending;
    if (scope.index > pending.scope.index) {
      pending.scope = scope;
    }
    pending.error ??= error;
    if (pending.error != null) {
      pending.reason = RealtimeReason.failure(pending.error!);
    }
    final active = _activeOperation;
    if (active != null && (active == origin || pending.scope.affects(active.kind))) {
      active.token._invalidate(pending.error);
      if (active.termination != pending) {
        active.termination = pending;
        pending.workers.add(active.workerFinished.future);
      }
    }
    if (fresh) {
      unawaited(Future<void>.microtask(() => _performTermination(pending)));
    }
    if (pending.scope != RealtimeTerminationScope.generation) {
      _setState(
        RealtimeState(
          connectionState: RealtimeConnectionState.disconnecting,
          sessionID: _state.sessionID,
        ),
      );
    }
    return pending.completion.future;
  }

  /// Settles affected workers, releases resources, then publishes terminal state.
  ///
  /// Parameters:
  /// - [pending]: The shared cleanup record.
  Future<void> _performTermination(
    _RealtimeTermination pending,
  ) async {
    try {
      while (_termination == pending) {
        final workers = List<Future<void>>.of(pending.workers);
        pending.workers.clear();
        await Future.wait(workers);
        final scope = pending.scope;
        final result = await _cleanup(
          scope,
          _state.taskID ?? '',
        );
        pending.sessionID = result.sessionID ?? pending.sessionID;
        if (pending.scope != scope || pending.workers.isNotEmpty) {
          continue;
        }

        final active = _activeOperation;
        if (active != null && scope.affects(active.kind)) {
          _finish(active);
        }
        final finalState = RealtimeState(
          connectionState: scope == RealtimeTerminationScope.generation
              ? RealtimeConnectionState.connected
              : scope == RealtimeTerminationScope.all || !result.hasLocalMedia
                  ? RealtimeConnectionState.idle : RealtimeConnectionState.ready,
          sessionID: pending.sessionID ?? _state.sessionID,
          reason: scope == RealtimeTerminationScope.generation ? null : pending.reason,
        );

        // App callbacks may immediately start new work or request another cleanup.
        _termination = null;
        if (scope != RealtimeTerminationScope.generation) {
          _errorManager.invalidatePendingFailures(
            scope: scope == RealtimeTerminationScope.all
                ? RealtimeFailureScope.all : RealtimeFailureScope.connection,
          );
        }
        _setState(finalState);
        if (pending.error != null) {
          _errorManager.report(pending.error!);
        }
        break;
      }
    } catch (error) {
      // Cleanup owners attempt every step; an unexpected failure must still release waiters.
      _errorManager.report(error);
      if (_termination == pending) {
        _termination = null;
      }
    } finally {
      pending.completion.complete();
    }
  }

  /// Releases admission and predecessor barriers only for [operation].
  void _finish(
    _RealtimeOperation operation,
  ) {
    if (_activeOperation == operation) {
      _activeOperation = null;
    }
    if (_generationRequest == operation.request) {
      _generationRequest = null;
    }
    operation.request?.finish();
    if (!operation.completion.isCompleted) {
      operation.completion.complete();
    }
  }

  /// Publishes [state] only when the complete snapshot changes.
  void _setState(
    RealtimeState state,
  ) {
    if (_state == state) {
      return;
    }
    final previous = _state;
    _state = state;
    if (previous.connectionState != state.connectionState) {
      XmaxLogger.debug(
        category: XmaxLoggerCategory.realtime,
        message: '实时状态 (Realtime State)\n└─ ${previous.connectionState.name} → ${state.connectionState.name}',
      );
    }
    _stateListener?.call(state);
  }

  /// Creates and reports an operation-admission error.
  XmaxError _conflict() => _errorManager.report(
    const XmaxError(
      code: XmaxErrorCode.invalidConfiguration,
      message: 'Another realtime operation is in progress; wait for it to finish',
    ),
  );

  /// Creates an ownership cancellation error.
  static XmaxError cancelledError() => const XmaxError(
    code: XmaxErrorCode.cancelled,
    message: 'Realtime operation was cancelled',
  );
}

/// A generation request's replacement flag and resource-completion barrier.
final class _GenerationRequest {

  /// Whether a successor or explicit termination cancelled this request.
  bool cancelled = false;

  /// The barrier released after resource work and cleanup finish.
  final Completer<void> completion = Completer<void>();

  /// Releases successors once.
  void finish() {
    if (!completion.isCompleted) {
      completion.complete();
    }
  }
}

/// An admitted worker and the resources its token protects.
final class _RealtimeOperation {

  /// Creates an operation record before invoking resource work.
  _RealtimeOperation({
    required this.kind,
    required this.token,
    required this.request,
    required this.background,
  });

  /// The operation kind governing admission and cleanup.
  final RealtimeOperationKind kind;

  /// The token invalidated by replacement or termination.
  final RealtimeOperationToken token;

  /// The owning generation request, if any.
  final _GenerationRequest? request;

  /// Whether foreground requests may await this low-priority operation.
  final bool background;

  /// Whether this worker began local media preparation.
  bool didBeginMediaPreparation = false;

  /// The state delivered after successful admission release.
  RealtimeState? completionState;

  /// The body-completion barrier, excluding lifecycle cleanup.
  final Completer<void> workerFinished = Completer<void>();

  /// The admission-release barrier, including cleanup.
  final Completer<void> completion = Completer<void>();

  /// The merged cleanup assigned to this worker.
  _RealtimeTermination? termination;
}

/// A cleanup request that can expand while resources are being released.
final class _RealtimeTermination {

  /// Creates a pending termination record.
  _RealtimeTermination({
    required this.scope,
    required this.reason,
    required this.error,
  });

  /// The broadest requested cleanup scope.
  RealtimeTerminationScope scope;

  /// The terminal reason, retaining the first runtime failure.
  RealtimeReason reason;

  /// The first runtime failure, if any.
  XmaxError? error;

  /// The session identifier retained across cleanup passes.
  String? sessionID;

  /// The workers that must settle before the next cleanup pass.
  final List<Future<void>> workers = [];

  /// The barrier shared by concurrent cleanup callers.
  final Completer<void> completion = Completer<void>();
}
