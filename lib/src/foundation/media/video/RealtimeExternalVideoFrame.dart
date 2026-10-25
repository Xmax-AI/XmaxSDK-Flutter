//
//  RealtimeExternalVideoFrame.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

/// Pixel layouts accepted by an external video source.
enum RealtimeExternalVideoPixelFormat {

  /// Interleaved blue, green, red, and alpha bytes.
  bgra,

  /// Video-range Y followed by interleaved UV, with even width and height.
  nv12,
}

/// Upright pixels supplied by an external source.
///
/// Orientation and mirroring must already be applied to the pixels. NV12 planes use
/// the same row stride and are contiguous, with the UV plane immediately after Y.
final class RealtimeExternalVideoFrame {

  /// Creates a frame referencing caller-owned pixels until sink submission copies them.
  const RealtimeExternalVideoFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.pixelFormat,
    this.bytesPerRow,
  });

  /// The pixel bytes, including row padding when present.
  final Uint8List data;

  /// The visible width, in pixels.
  final int width;

  /// The visible height, in pixels.
  final int height;

  /// The layout and range of the pixel data.
  final RealtimeExternalVideoPixelFormat pixelFormat;

  /// The row stride, in bytes; defaults to width × 4 for BGRA or width for NV12.
  final int? bytesPerRow;

  /// The resolved row stride, in bytes.
  int get rowBytes => bytesPerRow ??
      width * (pixelFormat == RealtimeExternalVideoPixelFormat.bgra ? 4 : 1);
}
