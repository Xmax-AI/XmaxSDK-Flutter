//
//  RealtimeModel.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';

/// A realtime generation model supported by XmaxSDK.
enum RealtimeModel {

  /// The X2.1 realtime generation model, routed by the client's environment.
  // ignore: constant_identifier_names
  x2_1('x2.1');

  /// Defines a model's serialized identifier.
  const RealtimeModel(
    this.value,
  );

  /// The serialized value.
  final String value;

  /// The model's display name.
  String get displayName => switch (this) {
    RealtimeModel.x2_1 => 'X2.1',
  };

  /// The supported camera and generation canvas dimensions, with recommended frame rates.
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

  /// The minimum pixel area used to resolve generation dimensions when no buckets exist.
  int get minimumInputPixels => 600000;

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
