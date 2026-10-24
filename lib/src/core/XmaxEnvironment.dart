//
//  XmaxEnvironment.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The Xmax service environment.
enum XmaxEnvironment {

  /// The China service environment.
  china,

  /// The global service environment.
  global;

  /// The base URL for realtime session requests; general services use the environment's general
  /// API.
  Uri get realtimeApiBaseURL => Uri.parse(switch (this) {
    XmaxEnvironment.china => 'https://cloud.xmax.22duck.cn/open/api/v1',
    XmaxEnvironment.global => 'https://api.xmax.ai/open/api/v1',
  });
}
