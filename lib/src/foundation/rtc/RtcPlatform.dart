//
//  RtcPlatform.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// 隔离 RTC 引擎的创建与原生资源释放。
abstract interface class RtcPlatform {

  /// 当前使用的原生 RTC 引擎。
  RtcEngine get engine;

  /// 关闭当前 RTC 资源，并使后续原生回调失效。
  Future<void> destroy();
}
