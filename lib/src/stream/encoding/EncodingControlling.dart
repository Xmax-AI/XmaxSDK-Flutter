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

/// An interface for realtime encoder configuration.
abstract interface class EncodingControlling {

  /// Resolves the format's bitrate budget and applies RTC encoding settings.
  ///
  /// Parameters:
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  Future<void> configure(
    RealtimeVideoFormat videoFormat,
  );
}
