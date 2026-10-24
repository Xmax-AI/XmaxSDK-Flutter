//
//  RealtimePoint.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A normalized media coordinate whose horizontal and vertical values range from 0 to 1.
final class RealtimePoint {

  /// Creates a normalized media coordinate.
  const RealtimePoint({
    required this.x,
    required this.y,
  });

  /// The normalized horizontal coordinate, from 0 to 1.
  final double x;

  /// The normalized vertical coordinate, from 0 to 1.
  final double y;
}
