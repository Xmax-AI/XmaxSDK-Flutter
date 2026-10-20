//
//  CameraPosition.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 摄像头的前后置位置。
enum CameraPosition {

  /// 前置摄像头。
  front('front'),

  /// 后置摄像头。
  back('back');

  /// 定义摄像头位置标识。
  const CameraPosition(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}
