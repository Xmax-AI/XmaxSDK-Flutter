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
import '../foundation/rtc/RemoteStream.dart';
import '../media/interaction/InteractionFrame.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import '../service/realtime/RealtimeMediaFrame.dart';
import '../foundation/rtc/RtcManaging.dart';
import 'video/RealtimeMediaFrameDispatcher.dart';
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
    RtcManaging? rtcManager,
    void Function(
      Object error,
    )? onError,
  }) : _rtcManager = rtcManager,
       _onOutputError = onError;

  /// The native output adapter, independent of texture view mounting.
  final RtcManaging? _rtcManager;

  /// The failure receiver for automatic result binding changes.
  final void Function(
    Object error,
  )? _onOutputError;

  /// The serial bounded application delivery queue.
  final _mediaDispatcher = RealtimeMediaFrameDispatcher();

  /// The last requested callback, retained for rollback after failed native configuration.
  RealtimeMediaFrameListener? _mediaListener;

  /// The serial native observer configuration operation.
  Future<void> _outputConfiguration = Future<void>.value();

  /// Invalidates observer work queued for earlier result bindings.
  int _outputVersion = 0;

  /// Replaces output immediately and awaits current native configuration.
  ///
  /// See [RenderControlling.setRemoteMediaFrameListener] for the delivery contract.
  @override
  Future<void> setRemoteMediaFrameListener(
    RealtimeMediaFrameListener? listener,
  ) async {
    final previous = _mediaListener;
    _mediaListener = listener;
    _mediaDispatcher.setListener(listener);
    final configuration = _configureMediaOutput();
    final version = _outputVersion;
    try {
      await configuration;
    } catch (_) {
      if (version != _outputVersion) {
        return;
      }
      if (listener != null) {
        _mediaListener = previous;
        _mediaDispatcher.setListener(previous);
        _refreshMediaOutput();
      }
      rethrow;
    }
  }

  /// Serializes observer replacement and rejects stale producers before copying further output.
  Future<void> _configureMediaOutput() {
    final version = ++_outputVersion;
    final previous = _outputConfiguration;
    final work = () async {
      await previous;
      if (version != _outputVersion) {
        return;
      }
      final stream = _remoteStream;
      final token = _mediaDispatcher.streamID;
      final enabled = _mediaDispatcher.hasListener && stream != null && token != null;
      await _rtcManager?.setRemoteMediaFrameListener(
        stream: enabled ? stream : null,
        listener: !enabled ? null : (
          content,
        ) {
          if (version == _outputVersion) {
            _mediaDispatcher.dispatch(
              content,
              streamID: token,
            );
          }
        },
      );
    }();
    _outputConfiguration = work.catchError((
      Object error,
    ) {});
    return work;
  }

  /// Rebinds native output after stream changes and routes configuration failures.
  void _refreshMediaOutput() {
    final configuration = _configureMediaOutput();
    final version = _outputVersion;
    unawaited(configuration.catchError((
      Object error,
    ) {
      if (version == _outputVersion) {
        _onOutputError?.call(error);
      }
    }));
  }

  /// The maximum wait for the first decoded remote frame; defaults to 10 seconds.
  final Duration remoteFrameReadyTimeout;

  /// The video track for the current remote generation result.
  RealtimeVideoTrack? _remoteTrack;

  /// The remote media stream for this generation result.
  RemoteStream? _remoteStream;

  /// Whether a valid first frame has been decoded for the current result stream.
  bool _remoteFrameReady = false;

  /// Invalidates submitted-frame notifications when a result binding is replaced or removed.
  Object? _bindingVersion;

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
    _mediaDispatcher.setStream(stream != null);
    _refreshMediaOutput();

    final track = _remoteTrack;

    if (track != null) {
      final bindingVersion = Object();
      _bindingVersion = bindingVersion;

      VideoRenderRegistry.register(
        track,
        stream == null
            ? null
            : RemoteVideoRenderBinding(
              stream,
              onFirstFrameRendered: () {
                if (identical(
                  _bindingVersion,
                  bindingVersion,
                )) {
                  markRemoteFrameRendered(stream);
                }
              },
            ),
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
    _bindingVersion = null;
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
        onFirstFrameRendered: binding.onFirstFrameRendered,
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
    _mediaDispatcher.setStream(false);
    _refreshMediaOutput();

    final target = track ?? _remoteTrack;

    if (target != null) {
      VideoRenderRegistry.unregister(target);
      TrajectoryRegistry.unregister(target);
    }

    _remoteTrack = null;
  }
}
