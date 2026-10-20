//
//  TrajectoryEffectRendering.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

/// 单个触点轨迹的标识，用于区分同时存在的多条轨迹。
final class TrajectoryID {

  /// 创建触点轨迹标识。
  TrajectoryID._(
    this.rawValue,
  );

  /// 当前轨迹对应的原始触点标识。
  final int rawValue;

  /// 与 [other] 比较类型及 [rawValue] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is TrajectoryID && rawValue == other.rawValue;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => rawValue.hashCode;
}

/// 轨迹渲染输入，包含触点标识、视图位置、归一化位置和采样时间。
final class TrajectoryPoint {

  /// 创建轨迹位置与采样时间记录。
  const TrajectoryPoint({
    required this.id,
    required this.location,
    required this.normalizedLocation,
    required this.timestamp,
  });

  /// 当前触点对应的轨迹标识。
  final TrajectoryID id;

  /// 触点在视图内的逻辑像素坐标。
  final Offset location;

  /// 触点相对于视图尺寸的归一化坐标，尚未按视频裁剪区域转换为媒体坐标。
  final Offset normalizedLocation;

  /// 触点在当前采样周期内的经过时间。
  final Duration timestamp;
}

/// 自定义轨迹效果接口，处理触点开始、移动和结束事件，并提供叠加显示的视图。
abstract interface class TrajectoryEffectRendering {

  /// 用于叠加显示当前轨迹效果的视图。
  Widget get view;

  /// 创建或替换指定触点的轨迹，并开始绘制效果。
  ///
  /// - [points]：本次采样的触点集合，顺序保持不变。
  void renderBegan(
    List<TrajectoryPoint> points,
  );

  /// 更新指定触点轨迹的位置；没有对应轨迹时创建。
  ///
  /// - [points]：本次采样的触点集合，顺序保持不变。
  void renderMoved(
    List<TrajectoryPoint> points,
  );

  /// 结束指定轨迹的输入，使其按渲染器策略消退。
  ///
  /// - [identifiers]：需要结束渲染的轨迹标识集合。
  void renderEnded(
    List<TrajectoryID> identifiers,
  );

  /// 清除当前显示的所有轨迹。
  void reset();
}

/// 根据原始触点标识创建轨迹标识。
///
/// - [rawValue]：可序列化的原始值。
///
/// 返回封装原始触点标识的轨迹 ID。
TrajectoryID createTrajectoryID(
  int rawValue,
) => TrajectoryID._(rawValue);
