//
//  PermissionManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:permission_handler/permission_handler.dart';

import '../errors/ErrorNormalizer.dart';
import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import 'PermissionManaging.dart';

/// 检查并按需申请摄像头或麦克风权限，拒绝时返回明确的 SDK 错误。
final class PermissionManager implements PermissionManaging {

  /// 创建媒体权限检查入口。
  const PermissionManager();

  /// 检查并按需申请摄像头权限；拒绝时抛出 cameraPermissionDenied。
  @override
  Future<void> ensureCameraPermission() => _ensurePermission(
    Permission.camera,
    errorCode: XmaxErrorCode.cameraPermissionDenied,
    errorMessage: 'Camera permission is unavailable or was denied',
  );

  /// 检查并按需申请麦克风权限；拒绝时抛出 microphonePermissionDenied。
  @override
  Future<void> ensureMicrophonePermission() => _ensurePermission(
    Permission.microphone,
    errorCode: XmaxErrorCode.microphonePermissionDenied,
    errorMessage: 'Microphone permission is unavailable or was denied',
  );

  /// 检查指定权限，未授权时发起申请，拒绝时抛出约定错误。
  ///
  /// - [permission]：当前请求检查或申请的媒体权限。
  /// - [errorCode]：权限拒绝时应抛出的 SDK 错误码。
  /// - [errorMessage]：权限拒绝时提供的错误描述。
  Future<void> _ensurePermission(
    Permission permission, {
    required XmaxErrorCode errorCode,
    required String errorMessage,
  }) async {
    PermissionStatus status;

    try {
      status = await permission.status;
      if (!status.isGranted) {
        status = await permission.request();
      }
    } catch (error) {
      XmaxLogger.error(
        category: XmaxLoggerCategory.permission,
        message:
            '权限申请失败 (Permission Request Failed)\n'
            '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}${ErrorNormalizer.description(error)}',
      );
      throw XmaxError(code: errorCode, message: errorMessage);
    }

    if (!status.isGranted) {
      throw XmaxError(code: errorCode, message: errorMessage);
    }
  }
}
