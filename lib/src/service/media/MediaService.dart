//
//  MediaService.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../foundation/errors/XmaxError.dart';
import '../realtime/RealtimeModel.dart';
import 'MediaServicing.dart';
import 'RealtimeMediaSource.dart';

/// The sizing and capability rules for local media, generation canvases, and returned media.
final class MediaService implements MediaServicing {

  /// Creates a model-aware media dimension resolver.
  MediaService({
    this.model = RealtimeModel.x2_1,
  });

  /// The model defining dimension constraints.
  @override
  final RealtimeModel model;

  /// Selects the model canvas closest to the local media aspect ratio without changing capture
  /// settings.
  ///
  /// See [MediaServicing.resolveGenerationSize] for the usage contract.
  @override
  Size resolveGenerationSize(
    Size size,
  ) {
    final buckets = model.supportedVideoFormats.map(
      (
        format,
      ) => Size(
        format.width.toDouble(),
        format.height.toDouble(),
      ),
    ).toList();

    if (buckets.isNotEmpty) {
      _validatedSize(size);

      return buckets.reduce(
        (
          a,
          b,
        ) =>
            (math.log(
                  (size.width / size.height) / (a.width / a.height),
                )).abs() <=
                (math.log(
                  (size.width / size.height) / (b.width / b.height),
                )).abs()
            ? a
            : b,
      );
    }

    final validated = _validatedSize(size);
    final pixels = validated.width * validated.height;
    final double scale;
    final double Function(
      num,
    )
    rounding;

    // Scale into the model's pixel-count range before aligning width and height.
    if (pixels < model.minimumInputPixels) {
      scale = math.sqrt(model.minimumInputPixels / pixels);
      rounding = (
        value,
      ) => value.ceilToDouble();
    } else if (pixels > model.maximumInputPixels) {
      scale = math.sqrt(model.maximumInputPixels / pixels);
      rounding = (
        value,
      ) => value.floorToDouble();
    } else {
      scale = 1;
      rounding = (
        value,
      ) => value.roundToDouble();
    }

    final alignment = model.inputSizeAlignment;
    final width = math.max(
      rounding(validated.width * scale / alignment).toInt() * alignment,
      alignment,
    );
    final height = math.max(
      rounding(validated.height * scale / alignment).toInt() * alignment,
      alignment,
    );

    final alignedPixels = width * height;

    if (alignedPixels >= model.minimumInputPixels &&
        alignedPixels <= model.maximumInputPixels) {
      return Size(
        width.toDouble(),
        height.toDouble(),
      );
    }

    // If alignment exceeds pixel limits, choose the nearest valid dimensions.
    return _boundedAlignedSize(
      width: validated.width * scale,
      height: validated.height * scale,
      alignment: model.inputSizeAlignment,
      minimumPixels: model.minimumInputPixels,
      maximumPixels: model.maximumInputPixels,
    );
  }

  /// Resolves local dimensions within model area limits and validates camera buckets.
  ///
  /// See [MediaServicing.resolveMediaSize] for the usage contract.
  @override
  Size resolveMediaSize(
    Size sourceMediaSize, {
    required RealtimeMediaSource source,
  }) {
    _validateIntegral(sourceMediaSize);

    final buckets = model.supportedVideoFormats.map(
      (
        format,
      ) => Size(
        format.width.toDouble(),
        format.height.toDouble(),
      ),
    ).toList();

    if (source == RealtimeMediaSource.camera &&
        buckets.isNotEmpty &&
        !buckets.contains(sourceMediaSize)) {
      throw XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Model ${model.value} does not support camera resolution ${sourceMediaSize.width}×${sourceMediaSize.height}',
      );
    }

    final pixels = sourceMediaSize.width * sourceMediaSize.height;
    final targetPixels = pixels.clamp(
      model.minimumInputPixels,
      model.maximumInputPixels,
    );
    final scale = math.sqrt(targetPixels / pixels);

