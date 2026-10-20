//
//  ApiLogger.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/ErrorMessageFormatter.dart';
import '../../foundation/logging/XmaxLogger.dart';
import 'ApiServicing.dart';

/// 记录请求结果与耗时，不记录访问凭证或完整响应内容。
abstract final class ApiLogger {

  /// 记录请求结果、响应字节数及耗时。
  ///
  /// - [method]：请求使用的 HTTP 方法。
  /// - [path]：API 相对路径。
  /// - [statusCode]：HTTP 响应状态码。
  /// - [bodyByteCount]：响应体的实际字节数。
  /// - [durationMs]：请求耗时，单位为毫秒。
  /// - [successful]：请求是否成功。
  static void logResponse({
    required ApiMethod method,
    required String path,
    required int statusCode,
    required int bodyByteCount,
    required int durationMs,
    required bool successful,
  }) {
    final message = responseMessage(
      method: method,
      path: path,
      statusCode: statusCode,
      bodyByteCount: bodyByteCount,
      durationMs: durationMs,
    );

    if (successful) {
      XmaxLogger.debug(category: XmaxLoggerCategory.api, message: message);
    } else {
      XmaxLogger.error(category: XmaxLoggerCategory.api, message: message);
    }
  }

  /// 记录请求失败原因及耗时。
  ///
  /// - [method]：请求使用的 HTTP 方法。
  /// - [path]：API 相对路径。
  /// - [error]：本次操作的错误。
  /// - [durationMs]：请求耗时，单位为毫秒。
  static void logFailure({
    required ApiMethod method,
    required String path,
    required Object error,
    required int durationMs,
  }) {
    XmaxLogger.error(
      category: XmaxLoggerCategory.api,
      message:
          '${method.value} $path 失败 (Request Failed)\n'
          '├─ ${XmaxLogger.localized('耗时：', 'Duration: ')}$durationMs ms\n'
          '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}${ErrorMessageFormatter.format(error)}',
    );
  }

  /// 构造不包含响应正文的请求结果日志。
  ///
  /// - [method]：请求使用的 HTTP 方法。
  /// - [path]：API 相对路径。
  /// - [statusCode]：HTTP 响应状态码。
  /// - [bodyByteCount]：响应体的实际字节数。
  /// - [durationMs]：请求耗时，单位为毫秒。
  ///
  /// 返回包含 HTTP 方法、路径、状态码、响应大小和耗时的日志文本。
  static String responseMessage({
    required ApiMethod method,
    required String path,
    required int statusCode,
    required int bodyByteCount,
    required int durationMs,
  }) =>
      '${method.value} $path\n'
      '├─ ${XmaxLogger.localized('状态：', 'Status: ')}$statusCode\n'
      '├─ ${XmaxLogger.localized('耗时：', 'Duration: ')}$durationMs ms\n'
      '└─ ${XmaxLogger.localized('响应：', 'Response Size: ')}$bodyByteCount bytes';
}
