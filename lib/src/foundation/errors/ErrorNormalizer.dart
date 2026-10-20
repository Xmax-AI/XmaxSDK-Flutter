//
//  ErrorNormalizer.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:io';

/// 将 Dart 和平台异常转换为 SDK 对外提供的统一错误信息。
abstract final class ErrorNormalizer {

  /// 提取适合对外展示的错误描述。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回异常消息；消息为空时使用异常类型名称。
  static String description(
    Object error,
  ) {
    final description = switch (error) {
      HttpException(:final message) => message,
      SocketException(:final message) => message,
      FileSystemException(:final message) => message,
      FormatException(:final message) => message,
      TimeoutException(:final message?) => message,
      _ => error.toString(),
    }.trim();

    return description.isEmpty ? error.runtimeType.toString() : description;
  }

  /// 提取平台错误码；无法识别时返回 null。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回可识别的操作系统错误码；不可识别时为 null。
  static int? platformErrorCode(
    Object error,
  ) => switch (error) {
    SocketException(:final osError?) => osError.errorCode,
    FileSystemException(:final osError?) => osError.errorCode,
    OSError(:final errorCode) => errorCode,
    _ => null,
  };

  /// 识别主动取消或请求终止对应的异常。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回错误是否表示 HTTP 请求被主动终止。
  static bool isCancellation(
    Object error,
  ) =>
      error is HttpException &&
      error.message.trim().toLowerCase() == 'request has been aborted';
}