    return _alignedSize(
      sourceMediaSize,
      scale,
      minimumPixels: model.minimumInputPixels,
      maximumPixels: model.maximumInputPixels,
    );
  }

  /// Downscales results within maximum dimensions, preferring exact aspect ratio and 4-pixel
  /// alignment.
  ///
  /// See [MediaServicing.resolveTargetSize] for the usage contract.
  @override
  Size resolveTargetSize(
    Size resolvedMediaSize, {
    required Size maximumSize,
  }) {
    _validateIntegral(resolvedMediaSize);
    _validatedSize(maximumSize);

    final scale = math.min(
      1.0,
      math.min(
        maximumSize.width / resolvedMediaSize.width,
        maximumSize.height / resolvedMediaSize.height,
      ),
    );

    return _alignedSize(
      resolvedMediaSize,
      scale,
    );
  }

  /// Resolves 4-pixel-aligned dimensions, preferring the exact aspect ratio.
  ///
  /// Parameters:
  /// - [size]: The media pixel dimensions to resolve.
  /// - [scale]: The target scale relative to the baseline dimensions.
  /// - [minimumPixels]: The inclusive area floor, or null to only round down.
  /// - [maximumPixels]: The inclusive area ceiling, or null for no area ceiling.
  ///
  /// Returns dimensions satisfying the area bounds when provided. Without bounds,
  /// only rounds down within the scale limit. Throws if no aligned size fits.
  Size _alignedSize(
    Size size,
    double scale, {
    int? minimumPixels,
    int? maximumPixels,
  }) {
    final width = size.width.toInt(), height = size.height.toInt();
    final divisor = width.gcd(height);
    final ratioWidth = width ~/ divisor;
    final ratioHeight = height ~/ divisor;
    var multiplier = (divisor * scale / 4).floor() * 4;

    if (minimumPixels != null) {
      final minimumScale = math.sqrt(
        minimumPixels / (ratioWidth.toDouble() * ratioHeight),
      );
      multiplier = math.max(multiplier, (minimumScale / 4).ceil() * 4);
    }

    final exactWidth = ratioWidth.toDouble() * multiplier;
    final exactHeight = ratioHeight.toDouble() * multiplier;

    if (multiplier >= 4 &&
        (maximumPixels == null || exactWidth * exactHeight <= maximumPixels)) {
      return Size(
        exactWidth,
        exactHeight,
      );
    }

    final w = (width * scale / 4).floor() * 4,
        h = (height * scale / 4).floor() * 4;
    final alignedPixels = w * h;

    // Independent rounding can cross an area limit when the exact ratio cannot fit.
    if (minimumPixels != null && maximumPixels != null &&
        (alignedPixels < minimumPixels || alignedPixels > maximumPixels)) {
      return _boundedAlignedSize(
        width: width * scale,
        height: height * scale,
        alignment: 4,
        minimumPixels: minimumPixels,
        maximumPixels: maximumPixels,
      );
    }

    if (w < 4 || h < 4) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'No aligned video size is available within the size limits',
      );
    }

    return Size(
      w.toDouble(),
      h.toDouble(),
    );
  }

  /// Validates that media dimensions are representable positive integer pixel values.
  ///
  /// Parameters:
  /// - [size]: The media pixel dimensions to resolve.
  static void _validateIntegral(
    Size size,
  ) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0 ||
        size.width >= 9223372036854775808.0 ||
        size.height >= 9223372036854775808.0 ||
        size.width != size.width.truncateToDouble() ||
        size.height != size.height.truncateToDouble()) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Media dimensions must be positive integers',
      );
    }
  }

  /// Selects valid aligned dimensions near the target within the model's pixel-count range.
  ///
  /// Parameters:
  /// - [width]: The video width, in pixels.
  /// - [height]: The video height, in pixels.
  /// - [alignment]: The required multiple of each dimension, in pixels.
  /// - [minimumPixels]: The inclusive area floor, in pixels.
  /// - [maximumPixels]: The inclusive area ceiling, in pixels.
  ///
  /// Returns the nearest valid dimensions satisfying model alignment and pixel-count limits.
  Size _boundedAlignedSize({
    required double width,
    required double height,
    required int alignment,
    required int minimumPixels,
    required int maximumPixels,
  }) {
    final unitPixels = alignment * alignment;
    final minimumUnits =
        (minimumPixels + unitPixels - 1) ~/ unitPixels;
    final maximumUnits = maximumPixels ~/ unitPixels;
    var bestSize = Size.zero;
    var bestDistance = double.infinity;

    for (var widthUnits = 1; widthUnits <= maximumUnits; widthUnits += 1) {
      final minimumHeight = (minimumUnits + widthUnits - 1) ~/ widthUnits;
      final maximumHeight = maximumUnits ~/ widthUnits;

      if (minimumHeight > maximumHeight) {
        continue;
      }

      final heightUnits = (height / alignment).round().clamp(
        minimumHeight,
        maximumHeight,
      );
      final candidateWidth = (widthUnits * alignment).toDouble();
      final candidateHeight = (heightUnits * alignment).toDouble();
      final distance =
          math.pow(
            (candidateWidth - width) / width,
            2,
          ) +
          math.pow(
            (candidateHeight - height) / height,
            2,
          );

      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        bestSize = Size(
          candidateWidth,
          candidateHeight,
        );
      }
    }

    return bestSize;
  }

  /// Validates finite positive dimensions and returns dimensions suitable for further calculations.
  ///
  /// Parameters:
  /// - [size]: The media pixel dimensions to resolve.
  ///
  /// Returns valid dimensions rounded to integer pixels; throws a configuration error for
  /// non-finite or nonpositive values.
  Size _validatedSize(
    Size size,
  ) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Image width and height must be finite numbers greater than '
            'zero',
      );
    }

    return Size(
      math.max(size.width.roundToDouble(), 1),
      math.max(size.height.roundToDouble(), 1),
    );
  }
}
