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

/// Converts view coordinates into normalized media coordinates using the video scaling and crop
/// region.
abstract final class InteractionCoordinateMapper {

  /// Calculates the video's display region for the specified scaling mode.
  ///
  /// Parameters:
  /// - [viewportSize]: The video view dimensions, in logical pixels.
  /// - [videoSize]: The video width and height, in pixels.
  /// - [contentMode]: The video scaling and cropping mode.
  ///
  /// Returns the video display region, or null if the dimensions are invalid.
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

    // Fill uses the larger scale and crops; fit uses the smaller scale and leaves unused space.
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

  /// Converts a view point into normalized media coordinates, excluding letterboxing and invalid
  /// dimensions.
  ///
  /// Parameters:
  /// - [point]: A single interaction point within the view.
  /// - [viewportSize]: The video view dimensions, in logical pixels.
  /// - [videoSize]: The video width and height, in pixels.
  /// - [contentMode]: The video scaling and cropping mode.
  ///
  /// Returns media coordinates from 0 to 1, or null for letterboxing or invalid dimensions.
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

    // Normalize against the displayed media region, accounting for crop or letterbox offsets.
    final x = ((point.dx - frame.left) / frame.width).clamp(
      0.0,
      1.0,
    );
    final y = ((point.dy - frame.top) / frame.height).clamp(
      0.0,
      1.0,
    );

    return RealtimePoint(
      x: x.toDouble(),
      y: y.toDouble(),
    );
  }
}
