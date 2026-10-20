//
//  EncodingController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/RtcModels.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'EncodingBitratePolicy.dart';
import 'EncodingControlling.dart';

/// 将传输规格及其码率预算应用到当前 RTC 编码器。
final class EncodingController implements EncodingControlling {

  /// 创建视频编码配置控制器。
  const EncodingController({
    required RtcManaging rtcManager,
  }) : _rtcManager = rtcManager;

  /// RTC 采集、房间及传输操作入口。
  final RtcManaging _rtcManager;

  /// 按视频规格解析码率预算，并提交 RTC 编码配置。
  ///
  /// - [format]：目标视频尺寸、帧率和编码配置。
  @override
  Future<void> configure(
    RealtimeVideoFormat format,
  ) async {
    final budget = EncodingBitratePolicy.resolve(format);

    await _rtcManager.configureVideoEncoding(
      VideoEncodingConfiguration(
        width: format.width,
        height: format.height,
        frameRate: format.fps,
        minimumBitrate: budget.$1,
        maximumBitrate: budget.$2,
        encoderPreference: format.encoderPreference,
      ),
    );
  }
}
