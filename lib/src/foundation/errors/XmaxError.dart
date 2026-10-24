//
//  XmaxError.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'ErrorNormalizer.dart';

/// An error code reported by XmaxSDK.
enum XmaxErrorCode {

  /// The API key is empty or invalid.
  invalidAPIKey('INVALID_API_KEY'),

  /// The parameters or configuration violate the API contract.
  invalidConfiguration('INVALID_CONFIGURATION'),

  /// An otherwise unclassified internal failure.
  internalError('INTERNAL_ERROR'),

  /// An HTTP transport failure.
  networkError('NETWORK_ERROR'),

  /// A server API request failure.
  apiError('API_ERROR'),

  /// Invalid server session state or RTC credentials.
  sessionError('SESSION_ERROR'),

  /// An RTC engine, room, or media transport failure.
  rtcError('RTC_ERROR'),

  /// A local media capture or processing failure.
  mediaError('MEDIA_ERROR'),

  /// The runtime does not support the requested frame interpolation capability.
  frameInterpolationUnsupported('FRAME_INTERPOLATION_UNSUPPORTED'),

  /// Camera permission was denied.
  cameraPermissionDenied('CAMERA_PERMISSION_DENIED'),

  /// Microphone permission was denied.
  microphonePermissionDenied('MICROPHONE_PERMISSION_DENIED'),

  /// An object upload failure.
  uploadError('UPLOAD_ERROR'),

  /// A file download or destination write failure.
  downloadError('DOWNLOAD_ERROR'),

  /// The image failed its content safety check.
  unsafeImage('UNSAFE_IMAGE'),

  /// The operation was cancelled.
  cancelled('CANCELLED'),

  /// The operation exceeded its deadline.
  timeout('TIMEOUT');

  /// Defines an error code's serialized identifier.
  const XmaxErrorCode(
    this.value,
  );

  /// The serialized value.
  final String value;
}

/// An error thrown or delivered by XmaxSDK.
final class XmaxError implements Exception {

  /// Creates an SDK error.
  const XmaxError({
    required this.code,
    required this.message,
    this.apiCode,
    this.httpStatus,
  });

  /// The SDK error code.
  final XmaxErrorCode code;

  /// The public error description, which must not contain credentials.
  final String message;

  /// The server API error code, when provided.
  final int? apiCode;

  /// The HTTP response status code, when available.
  final int? httpStatus;

  /// Preserves an SDK error or wraps another exception as an internal error.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  ///
  /// Returns the normalized SDK error.
  static XmaxError from(
    Object error,
  ) {
    if (error is XmaxError) {
      return error;
    }

    return XmaxError(
      code: XmaxErrorCode.internalError,
      message: ErrorNormalizer.description(error),
    );
  }

  /// Formats this error as text.
  ///
  /// Returns the SDK error code and message as text.
  @override
  String toString() => 'XmaxError(${code.value}): $message';

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxError &&
          code == other.code &&
          message == other.message &&
          apiCode == other.apiCode &&
          httpStatus == other.httpStatus;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    code,
    message,
    apiCode,
    httpStatus,
  );
}
