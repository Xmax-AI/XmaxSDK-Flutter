//
//  RealtimeModelRouting.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeModel.dart';

/// 会话路由独立于存储服务环境，不对接入方暴露地址配置。
extension RealtimeModelRouting on RealtimeModel {

  /// 当前模型用于创建实时会话的 API 地址。
  Uri get apiBaseURL => Uri.parse(switch (this) {
    RealtimeModel.x2_1_1_preview_cn =>
      'https://cloud.xmax.22duck.cn/open/api/v1',
    RealtimeModel.x2_1_1_preview_us => 'https://api.xmax.ai/open/api/v1',
  });
}
