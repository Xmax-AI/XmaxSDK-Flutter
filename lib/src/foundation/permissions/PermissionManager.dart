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

/// Checks and requests camera or microphone permission, reporting permission-specific SDK errors on
/// denial.
final class PermissionManager implements PermissionManaging {

  /// Creates a media permission checker.
  const PermissionManager();

  /// Checks and requests camera permission; throws cameraPermissionDenied if denied.
  @override
  Future<void> ensureCameraPermission() => _ensurePermission(
    Permission.camera,
    errorCode: XmaxErrorCode.cameraPermissionDenied,
    errorMessage: 'Camera permission is unavailable or was denied',
  );

  /// Checks and requests microphone permission; throws microphonePermissionDenied if denied.
  @override
  Future<void> ensureMicrophonePermission() => _ensurePermission(
    Permission.microphone,
    errorCode: XmaxErrorCode.microphonePermissionDenied,
    errorMessage: 'Microphone permission is unavailable or was denied',
  );

  /// Checks a permission, requests it if needed, and throws the specified error on denial.
  ///
  /// Parameters:
  /// - [permission]: The media permission to check or request.
  /// - [errorCode]: The SDK error code to throw if permission is denied.
  /// - [errorMessage]: The error description to provide if permission is denied.
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
      throw XmaxError(
        code: errorCode,
        message: errorMessage,
      );
    }

    if (!status.isGranted) {
      throw XmaxError(
        code: errorCode,
        message: errorMessage,
      );
    }
  }
}
