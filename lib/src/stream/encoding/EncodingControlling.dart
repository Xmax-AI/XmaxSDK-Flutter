//
//  EncodingControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';

/// 将视频规格和码率策略应用到 RTC 编码器的接口。
abstract interface class EncodingControlling {

  /// 按视频规格解析码率预算，并提交 RTC 编码配置。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  Future<void> configure(
    RealtimeVideoFormat videoFormat,
  );
}
