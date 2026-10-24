//
//  XmaxVideoView.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../foundation/media/video/VideoContentMode.dart';
import '../../media/interaction/InteractionFrame.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../trajectory/DefaultTrajectoryEffectRenderer.dart';
import '../trajectory/TrajectoryEffectRendering.dart';
import '../trajectory/TrajectoryRegistry.dart';
import 'VideoRenderBinding.dart';
import 'VideoRenderRegistry.dart';
import 'VideoRenderSurface.dart';

/// A Flutter view displaying a local or remote Xmax realtime video track.
final class XmaxVideoView extends StatefulWidget {

  /// Creates a single-track video view.
  const XmaxVideoView({
    super.key,
    this.track,
    this.videoContentMode = VideoContentMode.fill,
    this.isInteractionEnabled = true,
    this.trajectoryRenderer,
  });

  /// The video track to display; null shows a black background without creating a video texture.
  final RealtimeVideoTrack? track;

  /// The video scaling mode; defaults to aspect fill with cropping.
  final VideoContentMode videoContentMode;

  /// Whether to enable interaction sampling and trail rendering; enabled by default.
  final bool isInteractionEnabled;

  /// The custom trail renderer; null uses the SDK renderer.
  ///
  /// The caller owns a supplied renderer's lifecycle; the view disposes of its default renderer.
  final TrajectoryEffectRendering? trajectoryRenderer;

  /// Creates the state managing single-track video and interaction resources.
  @override
  State<XmaxVideoView> createState() => _XmaxVideoViewState();
}

