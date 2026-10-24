//
//  RenderController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../foundation/errors/XmaxError.dart';
import '../foundation/rtc/RtcModels.dart';
import '../media/interaction/InteractionFrame.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import 'RenderControlling.dart';
import 'trajectory/TrajectoryBinding.dart';
import 'trajectory/TrajectoryRegistry.dart';
import 'video/VideoRenderBinding.dart';
import 'video/VideoRenderRegistry.dart';

/// Manages remote track bindings, first-frame readiness, and video hiding before removal.
final class RenderController implements RenderControlling {

  /// Creates a remote video rendering controller.
  RenderController({
    this.remoteFrameReadyTimeout = const Duration(seconds: 10),
  });

  /// The maximum wait for the first decoded remote frame; defaults to 10 seconds.
  final Duration remoteFrameReadyTimeout;

  /// The video track for the current remote generation result.
  RealtimeVideoTrack? _remoteTrack;

  /// The remote media stream for this generation result.
  RemoteStream? _remoteStream;

  /// Whether a valid first frame has been decoded for the current result stream.
  bool _remoteFrameReady = false;

  /// The completers waiting for the current result stream's first decoded frame.
  final Set<Completer<void>> _frameWaiters = {};

  /// Waits for mounted views to conceal remote video before releasing its rendering resources.
  @override
  Future<void> prepareForRemoteRemoval() async {
    final track = _remoteTrack;

    if (track != null) {
      await VideoRenderRegistry.handleFor(track)?.prepareForRemoval();
    }
  }

  /// Registers a rendering handle and interaction sample handler for the remote track.
  ///
  /// See [RenderControlling.registerRemoteTrack] for the usage contract.
  @override
  void registerRemoteTrack(
    RealtimeVideoTrack track, {
    required void Function(
      InteractionFrame frame,
    )
    interactionListener,
  }) {
    _resetFrameReadiness();
    _remoteTrack = track;
    VideoRenderRegistry.register(
      track,
      null,
    );
    TrajectoryRegistry.register(
      track,
      TrajectoryBinding(interactionListener: interactionListener),
    );
  }

  /// Updates the result-stream binding for the current track.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  @override
  void setRemoteStream(
    RemoteStream? stream,
  ) {
    _resetFrameReadiness();
    _remoteStream = stream;

    final track = _remoteTrack;

    if (track != null) {
      VideoRenderRegistry.register(
        track,
        stream == null ? null : RemoteVideoRenderBinding(stream),
      );
    }
  }

  /// Records first-frame decoding without requiring the view to be mounted.
  ///
  /// Parameters:
  /// - [stream]: The remote stream whose first frame has been decoded.
  void markRemoteFrameReady(
    RemoteStream stream,
  ) {
    final active = _remoteStream;

    if (_remoteTrack == null ||
        active == null ||
        active.roomID != stream.roomID ||
        active.userID != stream.userID ||
        active.streamID != stream.streamID) {
      return;
    }

    _remoteFrameReady = true;
    for (final waiter in _frameWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }

    _frameWaiters.clear();
  }

  /// Waits for the first decoded result frame without requiring a mounted remote view.
  @override
  Future<void> waitUntilRemoteFrameReady() async {
    if (_remoteTrack == null || _remoteStream == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Remote video stream is unavailable',
      );
    }

    if (_remoteFrameReady) {
      return;
    }

    final waiter = Completer<void>();

    _frameWaiters.add(waiter);

    try {
      await waiter.future.timeout(
        remoteFrameReadyTimeout,
        onTimeout: () {
          throw const XmaxError(
            code: XmaxErrorCode.timeout,
            message: 'Remote video first frame timed out',
          );
        },
      );
    } finally {
      _frameWaiters.remove(waiter);
    }
  }

  /// Ends readiness waits for the old result stream and clears first-frame flags.
  void _resetFrameReadiness() {
    _remoteStream = null;
    _remoteFrameReady = false;
    for (final waiter in _frameWaiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(
          const XmaxError(
            code: XmaxErrorCode.cancelled,
            message: 'Remote frame wait cancelled',
          ),
        );
      }
    }

    _frameWaiters.clear();
  }

  /// Records the first rendered result frame so the view can display remote video.
  ///
  /// Parameters:
  /// - [stream]: The remote RTC stream to process.
  void markRemoteFrameRendered(
    RemoteStream stream,
  ) {
    final track = _remoteTrack;

    if (track == null) {
      return;
    }

    final handle = VideoRenderRegistry.handleFor(track);
    final binding = handle?.value;

    if (binding is! RemoteVideoRenderBinding ||
        binding.firstFrameRendered ||
        binding.stream.roomID != stream.roomID ||
        binding.stream.userID != stream.userID ||
        binding.stream.streamID != stream.streamID) {
      return;
    }

    VideoRenderRegistry.register(
      track,
      RemoteVideoRenderBinding(
        stream,
        firstFrameRendered: true,
      ),
    );
  }

  /// Removes remote track rendering, interaction bindings, and first-frame waits.
  ///
  /// Parameters:
  /// - [track]: The target video track.
  @override
  void resetRemoteTrack(
    RealtimeVideoTrack? track,
  ) {
    _resetFrameReadiness();

    final target = track ?? _remoteTrack;

    if (target != null) {
      VideoRenderRegistry.unregister(target);
      TrajectoryRegistry.unregister(target);
    }

    _remoteTrack = null;
  }
}
