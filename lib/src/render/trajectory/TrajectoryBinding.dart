//
//  TrajectoryBinding.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../media/interaction/InteractionFrame.dart';

/// 将视频轨道的交互采样连接到当前任务的处理入口。
final class TrajectoryBinding {

  /// 创建轨道交互采样绑定。
  const TrajectoryBinding({
    required this.interactionListener,
  });

  /// 接收当前轨道触点采样的函数。
  final void Function(
    InteractionFrame frame,
  )
  interactionListener;
}
