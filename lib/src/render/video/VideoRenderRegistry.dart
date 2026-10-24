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

/// An observable video binding that coordinates view hiding before native video removal.
final class VideoRenderHandle extends ValueNotifier<VideoRenderBinding?> {

  /// Creates an observable video rendering handle.
  VideoRenderHandle(
    super.value,
  );

  /// The view-hiding operations to await before native video removal.
  final Set<Future<void> Function()> _removalListeners = {};

  /// Registers a hide operation to run before video removal.
  ///
  /// Parameters:
  /// - [listener]: The callback receiving this notification.
  void addRemovalListener(
    Future<void> Function() listener,
  ) => _removalListeners.add(listener);

  /// Removes a registered video hide operation.
  ///
  /// Parameters:
  /// - [listener]: The callback receiving this notification.
  void removeRemovalListener(
    Future<void> Function() listener,
  ) => _removalListeners.remove(listener);

  /// Waits for registered hide operations before allowing resource removal.
  Future<void> prepareForRemoval() async {
    await Future.wait(_removalListeners.toList().map((
      listener,
    ) => listener()));
  }
}

/// Maintains local and remote rendering bindings by video track identity.
abstract final class VideoRenderRegistry {

  /// The bindings indexed by track object identity.
  static final Map<RealtimeVideoTrack, VideoRenderHandle> _bindings =
      <RealtimeVideoTrack, VideoRenderHandle>{};

  /// Registers a binding for the specified video track.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  /// - [binding]: The rendering or interaction configuration for the current track.
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

  /// Removes the binding for the specified video track.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  static void unregister(
    RealtimeVideoTrack track,
  ) {
    _bindings.remove(track)?.value = null;
  }

  /// Looks up a video track's rendering handle; returns null if unregistered.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  ///
  /// Returns the registered video rendering handle, or null if none exists.
  static VideoRenderHandle? handleFor(
    RealtimeVideoTrack track,
  ) => _bindings[track];
}
