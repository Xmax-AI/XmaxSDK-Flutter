//
//  RealtimeModel.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeVideoFormat.dart';

/// A realtime generation model supported by XmaxSDK.
enum RealtimeModel {

  /// The X2.1 realtime generation model.
  // ignore: constant_identifier_names
  x2_1('x2.1');

  /// Defines a model's serialized identifier.
  const RealtimeModel(
    this.value,
  );

  /// The serialized value.
  final String value;

  /// The model's display name.
  String get displayName => 'X2.1';

  /// The supported frame dimensions and recommended frame rates.
  ///
  /// Camera dimensions must match an entry exactly. External video retains its media aspect
  /// ratio and uses the closest generation canvas. An empty list allows variable canvas
  /// dimensions, resolved using pixel limits and alignment.
  List<RealtimeVideoFormat> get supportedVideoFormats => const [
    RealtimeVideoFormat(
      width: 1920,
      height: 1080,
      fps: 30,
    ),
    RealtimeVideoFormat(
      width: 1080,
      height: 1920,
      fps: 30,
    ),
    RealtimeVideoFormat(
      width: 1408,
      height: 1408,
      fps: 30,
    ),
    RealtimeVideoFormat(
      width: 1152,
      height: 1536,
      fps: 30,
    ),
    RealtimeVideoFormat(
      width: 1536,
      height: 1152,
      fps: 30,
    ),
  ];

  /// The minimum local media and uplink area, in pixels; also limits variable generation canvases.
  int get minimumInputPixels => 200000;

  /// The maximum local media area, in pixels; also limits variable generation canvases.
  int get maximumInputPixels => 2100000;

  /// The dimension alignment, in pixels, used to resolve variable generation canvases.
  int get inputSizeAlignment => 32;

  /// The default frame rate when no video format is specified.
  int get defaultFrameRate => 30;

  /// The default camera capture format.
  RealtimeVideoFormat get defaultCameraVideoFormat =>
      const RealtimeVideoFormat(
        width: 1080,
        height: 1920,
        fps: 30,
      );
}
