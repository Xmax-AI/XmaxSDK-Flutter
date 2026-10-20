//
//  InteractionFrame.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../foundation/media/video/VideoContentMode.dart';

/// 一次交互采样的触点集合、视图尺寸和视频缩放模式。
final class InteractionFrame {

  /// 创建视图交互采样快照。
  const InteractionFrame({
    required this.points,
    required this.viewportSize,
    required this.contentMode,
  });

  /// 本次采样的触点集合，顺序保持不变。
  final List<Offset> points;

  /// 视频视图的逻辑像素尺寸。
  final Size viewportSize;

  /// 视频的缩放和裁剪方式。
  final VideoContentMode contentMode;
}
