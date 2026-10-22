//
//  AgoraRtcPlatform.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import 'RtcPlatform.dart';

/// 声网平台资源。摄像头采集由 SDK 显式开启，麦克风始终关闭。
final class AgoraRtcPlatform implements RtcPlatform {

  /// 绑定已创建的 RTC 引擎。
  AgoraRtcPlatform(
    this.engine,
  );

  /// 当前使用的原生 RTC 引擎。
  @override
  final RtcEngineEx engine;

  /// 初始化 RTC 引擎并禁用本地采集，具体采集由媒体控制器显式启动。
  ///
  /// - [appID]：服务端约定的 RTC 应用标识。
  ///
  /// 返回已初始化且本地采集尚未开启的 RTC 平台资源。
  static Future<RtcPlatform> create(
    String appID,
  ) async {
    final engine = createAgoraRtcEngineEx();

    try {
      await engine.initialize(
        RtcEngineContext(
          appId: appID,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
      await engine.enableVideo();
      await engine.enableLocalVideo(false);
      await engine.enableLocalAudio(false);

      return AgoraRtcPlatform(engine);
    } catch (_) {
      await engine.release();
      rethrow;
    }
  }

  /// 关闭当前 RTC 资源，并使后续原生回调失效。
  @override
  Future<void> destroy() => engine.release();
}
