//
//  LocalStream.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// A local RTC input binding used by the rendering adapter.
final class LocalStream {

  /// Creates a preview binding without changing capture or publication.
  const LocalStream({
    this.engine,
    this.isExternal = false,
  });

  /// The native rendering engine; null leaves preview unavailable.
  final RtcEngineEx? engine;

  /// Whether preview uses custom pixels rather than the built-in camera input.
  final bool isExternal;
}
