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

  /// The China preview of the X2.1.1 realtime generation model.
  // ignore: constant_identifier_names
  x2_1_1_preview_cn('x2.1.1-preview-cn'),

  /// The global preview of the X2.1.1 realtime generation model.
  // ignore: constant_identifier_names
  x2_1_1_preview_us('x2.1.1-preview-us');

  /// Defines a model's serialized identifier.
  const RealtimeModel(
    this.value,
  );

  /// The serialized value.
  final String value;

  /// The model's display name.
  String get displayName => switch (this) {
    RealtimeModel.x2_1_1_preview_cn => 'X2.1.1-preview-cn',
    RealtimeModel.x2_1_1_preview_us => 'X2.1.1-preview-us',
  };

  /// The supported camera and generation canvas dimensions, with recommended frame rates.
  ///
  /// Camera dimensions must match an entry exactly. An empty list allows variable
  /// canvas dimensions, resolved using pixel limits and alignment.
  List<RealtimeVideoFormat> get supportedVideoFormats => const [
    RealtimeVideoFormat(
      width: 1024,
      height: 1920,
      fps: 30,
    ),
    RealtimeVideoFormat(
      width: 1920,
      height: 1024,
      fps: 30,
    ),
  ];

  /// The minimum local media and uplink area, in pixels; also limits variable generation canvases.
  int get minimumInputPixels => 500000;

  /// The maximum local media area, in pixels; also limits variable generation canvases.
  int get maximumInputPixels => 2100000;

  /// The dimension alignment, in pixels, used to resolve variable generation canvases.
  int get inputSizeAlignment => 32;

  /// The default frame rate when no video format is specified.
  int get defaultFrameRate => 30;

  /// The default camera capture format.
  RealtimeVideoFormat get defaultCameraVideoFormat =>
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
      );
}
