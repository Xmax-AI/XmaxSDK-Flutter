//
//  PermissionManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 媒体采集权限的检查与申请接口。
abstract interface class PermissionManaging {

  /// 检查并按需申请摄像头权限；拒绝时抛出 cameraPermissionDenied。
  Future<void> ensureCameraPermission();

  /// 检查并按需申请麦克风权限；拒绝时抛出 microphonePermissionDenied。
  Future<void> ensureMicrophonePermission();
}
