//
//  RealtimeVideoFormat.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';

/// 实时视频的编码策略偏好。
enum RealtimeVideoEncoderPreference {

  /// 平衡帧率和分辨率。
  auto,

  /// 优先保障帧率。
  maintainFramerate,

  /// 优先保障分辨率。
  maintainQuality,
}

/// 实时视频的尺寸、帧率和上传编码配置。
///
/// 构造时只保存配置；需要提前检查参数时可调用 [validate]。
final class RealtimeVideoFormat {

  /// 创建实时视频规格。
  const RealtimeVideoFormat({
    required this.width,
    required this.height,
    required this.fps,
    this.minimumBitrate,
    this.maximumBitrate,
    this.encoderPreference = RealtimeVideoEncoderPreference.maintainFramerate,
  });

  /// 视频宽度，单位为像素，必须为正偶数。
  final int width;

  /// 视频高度，单位为像素，必须为正偶数。
  final int height;

  /// 目标视频帧率，单位为 fps，必须大于 0。
  final int fps;

  /// 最低上传码率，单位为 kbps；省略时使用 500，且不超过最高码率。
  /// 0 表示不设最低码率。
  final int? minimumBitrate;

  /// 最高上传码率，单位为 kbps；`null` 使用 SDK 默认值，指定时必须大于 0。
  final int? maximumBitrate;

  /// 上传编码策略偏好，默认优先保障帧率。
  final RealtimeVideoEncoderPreference encoderPreference;

  /// 校验尺寸、帧率及码率区间，不满足约束时抛出 invalidConfiguration。
  ///
  /// 宽高须为正偶数，帧率须为正数；指定码率时最低值不得超过最高值。
  void validate() {
    if (width <= 0 || height <= 0 || fps <= 0 || width.isOdd || height.isOdd) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Realtime video width and height must be positive even '
            'numbers, and fps must be greater than zero',
      );
    }

    final minimum = minimumBitrate;
    final maximum = maximumBitrate;

    if (minimum != null && minimum < 0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Minimum bitrate must not be negative',
      );
    }

    if (maximum != null && maximum <= 0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Maximum bitrate must be greater than zero',
      );
    }

    if (minimum != null && maximum != null && minimum > maximum) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Minimum bitrate must not exceed maximum bitrate',
      );
    }
  }

  /// 创建新尺寸的视频规格，保留原帧率、码率和编码偏好。
  ///
  /// - [width]：视频宽度，单位为像素。
  /// - [height]：视频高度，单位为像素。
  ///
  /// 返回包含新尺寸的独立视频规格；不修改原对象，也不在此方法中执行校验。
  RealtimeVideoFormat resized({
    required int width,
    required int height,
  }) => RealtimeVideoFormat(
    width: width,
    height: height,
    fps: fps,
    minimumBitrate: minimumBitrate,
    maximumBitrate: maximumBitrate,
    encoderPreference: encoderPreference,
  );

  /// 与 [other] 比较类型及 [width]、[height]、[fps]、[minimumBitrate]、[maximumBitrate]、[encoderPreference] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimeVideoFormat &&
          width == other.width &&
          height == other.height &&
          fps == other.fps &&
          minimumBitrate == other.minimumBitrate &&
          maximumBitrate == other.maximumBitrate &&
          encoderPreference == other.encoderPreference;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(
    width,
    height,
    fps,
    minimumBitrate,
    maximumBitrate,
    encoderPreference,
  );
}
