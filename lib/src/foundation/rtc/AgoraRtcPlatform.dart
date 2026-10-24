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

/// The Agora platform resources; camera capture starts explicitly and microphone capture remains
/// disabled.
final class AgoraRtcPlatform implements RtcPlatform {

  /// Wraps an existing RTC engine.
  AgoraRtcPlatform(
    this.engine,
  );

  /// The native RTC engine in use.
  @override
  final RtcEngineEx engine;

  /// Initializes the RTC engine with local capture disabled until explicitly started by media
  /// control.
  ///
  /// Parameters:
  /// - [appID]: The RTC application identifier expected by the server.
  ///
  /// Returns initialized platform resources with local capture disabled.
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

  /// Releases RTC resources and invalidates subsequent native callbacks.
  @override
  Future<void> destroy() => engine.release();
}
