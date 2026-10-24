//
//  RealtimeQualityLevel.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A realtime transport level, from highest quality at L1 to lower bandwidth at L5.
///
/// Levels are not network quality measurements. Automatic adaptation remains active after manual
/// changes.
enum RealtimeQualityLevel {

  /// The highest transport quality.
  l1(1),

  /// High transport quality and the initial level when no valid history exists.
  l2(2),

  /// A balance between visual quality and bandwidth.
  l3(3),

  /// Reduced transmission dimensions and uplink frame rate.
  l4(4),

  /// A lower uplink frame rate that prioritizes bandwidth reduction.
  l5(5);

  /// Defines a level's serialized value.
  const RealtimeQualityLevel(
    this.value,
  );

  /// The quality level value, from 1 to 5.
  final int value;
}
