//
//  TrajectoryRegistry.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoTrack.dart';
import 'TrajectoryBinding.dart';

/// Registers interaction handlers by track identity without sharing sample bindings between tracks.
abstract final class TrajectoryRegistry {

  /// The bindings indexed by track object identity.
  static final Map<RealtimeVideoTrack, TrajectoryBinding> _bindings =
      <RealtimeVideoTrack, TrajectoryBinding>{};

  /// Registers a binding for the specified video track.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  /// - [binding]: The rendering or interaction configuration for the current track.
  static void register(
    RealtimeVideoTrack track,
    TrajectoryBinding binding,
  ) {
    _bindings[track] = binding;
  }

  /// Removes the binding for the specified video track.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  static void unregister(
    RealtimeVideoTrack track,
  ) {
    _bindings.remove(track);
  }

  /// Looks up a video track's interaction binding; returns null if unregistered.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  ///
  /// Returns the registered interaction binding, or null if none exists.
  static TrajectoryBinding? bindingFor(
    RealtimeVideoTrack track,
  ) => _bindings[track];
}
