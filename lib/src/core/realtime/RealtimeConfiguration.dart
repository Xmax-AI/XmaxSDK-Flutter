//
//  RealtimeConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeModel.dart';

/// 实时管理器使用的模型配置。
final class RealtimeConfiguration {

  /// 创建实时模型配置。
  const RealtimeConfiguration({
    required this.model,
  });

  /// 实时生成模型，决定可用的媒体规格。
  final RealtimeModel model;

  /// 与 [other] 比较类型及 [model] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimeConfiguration && model == other.model;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => model.hashCode;
}
