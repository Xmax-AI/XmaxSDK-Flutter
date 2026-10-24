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

/// The interaction points, viewport dimensions, and video scaling mode for one sample.
final class InteractionFrame {

  /// Creates a view interaction sample snapshot.
  const InteractionFrame({
    required this.points,
    required this.viewportSize,
    required this.contentMode,
  });

  /// The sampled interaction points, preserving their order.
  final List<Offset> points;

  /// The video view dimensions, in logical pixels.
  final Size viewportSize;

  /// The video scaling and cropping mode.
  final VideoContentMode contentMode;
}