/// Manages video rendering, interaction sampling, and trail effect resources.
final class _XmaxVideoViewState extends State<XmaxVideoView>
    with SingleTickerProviderStateMixin {

  /// The sampling interval, allowing at most 30 periodic interaction samples per second.
  static const _samplingInterval = Duration(
    microseconds: Duration.microsecondsPerSecond ~/ 30,
  );

  /// The renderer providing current trail state and repaint notifications.
  late TrajectoryEffectRendering _renderer;

  /// Whether this view owns disposal of the trail renderer.
  late bool _ownsRenderer;

  /// The display-synchronized ticker driving interaction sampling.
  late final Ticker _samplingTicker;

  /// The active pointers indexed by pointer identifier.
  final Map<int, _ActivePointer> _activePointers = <int, _ActivePointer>{};

  /// The elapsed time in the current interaction sampling cycle.
  Duration _currentSamplingTime = Duration.zero;

  /// The time of the last submitted sample in the current cycle.
  Duration? _lastSampleTime;

  /// The viewport dimensions of the latest sample, in logical pixels.
  Size? _samplingViewportSize;

  /// The handler for submitting view interaction samples.
  void Function(
    InteractionFrame frame,
  )?
  _samplingListener;

  /// Initializes view listeners, input sampling, and local drawing resources.
  @override
  void initState() {
    super.initState();
    _ownsRenderer = widget.trajectoryRenderer == null;
    _renderer = widget.trajectoryRenderer ?? DefaultTrajectoryEffectRenderer();
    _samplingTicker = createTicker(_sampleActivePointers);
  }

  /// Updates track bindings, interaction, and renderer ownership for the new widget configuration.
  ///
  /// Parameters:
  /// - [oldWidget]: The previous widget configuration.
  @override
  void didUpdateWidget(
    covariant XmaxVideoView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    final rendererChanged =
        oldWidget.trajectoryRenderer != widget.trajectoryRenderer;

    if (rendererChanged ||
        oldWidget.track != widget.track ||
        oldWidget.isInteractionEnabled != widget.isInteractionEnabled) {
      _resetPointers();
    }

    if (rendererChanged) {
      _disposeOwnedRenderer();
      _ownsRenderer = widget.trajectoryRenderer == null;
      _renderer =
          widget.trajectoryRenderer ?? DefaultTrajectoryEffectRenderer();
    }
  }

  /// Releases listeners, animation resources, and drawing resources owned by the component.
  @override
  void dispose() {
    _resetPointers();
    _disposeOwnedRenderer();
    _samplingTicker.dispose();
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
  ) {
    final track = widget.track;

    if (track == null) {
      return const ColoredBox(color: Colors.black);
    }

    final handle = VideoRenderRegistry.handleFor(track);
    final video = handle == null
        ? const ColoredBox(color: Colors.black)
        : ValueListenableBuilder<VideoRenderBinding?>(
          valueListenable: handle,
          builder: (
            context,
            binding,
            _,
          ) => _buildVideo(binding),
        );

    final interaction = TrajectoryRegistry.bindingFor(track);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          video,
          if (widget.isInteractionEnabled && interaction != null)
            LayoutBuilder(
              builder: (
                context,
                constraints,
              ) => Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (
                  event,
                ) => _pointerDown(
                  event,
                  constraints.biggest,
                  interaction.interactionListener,
                ),
                onPointerMove: (
                  event,
                ) => _pointerMove(
                  event,
                  constraints.biggest,
                  interaction.interactionListener,
                ),
                onPointerUp: _pointerUp,
                onPointerCancel: _pointerUp,
                child: IgnorePointer(child: _renderer.view),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the native video texture using the current track binding.
  ///
  /// Parameters:
  /// - [binding]: The rendering or interaction configuration for the current track.
  ///
  /// Returns the widget tree for the current video or trail effects.
  Widget _buildVideo(
    VideoRenderBinding? binding,
  ) {
    if (binding == null) {
      return const ColoredBox(color: Colors.black);
    }

    return VideoRenderSurface(
      binding: binding,
      track: widget.track,
      contentMode: widget.videoContentMode,
    );
  }

  /// Starts a pointer trail and immediately submits its first interaction sample.
  ///
  /// Parameters:
  /// - [event]: The pointer-down, move, or release event being processed.
  /// - [size]: The current video viewport dimensions, in logical pixels.
  /// - [listener]: The callback receiving this notification.
  void _pointerDown(
    PointerDownEvent event,
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    final pointer = _ActivePointer(
      id: createTrajectoryID(event.pointer),
      location: event.localPosition,
    );

    _activePointers[event.pointer] = pointer;
    _updateSamplingContext(
      size,
      listener,
    );
    _renderer.renderBegan(<TrajectoryPoint>[_point(
      pointer,
      size,
    )]);

    // Submit the first point immediately, then sample all active pointers at 30 Hz using the display ticker.
    _submit(
      size,
      listener,
    );
    if (!_samplingTicker.isActive) {
      _currentSamplingTime = Duration.zero;
      _lastSampleTime = Duration.zero;
      _samplingTicker.start();
    } else {
      _lastSampleTime = _currentSamplingTime;
    }
  }

  /// Updates an active pointer's position and trail display.
  ///
  /// Parameters:
  /// - [event]: The pointer-down, move, or release event being processed.
  /// - [size]: The current video viewport dimensions, in logical pixels.
  /// - [listener]: The callback receiving this notification.
  void _pointerMove(
    PointerMoveEvent event,
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    final pointer = _activePointers[event.pointer];

    if (pointer == null) {
      return;
    }

    pointer.location = event.localPosition;
    _updateSamplingContext(
      size,
      listener,
    );
    _renderer.renderMoved(<TrajectoryPoint>[_point(
      pointer,
      size,
    )]);
  }

  /// Ends a pointer trail and stops sampling when no active pointers remain.
  ///
  /// Parameters:
  /// - [event]: The pointer-down, move, or release event being processed.
  void _pointerUp(
    PointerEvent event,
  ) {
    final pointer = _activePointers.remove(event.pointer);

    if (pointer != null) {
      _renderer.renderEnded(<TrajectoryID>[pointer.id]);
    }

    if (_activePointers.isEmpty) {
      _stopSampling();
    }
  }

  /// Submits all active pointers at the fixed sampling interval.
  ///
  /// Parameters:
  /// - [elapsed]: The time elapsed in the current animation or sampling cycle.
  void _sampleActivePointers(
    Duration elapsed,
  ) {
    _currentSamplingTime = elapsed;

    if (_activePointers.isEmpty) {
      _stopSampling();

      return;
    }

    final lastSampleTime = _lastSampleTime;

    if (lastSampleTime != null &&
        elapsed - lastSampleTime < _samplingInterval) {
      return;
    }

    final size = _samplingViewportSize;
    final listener = _samplingListener;

    if (size == null || listener == null) {
      return;
    }

    _submit(
      size,
      listener,
    );
    _lastSampleTime = elapsed;
  }

  /// Saves the viewport dimensions and submission handler for interaction sampling.
  ///
  /// Parameters:
  /// - [size]: The current video viewport dimensions, in logical pixels.
  /// - [listener]: The callback receiving this notification.
  void _updateSamplingContext(
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    _samplingViewportSize = size;
    _samplingListener = listener;
  }

  /// Stops the sampling ticker and clears the sampling context.
  void _stopSampling() {
    if (_samplingTicker.isActive) {
      _samplingTicker.stop();
    }

    _currentSamplingTime = Duration.zero;
    _lastSampleTime = null;
    _samplingViewportSize = null;
    _samplingListener = null;
  }

  /// Converts an active pointer into trail rendering input containing position and elapsed time.
  ///
  /// Parameters:
  /// - [pointer]: The state of the active pointer.
  /// - [size]: The current video viewport dimensions, in logical pixels.
  ///
  /// Returns a position and time sample for local trail rendering.
  TrajectoryPoint _point(
    _ActivePointer pointer,
    Size size,
  ) => TrajectoryPoint(
    id: pointer.id,
    location: pointer.location,
    normalizedLocation: Offset(
      size.width == 0 ? 0 : pointer.location.dx / size.width,
      size.height == 0 ? 0 : pointer.location.dy / size.height,
    ),
    timestamp: Duration(microseconds: DateTime.now().microsecondsSinceEpoch),
  );

  /// Submits all active pointers to the interaction controller using the current view
  /// configuration.
  ///
  /// Parameters:
  /// - [size]: The current video viewport dimensions, in logical pixels.
  /// - [listener]: The callback receiving this notification.
  void _submit(
    Size size,
    void Function(
      InteractionFrame frame,
    )
    listener,
  ) {
    listener(
      InteractionFrame(
        points: _activePointers.values
            .map((
              pointer,
            ) => pointer.location)
            .toList(growable: false),
        viewportSize: size,
        contentMode: widget.videoContentMode,
      ),
    );
  }

  /// Clears active pointers, the sampling ticker, and visible trails.
  void _resetPointers() {
    _activePointers.clear();
    _stopSampling();
    _renderer.reset();
  }

  /// Disposes only the default trail renderer created by this view.
  void _disposeOwnedRenderer() {
    if (_ownsRenderer && _renderer is DefaultTrajectoryEffectRenderer) {
      (_renderer as DefaultTrajectoryEffectRenderer).dispose();
    }
  }
}

/// The trail identifier and latest view position of an active pointer.
final class _ActivePointer {

  /// Records an active pointer's trail identifier and current position.
  _ActivePointer({
    required this.id,
    required this.location,
  });

  /// The trail identifier of the active pointer.
  final TrajectoryID id;

  /// The pointer position within the view, in logical pixels.
  Offset location;
}
