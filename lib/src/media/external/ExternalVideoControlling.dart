//
//  ExternalVideoControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import 'RealtimeExternalVideoSource.dart';

/// Binds app-owned capture to native preview and realtime upload.
abstract interface class ExternalVideoControlling {

  /// The current external track, or null without a source.
  RealtimeVideoTrack? get currentTrack;

  /// Whether the source opted in to PCM upload.
  bool get hasAudio;

  /// Binds a source without taking ownership of its capture devices or players.
  ///
  /// Parameters:
  /// - [source]: The caller-owned frame producer.
  /// - [cancellation]: Completes to cancel pending source startup.
  ///
  /// Returns the external local media stream.
  Future<RealtimeMediaStream> createExternalVideoStream({
    required RealtimeExternalVideoSource source,
    Future<void>? cancellation,
  });

  /// Unbinds the source and waits for frame delivery to stop.
  Future<void> stopExternalVideoStream();
}
