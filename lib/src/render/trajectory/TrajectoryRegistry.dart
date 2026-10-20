//
//  TrajectoryRegistry.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoTrack.dart';
import 'TrajectoryBinding.dart';

/// 按轨道身份注册交互入口，不在不同轨道之间共享采样绑定。
abstract final class TrajectoryRegistry {

  /// 按轨道对象身份保存的绑定集合。
  static final Map<RealtimeVideoTrack, TrajectoryBinding> _bindings =
      <RealtimeVideoTrack, TrajectoryBinding>{};

  /// 为指定视频轨道注册绑定。
  ///
  /// - [track]：目标视频轨道。
  /// - [binding]：当前轨道的渲染或交互配置。
  static void register(
    RealtimeVideoTrack track,
    TrajectoryBinding binding,
  ) {
    _bindings[track] = binding;
  }

  /// 移除指定视频轨道的绑定。
  ///
  /// - [track]：目标视频轨道。
  static void unregister(
    RealtimeVideoTrack track,
  ) {
    _bindings.remove(track);
  }

  /// 查询指定视频轨道的交互绑定；未注册时返回 null。
  ///
  /// - [track]：目标视频轨道。
  ///
  /// 返回已注册的交互绑定；不存在时返回 null。
  static TrajectoryBinding? bindingFor(
    RealtimeVideoTrack track,
  ) => _bindings[track];
}
