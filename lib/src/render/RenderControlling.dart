//
//  RenderControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../foundation/rtc/RtcModels.dart';
import '../media/interaction/InteractionFrame.dart';
import '../service/realtime/RealtimeVideoTrack.dart';

/// 远端视频轨道绑定、就绪等待和移除的内部接口。
abstract interface class RenderControlling {

  /// 更新当前轨道的结果流绑定。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  void setRemoteStream(
    RemoteStream? stream,
  );

  /// 等待当前结果流首帧解码就绪，不要求预先挂载远端视图。
  Future<void> waitUntilRemoteFrameReady();

  /// 等待已挂载视图隐藏远端视频，再释放对应渲染资源。
  Future<void> prepareForRemoteRemoval();

  /// 为远端轨道注册渲染句柄和交互采样入口。
  ///
  /// - [track]：目标视频轨道。
  /// - [interactionListener]：接收当前轨道触点采样的函数。
  void registerRemoteTrack(
    RealtimeVideoTrack track, {
    required void Function(
      InteractionFrame frame,
    )
    interactionListener,
  });

  /// 解除远端轨道的渲染、交互和首帧等待。
  ///
  /// - [track]：目标视频轨道。
  void resetRemoteTrack(
    RealtimeVideoTrack? track,
  );
}
