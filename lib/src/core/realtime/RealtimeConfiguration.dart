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

/// The model configuration for a realtime manager.
final class RealtimeConfiguration {

  /// Creates a realtime configuration.
  const RealtimeConfiguration({
    required this.model,
  });

  /// The realtime generation model defining the supported media formats.
  final RealtimeModel model;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeConfiguration && model == other.model;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => model.hashCode;
}
