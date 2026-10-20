//
//  VideoContentMode.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 视频在视图中的缩放和裁剪方式。
enum VideoContentMode {

  /// 等比缩放并完整显示视频，多余区域保留黑边。
  fit('fit'),

  /// 等比填满视图，超出边界的视频区域会裁剪。
  fill('fill');

  /// 定义视频缩放模式标识。
  const VideoContentMode(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}
