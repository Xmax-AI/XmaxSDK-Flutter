//
//  XmaxRealtimeGenerationManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:io';
import 'dart:math';

import '../../foundation/errors/XmaxError.dart';
import '../../media/interaction/InteractionControlling.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../stream/StreamControlling.dart';
import 'RealtimeTiming.dart';

/// A factory for unique generation task identifiers.
///
/// Returns a unique identifier for the new generation task.
typedef RealtimeTaskIDGenerator = String Function();

/// Starts generation, caches conditions, and binds interactions to the active task.
final class XmaxRealtimeGenerationManager {

  /// Creates a generation manager.
  ///
  /// Parameters:
  /// - [interactionController]: The controller that binds touch input to a generation task.
  /// - [streamController]: The controller that sends generation signals.
  /// - [taskIDGenerator]: The task identifier factory; defaults to [createTaskID].
  XmaxRealtimeGenerationManager({
    required InteractionControlling interactionController,
    required StreamControlling streamController,
    RealtimeTaskIDGenerator? taskIDGenerator,
  }) : _interactionController = interactionController,
       _streamController = streamController,
       _taskIDGenerator = taskIDGenerator ?? createTaskID;

  /// The controller that samples and maps interactions for the generation task.
  final InteractionControlling _interactionController;

  /// The controller that manages RTC publishing, subscriptions, and signaling.
  final StreamControlling _streamController;

  /// The factory for generation task identifiers.
  final RealtimeTaskIDGenerator _taskIDGenerator;

  /// The most recently submitted generation conditions.
  RealtimeContext? _currentContext;

  /// The most recently submitted face restoration setting.
  bool _currentFaceRestoration = false;

  /// The face restoration setting used when resuming generation.
  bool get cachedFaceRestoration => _currentFaceRestoration;

  /// A cancellable wait for the current generation result stream.
  GenerationStartConfirmation? _startConfirmation;

  /// The generation startup revision.
  int _startVersion = 0;

  /// Cancels result stream confirmation while retaining RTC for subsequent generation.
  void cancelPendingStart() {
    _startVersion += 1;
    _startConfirmation?.cancel();
  }

  /// Starts a task, confirms its result stream, and binds interactions before caching its
  /// conditions.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [context]: The generation conditions; null reuses cached conditions and is invalid on the
  ///   first start.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  /// - [ensureCurrent]: A lifecycle validity check that throws a cancellation error when
  ///   invalidated.
  /// - [timing]: The startup duration recorder, or null to omit timing.
  ///
  /// Returns the new generation task identifier.
  Future<String> start({
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext? context,
    bool faceRestoration = false,
    required void Function() ensureCurrent,
    RealtimeTiming? timing,
  }) async {
    final resolvedContext = validateContext(context);

    final taskID = _taskIDGenerator();
    final startVersion = _startVersion;
    GenerationStartConfirmation? ownedConfirmation;

    try {
      timing?.beginSignal();

      final confirmation = await _streamController.beginGeneration(
        taskID: taskID,
        videoFormat: videoFormat,
        context: resolvedContext,
        faceRestoration: faceRestoration,
        targetSize: _streamController.targetSize,
      );

      ownedConfirmation = confirmation;
      _startConfirmation = confirmation;
      if (startVersion != _startVersion) {
        confirmation.cancel();
      }

      await confirmation.value;
      timing?.confirmRemoteStream();
      if (startVersion != _startVersion) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime generation start cancelled',
        );
      }

      ensureCurrent();

      _interactionController.startInteraction(
        taskID: taskID,
        videoFormat: videoFormat,
      );

      _currentContext = resolvedContext;
      _currentFaceRestoration = faceRestoration;

      return taskID;
    } catch (error) {
      // The start message may already have arrived; stop the server task if a later step fails.
      try {
        await _streamController.stopGeneration(taskID: taskID);
      } catch (_) {
        // Preserve the start error; the connection coordinator remains responsible for room cleanup.
      }

      throw XmaxError.from(error);
    } finally {
      if (identical(
        _startConfirmation,
        ownedConfirmation,
      )) {
        _startConfirmation = null;
      }
    }
  }

  /// Resolves supplied or cached conditions, rejecting a first start without conditions.
  ///
  /// Parameters:
  /// - [context]: The requested conditions; null reuses the most recently submitted conditions.
  ///
  /// Returns the supplied or cached generation conditions.
  RealtimeContext validateContext(
    RealtimeContext? context,
  ) {
    final resolvedContext = context ?? _currentContext;

    if (resolvedContext == null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'A realtime context is required for the first generation',
      );
    }

    return resolvedContext;
  }

  /// Updates generation conditions and face restoration, caching them after successful submission.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  /// - [context]: The updated conditions; null reuses the most recently submitted conditions.
  /// - [faceRestoration]: Whether to restore the original face; defaults to false and is submitted
  ///   on every call.
  Future<void> update({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext? context,
    bool faceRestoration = false,
  }) async {
    _interactionController.startInteraction(
      taskID: taskID,
      videoFormat: videoFormat,
    );

    final resolvedContext = validateContext(context);

    await _streamController.updateGeneration(
      taskID: taskID,
      videoFormat: videoFormat,
      context: resolvedContext,
      faceRestoration: faceRestoration,
      targetSize: _streamController.targetSize,
    );

    _currentContext = resolvedContext;
    _currentFaceRestoration = faceRestoration;
  }

  /// Cancels pending startup and stops generation and interactions.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  Future<void> stop({
    required String taskID,
  }) async {
    cancelPendingStart();
    _interactionController.stopInteraction();
    await _streamController.stopGeneration(taskID: taskID);
  }

  /// Stops generation and interactions and clears cached conditions.
  ///
  /// Parameters:
  /// - [taskID]: The task identifier; an empty string stops the current active generation.
  Future<void> reset({
    String taskID = '',
  }) async {
    _currentContext = null;
    _currentFaceRestoration = false;
    await stop(taskID: taskID);
  }

  /// Creates a random task identifier with a task- prefix and Flutter platform query fields.
  ///
  /// Returns a random task identifier with an os=flutter-platform query field.
  static String createTaskID() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      16,
      (
        _,
      ) => random.nextInt(256),
    );

    // Encode 128 random bits as unpadded base64url.
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final output = StringBuffer('task-');

    for (var index = 0; index < bytes.length; index += 3) {
      final remaining = bytes.length - index;
      final value =
          (bytes[index] << 16) |
          (remaining > 1 ? bytes[index + 1] << 8 : 0) |
          (remaining > 2 ? bytes[index + 2] : 0);

      output.write(alphabet[(value >> 18) & 63]);
      output.write(alphabet[(value >> 12) & 63]);
      if (remaining > 1) {
        output.write(alphabet[(value >> 6) & 63]);
      }

      if (remaining > 2) {
        output.write(alphabet[value & 63]);
      }
    }

    // Identify the client platform with a query field without changing the random task identifier.
    output.write('?os=flutter-${Platform.operatingSystem}');

    return output.toString();
  }
}
