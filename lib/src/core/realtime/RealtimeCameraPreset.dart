//
//  RealtimeCameraPreset.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:ui';

/// A camera resolution preset whose availability depends on the selected model.
///
/// Updating with a preset preserves the current frame rate, bitrate, and encoding preference.
enum RealtimeCameraPreset {

  /// A landscape 1920 × 1080 frame.
  resolution1920x1080(
    1920,
    1080,
  ),

  /// A portrait 1080 × 1920 frame.
  resolution1080x1920(
    1080,
    1920,
  ),

  /// A square 1408 × 1408 frame.
  resolution1408x1408(
    1408,
    1408,
  ),

  /// A portrait 1152 × 1536 frame.
  resolution1152x1536(
    1152,
    1536,
  ),

  /// A landscape 1536 × 1152 frame.
  resolution1536x1152(
    1536,
    1152,
  );

  /// Defines a capture resolution preset.
  const RealtimeCameraPreset(
    this._width,
    this._height,
  );

  /// The preset width, in pixels.
  final int _width;

  /// The preset height, in pixels.
  final int _height;

  /// The frame dimensions, in pixels.
  Size get size => Size(
    _width.toDouble(),
    _height.toDouble(),
  );
}
