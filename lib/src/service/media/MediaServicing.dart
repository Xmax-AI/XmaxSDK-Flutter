//
//  MediaServicing.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../core/realtime/RealtimeModel.dart';
import '../../core/realtime/RealtimeMediaSource.dart';

/// Media sizing rules for a realtime model.
abstract interface class MediaServicing {

  /// The model defining input dimension constraints for this media service.
  RealtimeModel get model;

  /// Validates camera preset dimensions and resolves a non-upscaled local size aligned to 4 pixels.
  ///
  /// Parameters:
  /// - [sourceMediaSize]: The original local media pixel dimensions; width and height must be
  ///   positive integers.
  /// - [source]: The media source type; cameras must exactly match a model preset resolution.
  ///
  /// Returns non-upscaled media dimensions satisfying pixel-count limits and 4-pixel alignment.
  Size resolveMediaSize(
    Size sourceMediaSize, {
    required RealtimeMediaSource source,
  });

  /// Selects the model canvas closest to the local media aspect ratio without changing capture
  /// settings.
  ///
  /// Parameters:
  /// - [resolvedMediaSize]: The resolved local media pixel dimensions.
  ///
  /// Returns the model canvas dimensions closest to the resolved media aspect ratio.
  Size resolveGenerationSize(
    Size resolvedMediaSize,
  );

  /// Downscales results within maximum dimensions, preferring exact aspect ratio and 4-pixel
  /// alignment.
  ///
  /// Parameters:
  /// - [resolvedMediaSize]: The resolved local media pixel dimensions.
  /// - [maximumSize]: The maximum result width and height, in pixels.
  ///
  /// Returns 4-pixel-aligned result dimensions within the media and result limits.
  Size resolveTargetSize(
    Size resolvedMediaSize, {
    required Size maximumSize,
  });
}
