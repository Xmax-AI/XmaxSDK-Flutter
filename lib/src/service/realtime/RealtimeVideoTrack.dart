//
//  RealtimeVideoTrack.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/media/camera/CameraPosition.dart';
import 'RealtimeVideoFormat.dart';

/// A realtime video track with dynamic metadata.
final class RealtimeVideoTrack {

  /// Creates a video track and its format metadata.
  RealtimeVideoTrack._({
    required this.id,
    RealtimeVideoFormat? videoFormat,
    CameraPosition? position,
  }) : _videoFormat = videoFormat,
       _position = position;

  /// The track identifier; metadata updates preserve the track object's identity.
  final String id;

  /// The video dimensions, frame rate, and encoding settings.
  RealtimeVideoFormat? _videoFormat;

  /// The camera position metadata, or null when unspecified or inapplicable.
  CameraPosition? _position;

  /// The video dimensions, frame rate, and encoding settings.
  RealtimeVideoFormat? get videoFormat => _videoFormat;

  /// The camera position, or null for remote tracks or an unknown position.
  CameraPosition? get position => _position;
}

/// An internal callback for local capture and preview readiness.
typedef RealtimeCameraPreviewReadyListener = void Function();

/// Creates a video track with initial format and camera position metadata.
///
/// Parameters:
/// - [id]: The video track identifier.
/// - [videoFormat]: The track's initial video format.
/// - [position]: The camera position metadata.
///
/// Returns the track with the specified identity and initial metadata.
RealtimeVideoTrack createRealtimeVideoTrack({
  required String id,
  RealtimeVideoFormat? videoFormat,
  CameraPosition? position,
}) =>
    RealtimeVideoTrack._(
      id: id,
      videoFormat: videoFormat,
      position: position,
    );

/// Updates nonnull metadata without replacing the track's identity.
///
/// Parameters:
/// - [track]: The target video track.
/// - [videoFormat]: The video format; omitting it retains the track's current format.
/// - [position]: The camera position; omitting it retains the track's current position.
void updateRealtimeVideoTrack({
  required RealtimeVideoTrack track,
  RealtimeVideoFormat? videoFormat,
  CameraPosition? position,
}) {
  if (videoFormat != null) {
    track._videoFormat = videoFormat;
  }

  if (position != null) {
    track._position = position;
  }
}
