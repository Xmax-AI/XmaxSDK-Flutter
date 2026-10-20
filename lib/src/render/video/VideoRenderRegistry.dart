//
//  VideoRenderRegistry.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/foundation.dart';

import '../../service/realtime/RealtimeVideoTrack.dart';
import 'VideoRenderBinding.dart';

/// 可监听的视频绑定，并协调原生视频移除前的视图隐藏。
final class VideoRenderHandle extends ValueNotifier<VideoRenderBinding?> {

  /// 创建可监听的视频渲染句柄。
  VideoRenderHandle(
    super.value,
  );

  /// 原生视频移除前需要等待的视图隐藏操作。
  final Set<Future<void> Function()> _removalListeners = {};

  /// 注册视频移除前的隐藏操作。
  ///
  /// - [listener]：接收本次通知的回调。
  void addRemovalListener(
    Future<void> Function() listener,
  ) => _removalListeners.add(listener);

  /// 移除已注册的视频隐藏操作。
  ///
  /// - [listener]：接收本次通知的回调。
  void removeRemovalListener(
    Future<void> Function() listener,
  ) => _removalListeners.remove(listener);

  /// 等待已注册的视频隐藏操作完成，再允许资源移除。
  Future<void> prepareForRemoval() async {
    await Future.wait(_removalListeners.toList().map((listener) => listener()));
  }
}

/// 按视频轨道身份维护本地及远端渲染绑定。
abstract final class VideoRenderRegistry {

  /// 按轨道对象身份保存的绑定集合。
  static final Map<RealtimeVideoTrack, VideoRenderHandle> _bindings =
      <RealtimeVideoTrack, VideoRenderHandle>{};

  /// 为指定视频轨道注册绑定。
  ///
  /// - [track]：目标视频轨道。
  /// - [binding]：当前轨道的渲染或交互配置。
  static void register(
    RealtimeVideoTrack track,
    VideoRenderBinding? binding,
  ) {
    final current = _bindings[track];

    if (current == null) {
      _bindings[track] = VideoRenderHandle(binding);
    } else {
      current.value = binding;
    }
  }

  /// 移除指定视频轨道的绑定。
  ///
  /// - [track]：目标视频轨道。
  static void unregister(
    RealtimeVideoTrack track,
  ) {
    _bindings.remove(track)?.value = null;
  }

  /// 查询指定视频轨道的渲染句柄；未注册时返回 null。
  ///
  /// - [track]：目标视频轨道。
  ///
  /// 返回已注册的视频渲染句柄；不存在时返回 null。
  static VideoRenderHandle? handleFor(
    RealtimeVideoTrack track,
  ) => _bindings[track];
}
