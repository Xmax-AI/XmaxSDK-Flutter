//
//  RealtimeError.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';

/// 接收统一 SDK 运行错误的内部回调。
///
/// - [error]：本次操作的错误。
typedef RealtimeErrorListener =
    void Function(
      XmaxError error,
    );
