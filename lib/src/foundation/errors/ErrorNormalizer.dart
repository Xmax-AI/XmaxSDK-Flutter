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

/// Normalizes Dart and platform exceptions for SDK error reporting.
abstract final class ErrorNormalizer {

  /// Extracts an error description suitable for display.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns the error message, falling back to the exception type when empty.
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

  /// Extracts a platform error code, or null when unrecognized.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns the operating system error code when recognizable, or null otherwise.
  static int? platformErrorCode(
    Object error,
  ) => switch (error) {
    SocketException(:final osError?) => osError.errorCode,
    FileSystemException(:final osError?) => osError.errorCode,
    OSError(:final errorCode) => errorCode,
    _ => null,
  };

  /// Identifies exceptions caused by deliberate cancellation or request termination.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns whether the error represents deliberate HTTP request termination.
  static bool isCancellation(
    Object error,
  ) =>
      error is HttpException &&
      error.message.trim().toLowerCase() == 'request has been aborted';
}
