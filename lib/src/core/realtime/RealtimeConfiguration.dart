//
//  RealtimeConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeModel.dart';

/// The model and adaptive quality settings for a realtime manager.
final class RealtimeConfiguration {

  /// Creates a realtime configuration.
  const RealtimeConfiguration({
    required this.model,
    this.isAdaptiveQualityEnabled = true,
  });

  /// The realtime generation model defining the supported media formats.
  final RealtimeModel model;

  /// Whether uplink and downlink quality levels adapt automatically.
  ///
  /// When disabled, each connection starts at L1 without reading or saving quality
  /// history. Manual quality changes remain available during generation.
  final bool isAdaptiveQualityEnabled;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeConfiguration &&
          model == other.model &&
          isAdaptiveQualityEnabled == other.isAdaptiveQualityEnabled;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    model,
    isAdaptiveQualityEnabled,
  );
}
