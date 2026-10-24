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
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeState.dart';
import 'XmaxRealtimeErrorManager.dart';

/// The session identifier and local media availability after connection cleanup.
final class RealtimeCleanupResult {

  /// Creates a cleanup result.
  const RealtimeCleanupResult({
    this.sessionID,
    required this.hasLocalMedia,
  });

  /// The session identifier involved in cleanup, if any.
  final String? sessionID;

  /// Whether usable local media remains after cleanup.
  final bool hasLocalMedia;
}

/// Owns lifecycle state, asynchronous operation validity, and scoped termination.
///
/// Resource owners perform cleanup through injected handlers. This coordinator does not own
/// capture, RTC, or rendering resources. Generation preparation is serialized independently of
/// first-frame waiting so later conditions and stop requests remain responsive.
final class XmaxRealtimeLifecycleManager {

  /// Creates a lifecycle coordinator with resource cleanup handlers.
  ///
  /// Parameters:
  /// - [errorManager]: The shared runtime failure manager.
  /// - [cleanupConnection]: Releases generation and connection resources for the supplied task.
  /// - [stopLocalMedia]: Releases local capture after connection cleanup and camera creation finish.
  /// - [stopGeneration]: Conceals remote video and stops a task without leaving RTC.
  /// - [cancelPendingStart]: Cancels result confirmation without leaving RTC.
  /// - [currentSessionID]: Reads the active server session identifier, or an empty string.
  XmaxRealtimeLifecycleManager({
    required XmaxRealtimeErrorManager errorManager,
    required Future<RealtimeCleanupResult> Function(
      String taskID,
    ) cleanupConnection,
    required Future<void> Function() stopLocalMedia,
    required Future<void> Function(
      String taskID,
    ) stopGeneration,
    required void Function() cancelPendingStart,
    required String Function() currentSessionID,
  }) : _errorManager = errorManager,
       _cleanupConnection = cleanupConnection,
       _stopLocalMedia = stopLocalMedia,
       _stopGeneration = stopGeneration,
       _cancelPendingStart = cancelPendingStart,
       _currentSessionID = currentSessionID;

  /// The manager that reports errors and invalidates failures from released resources.
  final XmaxRealtimeErrorManager _errorManager;

  /// The handler releasing generation and connection resources.
  final Future<RealtimeCleanupResult> Function(
    String taskID,
  ) _cleanupConnection;

  /// The handler releasing local capture resources.
  final Future<void> Function() _stopLocalMedia;

  /// The handler stopping a generation task while retaining RTC.
  final Future<void> Function(
    String taskID,
  ) _stopGeneration;

  /// The handler cancelling pending result confirmation.
  final void Function() _cancelPendingStart;

  /// The active server session identifier provider.
  final String Function() _currentSessionID;

  /// The realtime state snapshot exposed to your app.
  RealtimeState _state = const RealtimeState(
    connectionState: RealtimeConnectionState.idle,
  );

  /// The listener for connection and generation state changes.
  RealtimeStateListener? _stateListener;

  /// The revision of connection and local media operations.
  int _operationVersion = 0;

  /// The latest generation request revision.
  int _generationRequestVersion = 0;

  /// The revision invalidating queued generation work on disconnection.
  int _generationCancellationVersion = 0;

  /// The completion barrier for serialized generation preparation.
  Future<void> _generationOperation = Future<void>.value();

  /// The task awaiting first-frame readiness.
  String? _startingGenerationTaskID;

  /// The pending generation readiness notification.
  Completer<void>? _startingGenerationCompleter;

  /// The shared full shutdown operation.
  Future<void>? _closeFuture;

  /// The shared connection cleanup operation.
  Future<void>? _disconnectFuture;

  /// The camera creation operation that shutdown must await.
  Future<RealtimeMediaStream>? _cameraCreationFuture;

  /// The current connection and generation state.
  RealtimeState get currentState => _state;

  /// The current connection and local media revision.
  int get operationVersion => _operationVersion;

  /// The latest generation request revision.
  int get generationRequestVersion => _generationRequestVersion;

  /// The task awaiting generation readiness, if any.
  String? get startingGenerationTaskID => _startingGenerationTaskID;

  /// The pending first-frame readiness future, if any.
  Future<void>? get generationReadiness => _startingGenerationCompleter?.future;

  /// Whether full resource shutdown is in progress.
  bool get isClosing => _closeFuture != null;

  /// Whether connection cleanup is in progress.
  bool get isDisconnecting => _disconnectFuture != null;

  /// The connection cleanup to await before admitting generation, if any.
  Future<void>? get disconnection => _disconnectFuture;

  /// Replaces the state listener and immediately delivers the current state.
  ///
  /// Parameters:
  /// - [listener]: The state listener, or null to remove it.
  void setStateListener(
    RealtimeStateListener? listener,
  ) {
    _stateListener = listener;
    listener?.call(_state);
  }

