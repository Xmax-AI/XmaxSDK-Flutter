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

/// An interface for RTC engine creation and native resource release.
abstract interface class RtcPlatform {

  /// The native RTC engine in use.
  RtcEngineEx get engine;

  /// Releases RTC resources and invalidates subsequent native callbacks.
  Future<void> destroy();
}
