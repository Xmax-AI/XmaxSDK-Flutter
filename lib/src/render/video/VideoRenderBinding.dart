//
//  VideoRenderBinding.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/rtc/RtcModels.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// 本地预览或远端结果视频的内部渲染绑定。
sealed class VideoRenderBinding {

  /// 创建视频渲染绑定。
  const VideoRenderBinding();
}

/// 本地摄像头的 RTC 引擎和预览挂载通知。
final class LocalVideoRenderBinding extends VideoRenderBinding {

  /// 创建本地预览绑定。
  const LocalVideoRenderBinding({
    this.onPreviewAttached,
    this.engine,
  });

  /// 本地预览使用的 RTC 引擎；未指定时渲染组件显示黑色背景。
  final RtcEngine? engine;

  /// 原生预览视图完成挂载时的通知。
  final void Function()? onPreviewAttached;
}

/// 远端流及其首帧渲染状态。
final class RemoteVideoRenderBinding extends VideoRenderBinding {

  /// 创建远端结果流绑定。
  const RemoteVideoRenderBinding(
    this.stream, {
    this.firstFrameRendered = false,
  });

  /// 当前绑定的远端结果流。
  final RemoteStream stream;

  /// 当前远端流是否已渲染首帧，初始为 false。
  final bool firstFrameRendered;
}
