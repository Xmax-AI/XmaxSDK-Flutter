//
//  PermissionManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// An interface for checking and requesting media capture permissions.
abstract interface class PermissionManaging {

  /// Checks and requests camera permission; throws cameraPermissionDenied if denied.
  Future<void> ensureCameraPermission();

  /// Checks and requests microphone permission; throws microphonePermissionDenied if denied.
  Future<void> ensureMicrophonePermission();
}
