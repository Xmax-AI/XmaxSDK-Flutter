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

import '../realtime/RealtimeModel.dart';
import 'RealtimeMediaSource.dart';

/// Media sizing rules for a realtime model.
abstract interface class MediaServicing {

  /// The model defining input dimension constraints for this media service.
  RealtimeModel get model;

  /// Resolves local media dimensions and validates camera resolution buckets.
  ///
  /// Parameters:
  /// - [sourceMediaSize]: The original local media pixel dimensions; width and height must be
  ///   positive integers.
  /// - [source]: The media source type; cameras must exactly match a model preset resolution.
  ///
  /// Returns dimensions aligned to 4 within the model's area limits, upscaling or
  /// downscaling as needed and preserving the exact aspect ratio when possible.
  ///
  /// Throws a configuration error if dimensions are invalid or a camera bucket
  /// does not match.
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
