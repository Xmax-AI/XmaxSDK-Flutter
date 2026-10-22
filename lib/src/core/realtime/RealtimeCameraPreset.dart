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

/// 摄像头采集分辨率预设；实际可用范围由当前模型决定。
///
/// 使用预设更新规格时保留当前帧率、码率设置和编码偏好。
enum RealtimeCameraPreset {

  /// 1920 × 1080 横屏。
  resolution1920x1080(1920, 1080),

  /// 1080 × 1920 竖屏。
  resolution1080x1920(1080, 1920),

  /// 1408 × 1408 方形。
  resolution1408x1408(1408, 1408),

  /// 1152 × 1536 竖屏。
  resolution1152x1536(1152, 1536),

  /// 1536 × 1152 横屏。
  resolution1536x1152(1536, 1152);

  /// 定义采集分辨率。
  const RealtimeCameraPreset(
    this._width,
    this._height,
  );

  /// 预设采集宽度，单位为像素。
  final int _width;

  /// 预设采集高度，单位为像素。
  final int _height;

  /// 预设采集尺寸，单位为像素。
  Size get size => Size(_width.toDouble(), _height.toDouble());
}
