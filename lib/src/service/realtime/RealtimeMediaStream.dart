//
//  RealtimeMediaStream.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeVideoTrack.dart';

/// A local input or remote output media stream for realtime generation.
final class RealtimeMediaStream {

  /// Creates a media stream associated with a video track.
  const RealtimeMediaStream._({
    required this.id,
    this.videoTrack,
  });

  /// The stream identifier; video rendering uses the associated videoTrack.
  final String id;

  /// The stream's associated video track.
  final RealtimeVideoTrack? videoTrack;
}

/// Creates a media stream with the specified video track.
///
/// Parameters:
/// - [id]: The media stream identifier.
/// - [videoTrack]: The video track used to display this stream.
///
/// Returns the media stream with the specified identity and video track.
RealtimeMediaStream createRealtimeMediaStream({
  required String id,
  RealtimeVideoTrack? videoTrack,
}) => RealtimeMediaStream._(
  id: id,
  videoTrack: videoTrack,
);
