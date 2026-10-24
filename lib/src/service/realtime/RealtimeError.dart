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

/// An internal callback receiving normalized runtime failures.
///
/// Parameters:
/// - [error]: The operation error.
typedef RealtimeErrorListener =
    void Function(
      XmaxError error,
    );
