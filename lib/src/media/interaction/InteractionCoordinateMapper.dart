//
//  InteractionCoordinateMapper.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../foundation/media/video/VideoContentMode.dart';
import '../../service/realtime/RealtimePoint.dart';

/// 依据视频缩放和裁剪区域，将视图坐标转换为归一化媒体坐标。
abstract final class InteractionCoordinateMapper {

  /// 计算视频按给定缩放模式显示在视图中的实际区域。
  ///
  /// - [viewportSize]：视频视图的逻辑像素尺寸。
  /// - [videoSize]：视频宽高，单位为像素。
  /// - [contentMode]：视频的缩放和裁剪方式。
  ///
  /// 返回视频在视图中的显示区域；尺寸无效时返回 null。
  static Rect? displayedFrame({
    required Size viewportSize,
    required Size videoSize,
    required VideoContentMode contentMode,
  }) {
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        videoSize.width <= 0 ||
        videoSize.height <= 0) {
      return null;
    }

    final widthScale = viewportSize.width / videoSize.width;
    final heightScale = viewportSize.height / videoSize.height;

    // 填满模式按较大的缩放比例裁剪，完整显示模式按较小的比例保留留白。
    final scale = contentMode == VideoContentMode.fill
        ? math.max(widthScale, heightScale)
        : math.min(widthScale, heightScale);
    final displayedSize = Size(
      videoSize.width * scale,
      videoSize.height * scale,
    );

    return Rect.fromLTWH(
      (viewportSize.width - displayedSize.width) / 2,
      (viewportSize.height - displayedSize.height) / 2,
      displayedSize.width,
      displayedSize.height,
    );
  }

  /// 将视图触点转换为归一化媒体坐标；黑边或无效尺寸不产生采样。
  ///
  /// - [point]：视图内的单个触点位置。
  /// - [viewportSize]：视频视图的逻辑像素尺寸。
  /// - [videoSize]：视频宽高，单位为像素。
  /// - [contentMode]：视频的缩放和裁剪方式。
  ///
  /// 返回 0～1 范围的媒体坐标；位于黑边或尺寸无效时返回 null。
  static RealtimePoint? map({
    required Offset point,
    required Size viewportSize,
    required Size videoSize,
    required VideoContentMode contentMode,
  }) {
    final frame = displayedFrame(
      viewportSize: viewportSize,
      videoSize: videoSize,
      contentMode: contentMode,
    );

    if (!point.dx.isFinite || !point.dy.isFinite || frame == null) {
      return null;
    }

    if (contentMode == VideoContentMode.fit && !frame.contains(point)) {
      return null;
    }

    // 按实际显示的媒体区域归一化，同时扣除裁剪或留白产生的偏移。
    final x = ((point.dx - frame.left) / frame.width).clamp(0.0, 1.0);
    final y = ((point.dy - frame.top) / frame.height).clamp(0.0, 1.0);

    return RealtimePoint(x: x.toDouble(), y: y.toDouble());
  }
}
