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
  ),

  /// A portrait 11:20 frame for X2.1 Flash.
  resolution704x1280(
    704,
    1280,
  ),

  /// The landscape 16:9 preset for X2.1 Flash.
  resolution1280x704(
    1280,
    704,
  ),

  /// A square frame for X2.1 Flash.
  resolution960x960(
    960,
    960,
  ),

  /// A landscape 4:3 frame for X2.1 Flash.
  resolution1024x768(
    1024,
    768,
  ),

  /// A portrait 3:4 frame for X2.1 Flash.
  resolution768x1024(
    768,
    1024,
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