  /// Commits and delivers a realtime state snapshot.
  ///
  /// Parameters:
  /// - [state]: The state to expose to your app.
  void emit(
    RealtimeState state,
  ) {
    final previous = _state.connectionState;

    _state = state;
    if (previous != state.connectionState) {
      XmaxLogger.debug(
        category: XmaxLoggerCategory.realtime,
        message:
            '实时状态 (Realtime State)\n'
            '└─ ${previous.name} → ${state.connectionState.name}',
      );
    }

    _stateListener?.call(state);
  }

  /// Advances and returns the revision guarding connection and media work.
  int beginOperation() => ++_operationVersion;

  /// Supersedes earlier generation requests and cancels pending result confirmation.
  ///
  /// Returns the revision to validate before executing the new request.
  int beginGenerationRequest() {
    final version = ++_generationRequestVersion;

    _cancelPendingStart();

    return version;
  }

  /// Records camera creation so shutdown can wait for capture ownership to settle.
  ///
  /// Parameters:
  /// - [creation]: The camera stream creation operation.
  void trackCameraCreation(
    Future<RealtimeMediaStream> creation,
  ) {
    _cameraCreationFuture = creation;
  }

  /// Clears camera creation bookkeeping only if the operation is still current.
  ///
  /// Parameters:
  /// - [creation]: The completed camera creation operation.
  void finishCameraCreation(
    Future<RealtimeMediaStream> creation,
  ) {
    if (identical(
      _cameraCreationFuture,
      creation,
    )) {
      _cameraCreationFuture = null;
    }
  }

  /// Creates the first-frame readiness notification for a confirmed generation task.
  ///
  /// Parameters:
  /// - [taskID]: The confirmed generation task identifier.
  ///
  /// Returns the completer owned by this task until completion, failure, or cancellation.
  Completer<void> beginGenerationWait(
    String taskID,
  ) {
    final completer = Completer<void>();

    // Attach a handler before returning the wait to prevent unhandled cancellation errors.
    completer.future.ignore();
    _startingGenerationTaskID = taskID;
    _startingGenerationCompleter = completer;

    return completer;
  }

  /// Detaches a failed wait so connection cleanup cannot replace its original error.
  ///
  /// Parameters:
  /// - [completer]: The failed first-frame wait.
  void detachGenerationWait(
    Completer<void> completer,
  ) {
    if (identical(
      _startingGenerationCompleter,
      completer,
    )) {
      _startingGenerationCompleter = null;
    }
  }

  /// Clears readiness bookkeeping only when it belongs to the completed wait.
  ///
  /// Parameters:
  /// - [completer]: The completed first-frame wait.
  void finishGenerationWait(
    Completer<void> completer,
  ) {
    if (identical(
      _startingGenerationCompleter,
      completer,
    )) {
      _startingGenerationTaskID = null;
      _startingGenerationCompleter = null;
    }
  }

  /// Serializes generation preparation without holding the queue for first-frame readiness.
  ///
  /// Parameters:
  /// - [operation]: The asynchronous generation control operation.
  ///
  /// Returns the operation's result, preserving its error on failure.
  Future<T> enqueueGenerationOperation<T>(
    Future<T> Function() operation,
  ) {
    final cancellationVersion = _generationCancellationVersion;
    final previousOperation = _generationOperation;
    final completion = Completer<void>();

    _generationOperation = completion.future;

    return () async {
      await previousOperation;

      try {
        _ensureGenerationOperationCurrent(cancellationVersion);

        final result = await operation();

        _ensureGenerationOperationCurrent(cancellationVersion);

        return result;
      } finally {
        completion.complete();
      }
    }();
  }

  /// Stops generation while retaining the connection and local media.
  Future<void> stopGeneration() {
    beginGenerationRequest();

    return enqueueGenerationOperation(_performStopGeneration);
  }

