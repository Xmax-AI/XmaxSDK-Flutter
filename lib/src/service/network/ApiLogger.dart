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

/// Logs request results and duration without credentials or complete response content.
abstract final class ApiLogger {

  /// Logs the request result, response byte count, and duration.
  ///
  /// Parameters:
  /// - [method]: The request's HTTP method.
  /// - [path]: The relative API path.
  /// - [statusCode]: The HTTP response status.
  /// - [bodyByteCount]: The actual response body byte count.
  /// - [durationMs]: The request duration, in milliseconds.
  /// - [successful]: Whether the request succeeded.
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
      XmaxLogger.debug(
        category: XmaxLoggerCategory.api,
        message: message,
      );
    } else {
      XmaxLogger.error(
        category: XmaxLoggerCategory.api,
        message: message,
      );
    }
  }

  /// Logs the request failure reason and duration.
  ///
  /// Parameters:
  /// - [method]: The request's HTTP method.
  /// - [path]: The relative API path.
  /// - [error]: The operation error.
  /// - [durationMs]: The request duration, in milliseconds.
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

  /// Builds a request result log without response body content.
  ///
  /// Parameters:
  /// - [method]: The request's HTTP method.
  /// - [path]: The relative API path.
  /// - [statusCode]: The HTTP response status.
  /// - [bodyByteCount]: The actual response body byte count.
  /// - [durationMs]: The request duration, in milliseconds.
  ///
  /// Returns a log containing the HTTP method, path, status, response size, and duration.
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
