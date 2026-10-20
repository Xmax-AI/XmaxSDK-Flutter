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

/// SDK 向接入方暴露的统一错误码。
enum XmaxErrorCode {

  /// 访问 API 所需的密钥为空或无效。
  invalidAPIKey('INVALID_API_KEY'),

  /// 参数或配置不满足 SDK 的调用约束。
  invalidConfiguration('INVALID_CONFIGURATION'),

  /// 未分类的内部执行错误。
  internalError('INTERNAL_ERROR'),

  /// HTTP 网络传输失败。
  networkError('NETWORK_ERROR'),

  /// 服务端业务请求失败。
  apiError('API_ERROR'),

  /// 云端会话状态无效或 RTC 凭证解析失败。
  sessionError('SESSION_ERROR'),

  /// RTC 引擎、房间或媒体传输失败。
  rtcError('RTC_ERROR'),

  /// 本地媒体采集或处理失败。
  mediaError('MEDIA_ERROR'),

  /// 当前运行环境不支持请求的插帧能力。
  frameInterpolationUnsupported('FRAME_INTERPOLATION_UNSUPPORTED'),

  /// 摄像头采集权限被拒绝。
  cameraPermissionDenied('CAMERA_PERMISSION_DENIED'),

  /// 麦克风采集权限被拒绝。
  microphonePermissionDenied('MICROPHONE_PERMISSION_DENIED'),

  /// 对象上传失败。
  uploadError('UPLOAD_ERROR'),

  /// 文件下载或目标写入失败。
  downloadError('DOWNLOAD_ERROR'),

  /// 图片未通过内容安全检查。
  unsafeImage('UNSAFE_IMAGE'),

  /// 主动取消操作对应的 SDK 错误。
  cancelled('CANCELLED'),

  /// 操作等待时间超过规定时限。
  timeout('TIMEOUT');

  /// 定义错误码的序列化标识。
  const XmaxErrorCode(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}

/// 表示 SDK 抛出或通过回调通知接入方的统一错误。
final class XmaxError implements Exception {

  /// 创建 SDK 错误信息。
  const XmaxError({
    required this.code,
    required this.message,
    this.apiCode,
    this.httpStatus,
  });

  /// SDK 统一错误码。
  final XmaxErrorCode code;

  /// 对外提供的错误描述，不应包含访问凭证。
  final String message;

  /// 云端返回的业务错误码；不可用时为空。
  final int? apiCode;

  /// HTTP 响应状态码；不可用时为空。
  final int? httpStatus;

  /// 保留已有 SDK 错误，或将其他异常转换为统一内部错误。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回统一 SDK 错误。
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

  /// 生成当前错误的文本描述。
  ///
  /// 返回包含 SDK 错误码和错误消息的文本。
  @override
  String toString() => 'XmaxError(${code.value}): $message';

  /// 与 [other] 比较类型及 [code]、[message]、[apiCode]、[httpStatus] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is XmaxError &&
          code == other.code &&
          message == other.message &&
          apiCode == other.apiCode &&
          httpStatus == other.httpStatus;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(code, message, apiCode, httpStatus);
}
