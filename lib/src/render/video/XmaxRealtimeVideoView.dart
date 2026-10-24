//
//  XmaxRealtimeVideoView.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../foundation/media/video/VideoContentMode.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../trajectory/TrajectoryEffectRendering.dart';
import 'VideoRenderBinding.dart';
import 'VideoRenderRegistry.dart';
import 'XmaxVideoView.dart';

/// The recommended realtime video view, automatically switching between local preview and remote
/// results.
///
/// The local preview remains underneath. After [remoteTrack] renders its first frame,
/// the result appears above the preview. Stopping or unbinding the remote stream restores local
/// preview.
/// When generation stops, remote video is hidden before resources are released to avoid black
/// flashes.
///
/// For picture-in-picture or custom layouts, compose multiple [XmaxVideoView] widgets instead.
final class XmaxRealtimeVideoView extends StatefulWidget {

  /// Creates a video view that automatically switches between local preview and generation results.
  const XmaxRealtimeVideoView({
    super.key,
    this.localTrack,
    this.remoteTrack,
    this.videoContentMode = VideoContentMode.fill,
    this.isInteractionEnabled = true,
    this.trajectoryRenderer,
    this.onRemoteVideoReady,
  });

  /// The local camera track shown before a remote result appears and after it stops.
  final RealtimeVideoTrack? localTrack;

  /// The remote result track, displayed automatically after stream matching and first-frame
  /// rendering.
  final RealtimeVideoTrack? remoteTrack;

  /// The shared video scaling mode; defaults to aspect fill with cropping.
  final VideoContentMode videoContentMode;

  /// Whether to submit interaction trails on visible remote video; enabled by default.
  final bool isInteractionEnabled;

  /// The remote interaction trail renderer; defaults to the SDK renderer.
  ///
  /// The caller owns a supplied renderer's lifecycle; the view disposes of its default renderer.
  final TrajectoryEffectRendering? trajectoryRenderer;

  /// The callback invoked when the first remote frame is rendered and displayed; use it to dismiss
  /// loading UI.
  ///
  /// Called once per remote stream binding; condition updates do not trigger it again.
  /// Runs after the current frame, allowing safe UI updates; the fade-in animation may still be in
  /// progress.
  /// Pending callbacks are discarded if generation stops, the stream is unbound, or the track is
  /// replaced.
  final VoidCallback? onRemoteVideoReady;

  /// Creates the state managing preview transitions and remote readiness notifications.
  @override
  State<XmaxRealtimeVideoView> createState() => _XmaxRealtimeVideoViewState();
}

/// Manages transitions between local preview and remote results, including readiness notifications.
final class _XmaxRealtimeVideoViewState extends State<XmaxRealtimeVideoView> {

  // Flutter quantizes opacity to an 8-bit value.
  // Very small values such as 0.001 round to zero, preventing the RTC view from painting.

  /// The remote layer opacity before its first frame is ready.
  static const _pendingRemoteOpacity = 1 / 255;

  /// The observable rendering handle for the current remote track.
  VideoRenderHandle? _remoteHandle;

  /// Whether remote video can currently be displayed.
  bool _isRemoteVisible = false;

  /// Whether the result is forcibly hidden while remote resources are being removed.
  bool _isRemoteSuppressed = false;

  /// The task waiting for remote video to finish hiding.
  Future<void>? _concealment;

  /// The unique result-stream identifier used to distinguish bindings.
  (String, String, String)? _remoteIdentity;

  /// The remote binding version used to invalidate stale readiness callbacks.
  int _readyVersion = 0;

  /// Whether display readiness has been reported for this remote binding.
  bool _didNotifyReady = false;

  /// Initializes view listeners, input sampling, and local drawing resources.
  @override
  void initState() {
    super.initState();
    _attachRemoteTrack();
  }

