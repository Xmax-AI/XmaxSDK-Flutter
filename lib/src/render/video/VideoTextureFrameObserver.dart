//
//  VideoTextureFrameObserver.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports the first painted video texture without transferring frame buffers to Dart.
///
/// The RTC texture renderer must insert its Texture only after receiving a nonempty frame.
/// A texture mount point alone is not sufficient evidence that a frame is available.
final class VideoTextureFrameObserver extends SingleChildRenderObjectWidget {

  /// Creates a first-frame observer for a result-stream binding.
  const VideoTextureFrameObserver({
    super.key,
    required this.binding,
    required this.onFirstFrameRendered,
    required super.child,
  });

  /// The binding identity; replacing it invalidates queued frame notifications.
  final Object binding;

  /// The callback delivered after the first texture-containing frame is submitted.
  final VoidCallback? onFirstFrameRendered;

  /// Creates the render object observing texture submission.
  ///
  /// [context] provides this widget's location in the tree.
  ///
  /// Returns a render object that leaves child layout and painting unchanged.
  @override
  RenderObject createRenderObject(
    BuildContext context,
  ) => _VideoTextureFrameRenderObject(
    binding: binding,
    onFirstFrameRendered: onFirstFrameRendered,
  );

  /// Updates the binding and callback while retaining the native video subtree.
  ///
  /// Parameters:
  /// - [context]: This widget's location in the tree.
  /// - [renderObject]: The existing texture observer.
  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) => (renderObject as _VideoTextureFrameRenderObject).update(
    binding: binding,
    onFirstFrameRendered: onFirstFrameRendered,
  );
}

/// Observes initial texture painting and discards notifications for expired bindings.
final class _VideoTextureFrameRenderObject extends RenderProxyBox {

  /// Creates an observer for a single result-stream binding.
  _VideoTextureFrameRenderObject({
    required Object binding,
    required VoidCallback? onFirstFrameRendered,
  }) : _binding = binding,
       _onFirstFrameRendered = onFirstFrameRendered;

  /// The currently observed result-stream identity.
  Object _binding;

  /// The callback receiving display readiness after frame submission.
  VoidCallback? _onFirstFrameRendered;

  /// Whether this binding has already submitted a texture frame.
  bool _didSubmitFrame = false;

  /// The revision used to reject callbacks from detached or replaced video surfaces.
  int _revision = 0;

  /// Updates callback ownership, restarting observation only when the binding changes.
  ///
  /// Parameters:
  /// - [binding]: The result-stream identity.
  /// - [onFirstFrameRendered]: The callback receiving the first submitted frame.
  void update({
    required Object binding,
    required VoidCallback? onFirstFrameRendered,
  }) {
    if (!identical(binding, _binding)) {
      _binding = binding;
      _revision += 1;
      _didSubmitFrame = false;
    }

    _onFirstFrameRendered = onFirstFrameRendered;
    if (!_didSubmitFrame) {
      markNeedsPaint();
    }
  }

  /// Paints the child and reports its first nonempty texture after frame submission.
  ///
  /// Parameters:
  /// - [context]: The current painting context.
  /// - [offset]: The child's painting origin.
  @override
  void paint(
    PaintingContext context,
    Offset offset,
  ) {
    super.paint(
      context,
      offset,
    );

    if (_didSubmitFrame || _onFirstFrameRendered == null || !_containsTexture(this)) {
      return;
    }

    _didSubmitFrame = true;
    final revision = _revision;

    WidgetsBinding.instance.addPostFrameCallback((
      _,
    ) {
      if (attached && revision == _revision) {
        _onFirstFrameRendered?.call();
      }
    });
  }

  /// Tests whether a visible, nonempty texture is present in the painted subtree.
  ///
  /// [node] is the subtree root to inspect before the first frame is submitted.
  ///
  /// Returns whether the subtree contains a texture with nonzero layout dimensions.
  bool _containsTexture(
    RenderObject node,
  ) {
    if (node is RenderOffstage && node.offstage ||
        node is RenderOpacity && node.opacity == 0) {
      return false;
    }

    if (node is TextureBox) {
      return node.hasSize && !node.size.isEmpty;
    }

    var found = false;

    node.visitChildren((
      child,
    ) {
      if (!found) {
        found = _containsTexture(child);
      }
    });

    return found;
  }

  /// Invalidates queued notifications when the surface leaves the render tree.
  @override
  void detach() {
    _revision += 1;
    _didSubmitFrame = false;
    super.detach();
  }
}
