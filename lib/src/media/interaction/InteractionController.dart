//
//  InteractionController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../foundation/logging/XmaxLogger.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'InteractionControlling.dart';
import 'InteractionCoordinateMapper.dart';
import 'InteractionFrame.dart';

/// Sends interaction points for the specified generation task to the server.
///
/// Parameters:
/// - [taskID]: The current generation task identifier.
/// - [points]: Normalized media coordinates in sampling order.
typedef InteractionListener =
    Future<void> Function(
      String taskID,
      List<RealtimePoint> points,
    );

/// Maps input to media coordinates, coalesces pending samples, and isolates generation tasks.
final class InteractionController implements InteractionControlling {

  /// Creates an interaction mapping and task sampling controller.
  InteractionController({
    required InteractionListener listener,
  }) : _listener = listener;

  /// The handler that submits normalized points for the current task.
  final InteractionListener _listener;

  /// The current generation task identifier.
  String? _taskID;

  /// The video dimensions, frame rate, and encoding settings.
  RealtimeVideoFormat? _videoFormat;

  /// The latest pending normalized points for the current task.
  List<RealtimePoint>? _pendingPoints;

  /// Whether interaction samples are being sent.
  bool _draining = false;

  /// The send-loop version used to discard results from older tasks.
  int _drainGeneration = 0;

  /// Enables interaction for the current task and clears pending samples from the previous task.
  ///
  /// See [InteractionControlling.startInteraction] for the usage contract.
  @override
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  }) {
    _cancelPendingFrames();
    _taskID = taskID;
    _videoFormat = videoFormat;
  }

  /// Stops interaction input and invalidates pending samples.
  @override
  void stopInteraction() {
    _taskID = null;
    _videoFormat = null;
    _cancelPendingFrames();
  }

  /// Submits view interaction samples; ignored when no generation task is active.
  ///
  /// Parameters:
  /// - [frame]: A view interaction sample.
  @override
  void submitInteraction(
    InteractionFrame frame,
  ) {
    final taskID = _taskID;
    final format = _videoFormat;

    if (taskID == null || format == null || frame.points.isEmpty) {
      return;
    }

    final videoSize = Size(
      format.width.toDouble(),
      format.height.toDouble(),
    );
    final points = frame.points
        .map(
          (
            point,
          ) => InteractionCoordinateMapper.map(
            point: point,
            viewportSize: frame.viewportSize,
            videoSize: videoSize,
            contentMode: frame.contentMode,
          ),
        )
        .whereType<RealtimePoint>()
        .toList(growable: false);

    if (points.isEmpty) {
      return;
    }

    // Keep only the latest pending sample to prevent an unbounded input backlog.
    _pendingPoints = points;

    if (!_draining) {
      unawaited(_drain(_drainGeneration));
    }
  }

  /// Clears pending interaction samples and invalidates send completions from older tasks.
  void _cancelPendingFrames() {
    // Submitted RTC messages cannot be recalled; invalidate old send loops by version instead.
    // New tasks can send immediately; stale callbacks cannot consume their points or clear their sending state.
    _drainGeneration += 1;
    _pendingPoints = null;
    _draining = false;
  }

  /// Sends the latest pending points, retaining only the newest sample received while awaiting
  /// delivery.
  ///
  /// Parameters:
  /// - [generation]: The send-loop version; stop sending if the version changes.
  Future<void> _drain(
    int generation,
  ) async {
    _draining = true;

    try {
      while (generation == _drainGeneration &&
          _taskID != null &&
          _pendingPoints != null) {
        final taskID = _taskID!;
        final points = _pendingPoints!;

        _pendingPoints = null;

        try {
          await _listener(
            taskID,
            points,
          );
        } catch (error) {
          if (generation != _drainGeneration) {
            return;
          }

          XmaxLogger.warn(
            category: XmaxLoggerCategory.interaction,
            message:
                '发送交互轨迹失败，已丢弃当前采样帧 '
                '(Failed to Send Interaction Trajectory; Current Sample Dropped)\n'
                '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
          );
        }
      }
    } finally {
      if (generation == _drainGeneration) {
        _draining = false;
        if (_taskID != null && _pendingPoints != null) {
          unawaited(_drain(generation));
        }
      }
    }
  }
}
