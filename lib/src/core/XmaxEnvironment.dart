//
//  XmaxEnvironment.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Xmax 服务环境。
enum XmaxEnvironment {

  /// 国内环境。
  china,

  /// 海外环境。
  global;

  /// 实时会话的 API 根地址；存储等通用服务仍使用各环境的通用地址。
  Uri get realtimeApiBaseURL => Uri.parse(switch (this) {
    XmaxEnvironment.china => 'https://cloud.xmax.22duck.cn/open/api/v1',
    XmaxEnvironment.global => 'https://api.xmax.ai/open/api/v1',
  });
}