  /// Stops the active task and invalidates its pending readiness notification.
  Future<void> _performStopGeneration() async {
    final sessionID = _currentSessionID();

    if (sessionID.isEmpty ||
        (_state.connectionState != RealtimeConnectionState.connected &&
            _state.connectionState != RealtimeConnectionState.generating)) {
      return;
    }

    final taskID = _state.taskID ?? _startingGenerationTaskID ?? '';
    final wasGenerating =
        _state.connectionState == RealtimeConnectionState.generating ||
        _startingGenerationTaskID != null;

    _operationVersion += 1;
    _generationRequestVersion += 1;
    _cancelStartingGeneration();

    try {
      await _stopGeneration(taskID);
    } catch (error) {
      _errorManager.report(error);
    }

    if (wasGenerating) {
      emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.connected,
          sessionID: sessionID,
        ),
      );
    }
  }

  /// Releases connection resources while preserving local media, sharing pending cleanup.
  ///
  /// Parameters:
  /// - [reason]: The reason associated with the resulting state.
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  }) {
    final active = _disconnectFuture;

    if (active != null) {
      return active;
    }

    if (_state.connectionState == RealtimeConnectionState.idle ||
        _state.connectionState == RealtimeConnectionState.preparing ||
        _state.connectionState == RealtimeConnectionState.ready) {
      _generationRequestVersion += 1;
      _generationCancellationVersion += 1;
      _cancelPendingStart();

      return Future<void>.value();
    }

    final future = _performDisconnect(reason);

    _disconnectFuture = future;

    return future.whenComplete(() => _disconnectFuture = null);
  }

  /// Invalidates connection work before invoking resource cleanup and committing its result.
  ///
  /// Parameters:
  /// - [reason]: The disconnection reason.
  Future<void> _performDisconnect(
    RealtimeReason reason,
  ) async {
    _errorManager.invalidatePendingFailures(
      scope: RealtimeFailureScope.connection,
    );
    _operationVersion += 1;
    _generationRequestVersion += 1;
    _generationCancellationVersion += 1;

    final taskID = _state.taskID ?? _startingGenerationTaskID ?? '';

    _cancelStartingGeneration();
    emit(
      const RealtimeState(
        connectionState: RealtimeConnectionState.disconnecting,
      ),
    );

    final result = await _cleanupConnection(taskID);

    emit(
      RealtimeState(
        connectionState: result.hasLocalMedia
            ? RealtimeConnectionState.ready
            : RealtimeConnectionState.idle,
        sessionID: result.sessionID,
        reason: reason,
      ),
    );
  }

  /// Releases connection and local media resources, sharing an existing shutdown operation.
  ///
  /// Parameters:
  /// - [reason]: The reason associated with the final idle state.
  Future<void> close({
    RealtimeReason reason = RealtimeReason.normal,
  }) {
    final active = _closeFuture;

    if (active != null) {
      return active;
    }

    final future = _performClose(reason);

    _closeFuture = future;

    return future.whenComplete(() => _closeFuture = null);
  }

  /// Waits for connection cleanup and camera creation before releasing local capture.
  ///
  /// Parameters:
  /// - [reason]: The shutdown reason.
  Future<void> _performClose(
    RealtimeReason reason,
  ) async {
    _errorManager.invalidatePendingFailures();
    _operationVersion += 1;
    await disconnect(reason: reason);

    try {
      await _cameraCreationFuture;
    } catch (_) {
      // Creation reports its own failure; shutdown must still release local resources.
    }

    try {
      await _stopLocalMedia();
      emit(
        RealtimeState(
          connectionState: RealtimeConnectionState.idle,
          reason: reason,
        ),
      );
    } catch (error) {
      _errorManager.report(error);
    }
  }

  /// Routes a current runtime failure to connection or full resource cleanup.
  ///
  /// Parameters:
  /// - [error]: The runtime failure.
  /// - [scope]: The resources affected by the failure.
  /// - [isCurrent]: A check that the failure still belongs to the current lifecycle.
  Future<void> handleFailure(
    XmaxError error,
    RealtimeFailureScope scope,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent() ||
        isClosing ||
        _state.connectionState == RealtimeConnectionState.idle) {
      return;
    }

    final reason = RealtimeReason.failure(error);

    if (scope == RealtimeFailureScope.all) {
      await close(reason: reason);
    } else if (_state.connectionState != RealtimeConnectionState.disconnecting) {
      await disconnect(reason: reason);
    }
  }

  /// Marks a preparing local stream ready after its resource owner confirms preview readiness.
  void markPreviewReady() {
    if (_state.connectionState == RealtimeConnectionState.preparing) {
      emit(
        const RealtimeState(connectionState: RealtimeConnectionState.ready),
      );
    }
  }

  /// Cancels the first-frame wait and clears its task binding.
  void _cancelStartingGeneration() {
    final completer = _startingGenerationCompleter;

    _startingGenerationTaskID = null;
    _startingGenerationCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime generation was cancelled',
        ),
      );
    }
  }

  /// Rejects connection or media work that no longer belongs to this lifecycle.
  ///
  /// Parameters:
  /// - [version]: The captured operation revision.
  void ensureCurrent(
    int version,
  ) {
    if (version != _operationVersion) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime connection was cancelled',
      );
    }
  }

  /// Rejects generation requests superseded by later requests or termination.
  ///
  /// Parameters:
  /// - [version]: The captured generation request revision.
  void ensureGenerationRequestCurrent(
    int version,
  ) {
    if (version != _generationRequestVersion) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime generation request was superseded',
      );
    }
  }

  /// Rejects queued generation operations invalidated by disconnection.
  ///
  /// Parameters:
  /// - [version]: The captured generation cancellation revision.
  void _ensureGenerationOperationCurrent(
    int version,
  ) {
    if (version != _generationCancellationVersion) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime generation operation was cancelled',
      );
    }
  }
}
