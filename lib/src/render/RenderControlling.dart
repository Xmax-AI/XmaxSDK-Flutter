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

/// The rendering interface used by Core.
abstract interface class RenderControlling {

  /// Updates the result-stream binding for the current track.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  void setRemoteStream(
    RemoteStream? stream,
  );

  /// Waits for the first decoded result frame without requiring a mounted remote view.
  Future<void> waitUntilRemoteFrameReady();

  /// Waits for mounted views to conceal remote video before releasing its rendering resources.
  Future<void> prepareForRemoteRemoval();

  /// Registers a rendering handle and interaction sample handler for the remote track.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  /// - [interactionListener]: The handler receiving interaction samples for the current track.
  void registerRemoteTrack(
    RealtimeVideoTrack track, {
    required void Function(
      InteractionFrame frame,
    )
    interactionListener,
  });

  /// Removes remote track rendering, interaction bindings, and first-frame waits.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  void resetRemoteTrack(
    RealtimeVideoTrack? track,
  );
}
