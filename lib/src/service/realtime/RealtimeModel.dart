//
//  RealtimeModel.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeCameraPreset.dart';
import 'RealtimeVideoFormat.dart';

/// A realtime generation model supported by XmaxSDK.
enum RealtimeModel {

  /// The X2.1 realtime generation model.
  // ignore: constant_identifier_names
  x2_1('x2.1'),

  /// The X2.1 Flash realtime generation model.
  // ignore: constant_identifier_names
  x2_1_flash('x2.1-flash');

  /// Defines a model's serialized identifier.
  const RealtimeModel(
    this.value,
  );

  /// The serialized value.
  final String value;

  /// The model's display name.
  String get displayName => switch (this) {
    x2_1 => 'X2.1',
    x2_1_flash => 'X2.1 Flash',
  };

  /// The supported frame dimensions and recommended frame rates.
  ///
  /// Camera dimensions must match an entry exactly. External video retains its media aspect
  /// ratio and uses the closest generation canvas. An empty list allows variable canvas
  /// dimensions, resolved using pixel limits and alignment.
  List<RealtimeVideoFormat> get supportedVideoFormats {
    final presets = switch (this) {
      x2_1 => const [
        RealtimeCameraPreset.resolution1920x1080,
        RealtimeCameraPreset.resolution1080x1920,
        RealtimeCameraPreset.resolution1408x1408,
        RealtimeCameraPreset.resolution1152x1536,
        RealtimeCameraPreset.resolution1536x1152,
      ],
      x2_1_flash => const [
        RealtimeCameraPreset.resolution704x1280,
        RealtimeCameraPreset.resolution1280x704,
        RealtimeCameraPreset.resolution960x960,
        RealtimeCameraPreset.resolution1024x768,
        RealtimeCameraPreset.resolution768x1024,
      ],
    };
    return List.unmodifiable(presets.map(_formatForPreset));
  }

  /// The minimum local media and uplink area, in pixels; also limits variable generation canvases.
  int get minimumInputPixels => 200000;

  /// The maximum local media area, in pixels; also limits variable generation canvases.
  int get maximumInputPixels => switch (this) {
    x2_1 => 2100000,
    x2_1_flash => 960 * 960,
  };

  /// The dimension alignment, in pixels, used to resolve variable generation canvases.
  int get inputSizeAlignment => 32;

  /// The default frame rate when no video format is specified.
  int get defaultFrameRate => 30;

  /// The default camera capture format.
  RealtimeVideoFormat get defaultCameraVideoFormat => _formatForPreset(
    switch (this) {
      x2_1 => RealtimeCameraPreset.resolution1080x1920,
      x2_1_flash => RealtimeCameraPreset.resolution704x1280,
    },
  );

  /// Builds the recommended camera format for the dimensions of [preset].
  RealtimeVideoFormat _formatForPreset(
    RealtimeCameraPreset preset,
  ) {
    final size = preset.size;
    return RealtimeVideoFormat(
      width: size.width.toInt(),
      height: size.height.toInt(),
      fps: defaultFrameRate,
    );
  }
}
