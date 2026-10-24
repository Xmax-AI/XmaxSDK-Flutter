//
//  RtcEventListener.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RemoteStream.dart';

/// The internal RTC publication, first-frame, and failure callbacks.
final class RtcEventListener {

  /// Creates RTC event callbacks.
  const RtcEventListener({
    this.onRemoteVideoPublished,
    this.onFirstRemoteVideoFrameRendered,
    this.onFirstRemoteVideoFrameDecoded,
    this.onRemoteAudioPublished,
    this.onError,
  });

  /// The remote video publication callback.
  final void Function(
    RemoteStream stream,
    bool published,
  )?
  onRemoteVideoPublished;

  /// The callback for a rendered first remote video frame.
  final void Function(
    RemoteStream stream,
  )?
  onFirstRemoteVideoFrameRendered;

  /// The callback for a decoded first remote video frame.
  final void Function(
    RemoteStream stream,
  )?
  onFirstRemoteVideoFrameDecoded;

  /// The remote audio publication callback.
  final void Function(
    RemoteStream stream,
    bool published,
  )?
  onRemoteAudioPublished;

  /// The RTC runtime failure callback.
  final void Function(
    Object error,
  )?
  onError;
}
