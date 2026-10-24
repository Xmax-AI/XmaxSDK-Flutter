//
//  ErrorMessageFormatter.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'ErrorNormalizer.dart';
import 'XmaxError.dart';

/// Formats errors for logs and diagnostic displays.
abstract final class ErrorMessageFormatter {

  /// Formats SDK, platform, and third-party errors as readable descriptions.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns a readable error description.
  static String format(
    Object error,
  ) {
    if (error is XmaxError) {
      final apiCode = error.apiCode == null ? '' : '，业务码 ${error.apiCode}';
      final httpStatus = error.httpStatus == null
          ? ''
          : '，HTTP ${error.httpStatus}';

      return '${error.message}（${error.code.value}$apiCode$httpStatus）';
    }

    final message = ErrorNormalizer.description(error);
    final platformCode = ErrorNormalizer.platformErrorCode(error);

    return platformCode == null ? message : '$message（平台错误码：$platformCode）';
  }
}
