//
//  XmaxRealtimeDualVideo.dart
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
import 'XmaxRealtimeVideo.dart';

/// A Flutter widget that overlays local and remote video tracks and switches between them.
///
/// The local preview remains underneath. After [remoteTrack] renders its first frame,
/// the result appears above the preview. Stopping or unbinding the remote stream restores local
/// preview.
/// When generation stops, remote video is hidden before resources are released to avoid black
/// flashes.
///
/// For picture-in-picture or custom layouts, compose multiple [XmaxRealtimeVideo] widgets instead.
final class XmaxRealtimeDualVideo extends StatefulWidget {

  /// Creates a dual-track realtime video widget.
  const XmaxRealtimeDualVideo({
    super.key,
    this.localTrack,
    this.remoteTrack,
    this.videoContentMode = VideoContentMode.fill,
    this.remoteVideoFadeInDuration = 0.3,
    this.isInteractionEnabled = true,
    this.trajectoryRenderer,
    this.onRemoteVideoReady,
  });

  /// The local preview track shown before a remote result appears and after it stops.
  final RealtimeVideoTrack? localTrack;

  /// The remote generation track.
  ///
  /// A new remote track appears after its first frame is submitted for display. Setting it to
  /// null immediately restores local preview.
  final RealtimeVideoTrack? remoteTrack;

  /// The shared video scaling mode; defaults to aspect fill with cropping.
  final VideoContentMode videoContentMode;

  /// The remote video's fade-in duration, in seconds. The default is 0.3.
  ///
  /// Zero, negative, or nonfinite values disable the animation. Changes apply to the next fade-in.
  final double remoteVideoFadeInDuration;

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
  State<XmaxRealtimeDualVideo> createState() =>
      _XmaxRealtimeDualVideoState();
}

/// Manages transitions between local preview and remote results, including readiness notifications.
final class _XmaxRealtimeDualVideoState
    extends State<XmaxRealtimeDualVideo> {

  /// The remote layer opacity before its first frame is ready.
  ///
  /// A nonzero 8-bit alpha keeps the native video surface painting while it prepares its first frame.
  static const _pendingRemoteOpacity = 1 / 255;

  /// The observable rendering handle for the current remote track.
  VideoRenderHandle? _remoteHandle;

  /// Whether remote video can currently be displayed.
  bool _isRemoteVisible = false;

  /// The duration captured when the current remote fade-in starts.
  Duration _fadeInDuration = Duration.zero;

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

  /// Observes the initial remote track's rendering and removal events.
  @override
  void initState() {
    super.initState();
    _attachRemoteTrack();
  }

  /// Rebinds remote listeners or schedules readiness for the new widget configuration.
  ///
  /// Parameters:
  /// - [oldWidget]: The previous widget configuration.
  @override
  void didUpdateWidget(
    covariant XmaxRealtimeDualVideo oldWidget,
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

  /// Removes remote listeners and invalidates pending readiness notifications.
  @override
  void dispose() {
    _detachRemoteTrack();
    super.dispose();
  }

  /// Builds persistent local preview with a fading remote video layer above it.
  ///
  /// Parameters:
  /// - [context]: The widget build context.
  ///
  /// Returns the local and remote video layers.
  @override
  Widget build(
    BuildContext context,
  ) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      XmaxRealtimeVideo(
        track: widget.localTrack,
        videoContentMode: widget.videoContentMode,
        isInteractionEnabled: false,
      ),
      if (widget.remoteTrack != null)
        IgnorePointer(
          ignoring: !_isRemoteVisible,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.remoteTrack),
            // Keep opacity low but nonzero while waiting for the native first frame, then fade in above local preview.
            tween: Tween<double>(
              begin: _pendingRemoteOpacity,
              end: _remoteOpacity,
            ),
            duration: _isRemoteVisible ? _fadeInDuration : Duration.zero,
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
            child: XmaxRealtimeVideo(
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

    if (_isRemoteVisible) {
      _fadeInDuration = _nextFadeInDuration;
    }

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

    if (isVisible && !_isRemoteVisible) {
      _fadeInDuration = _nextFadeInDuration;
    }

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

  /// The configured fade-in duration, resolved to microseconds without overflowing a Duration.
  Duration get _nextFadeInDuration {
    final seconds = widget.remoteVideoFadeInDuration;

    if (!seconds.isFinite || seconds <= 0) {
      return Duration.zero;
    }

    final microseconds = (seconds * Duration.microsecondsPerSecond).clamp(
      0,
      0x7FFFFFFFFFFFFFFF,
    );

    return Duration(microseconds: microseconds.round());
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
