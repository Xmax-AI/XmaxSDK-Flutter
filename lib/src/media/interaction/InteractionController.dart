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

/// 将指定生成任务的触点发送给服务端。
///
/// - [taskID]：当前生成任务标识。
/// - [points]：归一化后的媒体坐标，顺序与采样一致。
typedef InteractionListener =
    Future<void> Function(
      String taskID,
      List<RealtimePoint> points,
    );

/// 将触点映射到媒体坐标，合并待发采样并隔离不同生成任务。
final class InteractionController implements InteractionControlling {

  /// 创建触点映射与任务采样控制器。
  InteractionController({
    required InteractionListener listener,
  }) : _listener = listener;

  /// 提交当前任务归一化触点的处理函数。
  final InteractionListener _listener;

  /// 当前生成任务标识。
  String? _taskID;

  /// 视频尺寸、帧率和编码配置。
  RealtimeVideoFormat? _videoFormat;

  /// 当前任务最新一组尚未提交的归一化触点。
  List<RealtimePoint>? _pendingPoints;

  /// 是否正在发送触点采样。
  bool _draining = false;

  /// 触点发送循环的版本号，用于忽略旧任务的发送结果。
  int _drainGeneration = 0;

  /// 为当前生成任务启用交互输入，并清除旧任务的待发采样。
  ///
  /// 详细说明见 [InteractionControlling.startInteraction]。
  @override
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  }) {
    _cancelPendingFrames();
    _taskID = taskID;
    _videoFormat = videoFormat;
  }

  /// 停止交互输入，并使尚未提交的采样失效。
  @override
  void stopInteraction() {
    _taskID = null;
    _videoFormat = null;
    _cancelPendingFrames();
  }

  /// 提交当前视图触点采样；没有有效生成任务时忽略。
  ///
  /// - [frame]：一次视图触点采样。
  @override
  void submitInteraction(
    InteractionFrame frame,
  ) {
    final taskID = _taskID;
    final format = _videoFormat;

    if (taskID == null || format == null || frame.points.isEmpty) {
      return;
    }

    final videoSize = Size(format.width.toDouble(), format.height.toDouble());
    final points = frame.points
        .map(
          (point) => InteractionCoordinateMapper.map(
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

    // 只保留最新一组待发触点，避免采样不断堆积。
    _pendingPoints = points;

    if (!_draining) {
      unawaited(_drain(_drainGeneration));
    }
  }

  /// 清除待发交互采样，并使旧任务的发送完成回调失效。
  void _cancelPendingFrames() {
    // 已提交的 RTC 消息无法撤回，因此用版本号使旧发送循环失效。
    // 新任务可立即发送，旧回调不能取走新触点或清除新任务的发送标记，任务标识相同也不例外。
    _drainGeneration += 1;
    _pendingPoints = null;
    _draining = false;
  }

  /// 发送最新一组待发触点，等待期间收到的新采样仅保留最后一组。
  ///
  /// - [generation]：本次发送循环的版本号；版本变化后停止发送。
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
          await _listener(taskID, points);
        } catch (error) {
          if (generation != _drainGeneration) return;

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