  /// Updates track bindings, interaction, and renderer ownership for the new widget configuration.
  ///
  /// Parameters:
  /// - [oldWidget]: The previous widget configuration.
  @override
  void didUpdateWidget(
    covariant XmaxRealtimeVideoView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.remoteTrack != widget.remoteTrack) {
      _detachRemoteTrack();
      _isRemoteVisible = false;
      _isRemoteSuppressed = false;
      _attachRemoteTrack();
    } else if (oldWidget.onRemoteVideoReady != widget.onRemoteVideoReady) {
      _scheduleRemoteVideoReady();
    }
  }

  /// Releases listeners, animation resources, and drawing resources owned by the component.
  @override
  void dispose() {
    _detachRemoteTrack();
    super.dispose();
  }

  /// Builds a video or trail view from the current binding and display configuration.
  ///
  /// Parameters:
  /// - [context]: The widget build context.
  ///
  /// Returns the widget tree for the current video or trail effects.
  @override
  Widget build(
    BuildContext context,
  ) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      XmaxVideoView(
        track: widget.localTrack,
        videoContentMode: widget.videoContentMode,
        isInteractionEnabled: false,
      ),
      if (widget.remoteTrack != null)
        IgnorePointer(
          ignoring: !_isRemoteVisible,
          child: TweenAnimationBuilder<double>(
            // Keep opacity low but nonzero while waiting for the native first frame, then fade in above local preview.
            tween: Tween<double>(end: _remoteOpacity),
            duration: _isRemoteVisible
                ? const Duration(milliseconds: 300)
                : Duration.zero,
            curve: Curves.easeInOut,
            builder: (
              context,
              opacity,
              child,
            ) =>
                Opacity(
                  opacity: opacity,
                  child: child,
                ),
            child: XmaxVideoView(
              track: widget.remoteTrack,
              videoContentMode: widget.videoContentMode,
              isInteractionEnabled:
                  _isRemoteVisible && widget.isInteractionEnabled,
              trajectoryRenderer: widget.trajectoryRenderer,
            ),
          ),
        ),
    ],
  );

  /// Observes rendering bindings and removal notifications for the current remote track.
  void _attachRemoteTrack() {
    final track = widget.remoteTrack;

    if (track == null) {
      return;
    }

    final handle = VideoRenderRegistry.handleFor(track);

    _remoteHandle = handle;
    handle?.addListener(_remoteBindingDidChange);
    handle?.addRemovalListener(_prepareForRemoteRemoval);
    _isRemoteVisible = _hasRemoteBinding;
    _updateRemoteReadiness();
  }

  /// Removes remote track listeners and invalidates scheduled readiness notifications.
  void _detachRemoteTrack() {
    _remoteHandle?.removeListener(_remoteBindingDidChange);
    _remoteHandle?.removeRemovalListener(_prepareForRemoteRemoval);
    _remoteHandle = null;
    _concealment = null;
    _remoteIdentity = null;
    _invalidateRemoteReadiness();
  }

  /// Updates video visibility using the latest remote stream binding.
  void _remoteBindingDidChange() {
    if (_remoteHandle?.value == null) {
      _isRemoteSuppressed = false;
    }

    final isVisible = _hasRemoteBinding;

    if (mounted) {
      setState(() => _isRemoteVisible = isVisible);
    }

    _updateRemoteReadiness();
  }

  /// Invalidates pending display readiness callbacks for this binding.
  void _invalidateRemoteReadiness() {
    _readyVersion += 1;
    _didNotifyReady = false;
  }

  /// Updates result visibility from the remote binding and first-frame state.
  void _updateRemoteReadiness() {
    final binding = _remoteHandle?.value;
    final stream = binding is RemoteVideoRenderBinding ? binding.stream : null;
    final identity = stream == null
        ? null
        : (stream.roomID, stream.userID, stream.streamID);

    if (identity != _remoteIdentity || !_hasRemoteBinding) {
      _invalidateRemoteReadiness();
      _remoteIdentity = identity;
    }

    _scheduleRemoteVideoReady();
  }

  /// Invokes display readiness after the current frame, unless the binding has expired.
  void _scheduleRemoteVideoReady() {
    if (!_hasRemoteBinding ||
        _didNotifyReady ||
        widget.onRemoteVideoReady == null) {
      return;
    }

    final version = _readyVersion;
    // A cached first frame may exist during build; defer readiness until visibility is updated
    // so applications can safely call setState from the callback.
    WidgetsBinding.instance.addPostFrameCallback((
      _,
    ) {
      if (!mounted ||
          version != _readyVersion ||
          !_hasRemoteBinding ||
          _didNotifyReady) {
        return;
      }

      final callback = widget.onRemoteVideoReady;

      if (callback == null) {
        return;
      }

      _didNotifyReady = true;
      callback();
    });
  }

  /// The effective opacity of the remote video layer.
  double get _remoteOpacity {
    if (_isRemoteSuppressed || _remoteHandle?.value == null) {
      return 0;
    }

    return _isRemoteVisible ? 1 : _pendingRemoteOpacity;
  }

  /// Hides remote video and waits for frame submission before allowing native resources to be
  /// released.
  Future<void> _prepareForRemoteRemoval() {
    final active = _concealment;

    if (active != null) {
      return active;
    }

    if (!mounted || _isRemoteSuppressed || _remoteHandle?.value == null) {
      return Future<void>.value();
    }

    // Retain video rendering resources until the hidden frame is submitted,
    // then clear the binding to avoid exposing a black canvas while the layer is visible.
    setState(() {
      _isRemoteSuppressed = true;
      _isRemoteVisible = false;
    });
    _invalidateRemoteReadiness();

    final binding = WidgetsBinding.instance;
    final lifecycle = binding.lifecycleState;

    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return Future<void>.value();
    }

    final future = binding.endOfFrame.timeout(
      const Duration(milliseconds: 100),
      onTimeout: () {},
    );

    _concealment = future;

    return future.whenComplete(() {
      if (identical(
        _concealment,
        future,
      )) {
        _concealment = null;
      }
    });
  }

  /// Whether the remote track has an available result-stream binding.
  bool get _hasRemoteBinding {
    final binding = _remoteHandle?.value;

    return !_isRemoteSuppressed &&
        binding is RemoteVideoRenderBinding &&
        binding.firstFrameRendered;
  }
}
