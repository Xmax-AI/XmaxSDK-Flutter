//
//  RealtimePoint.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 交互输入的归一化媒体坐标，横纵分量均位于 0～1。
final class RealtimePoint {

  /// 创建归一化媒体坐标。
  const RealtimePoint({
    required this.x,
    required this.y,
  });

  /// 横向归一化媒体坐标，范围为 0～1。
  final double x;

  /// 纵向归一化媒体坐标，范围为 0～1。
  final double y;
}
