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

import '../../core/realtime/RealtimeModel.dart';
import '../../core/realtime/RealtimeMediaSource.dart';
import '../../foundation/errors/XmaxError.dart';
import 'MediaServicing.dart';

/// 依据模型约束解析本地媒体、生成画布和回传视频的尺寸。
final class MediaService implements MediaServicing {

  /// 创建模型媒体尺寸解析服务。
  MediaService({
    this.model = RealtimeModel.x2_1_1_preview_cn,
  });

  /// 尺寸约束所属模型，默认使用国内 X2.1.1-preview-cn。
  @override
  final RealtimeModel model;

  /// 选择宽高比最接近本地媒体的模型生成画布，不修改本地采集规格。
  ///
  /// 详细说明见 [MediaServicing.resolveGenerationSize]。
  @override
  Size resolveGenerationSize(
    Size size,
  ) {
    final buckets = model.resolutionBuckets;

    if (buckets.isNotEmpty) {
      _validatedSize(size);

      return buckets.reduce(
        (a, b) =>
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

    // 先缩放到模型允许的像素数量范围，再调整宽高以满足对齐要求。
    if (pixels < model.minimumInputPixels) {
      scale = math.sqrt(model.minimumInputPixels / pixels);
      rounding = (value) => value.ceilToDouble();
    } else if (pixels > model.maximumInputPixels) {
      scale = math.sqrt(model.maximumInputPixels / pixels);
      rounding = (value) => value.floorToDouble();
    } else {
      scale = 1;
      rounding = (value) => value.roundToDouble();
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
      return Size(width.toDouble(), height.toDouble());
    }

    // 宽高对齐可能使总像素数越界，此时选择最接近目标的合法尺寸。
    return _boundedAlignedSize(
      width: validated.width * scale,
      height: validated.height * scale,
    );
  }

  /// 校验摄像头预设分辨率，计算不放大且宽高按 4 像素对齐的本地媒体尺寸。
  ///
  /// 详细说明见 [MediaServicing.resolveMediaSize]。
  @override
  Size resolveMediaSize(
    Size sourceMediaSize, {
    required RealtimeMediaSource source,
  }) {
    _validateIntegral(sourceMediaSize);

    final buckets = model.resolutionBuckets;

    if (source == RealtimeMediaSource.camera &&
        buckets.isNotEmpty &&
        !buckets.contains(sourceMediaSize)) {
      throw XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Model ${model.value} does not support camera resolution ${sourceMediaSize.width}×${sourceMediaSize.height}',
      );
    }

    final scale = math.min(
      1.0,
      math.sqrt(
        model.maximumInputPixels /
            (sourceMediaSize.width * sourceMediaSize.height),
      ),
    );

    return _alignedSize(sourceMediaSize, scale);
  }

  /// 在最大宽高限制内缩小回传视频，优先保留精确比例并按 4 像素对齐。
  ///
  /// 详细说明见 [MediaServicing.resolveTargetSize]。
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

    return _alignedSize(resolvedMediaSize, scale);
  }

  /// 在缩放限制内计算按 4 像素对齐的尺寸，优先保留精确宽高比。
  ///
  /// - [size]：用于尺寸解析的媒体像素宽高。
  /// - [scale]：目标尺寸相对于基准尺寸的缩放比例。
  ///
  /// 返回不超过缩放上限的对齐像素宽高；无法对齐时抛出配置错误。
  static Size _alignedSize(
    Size size,
    double scale,
  ) {
    final width = size.width.toInt(), height = size.height.toInt();
    final divisor = width.gcd(height);
    final multiplier = (divisor * scale / 4).floor() * 4;

    if (multiplier >= 4) {
      return Size(
        (width ~/ divisor * multiplier).toDouble(),
        (height ~/ divisor * multiplier).toDouble(),
      );
    }

    final w = (width * scale / 4).floor() * 4,
        h = (height * scale / 4).floor() * 4;

    if (w < 4 || h < 4) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'No aligned video size is available within the size limits',
      );
    }

    return Size(w.toDouble(), h.toDouble());
  }

  /// 校验媒体尺寸是可表示的正整数像素值。
  ///
  /// - [size]：用于尺寸解析的媒体像素宽高。
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

  /// 在模型像素范围内选择接近目标尺寸的有效对齐规格。
  ///
  /// - [width]：视频宽度，单位为像素。
  /// - [height]：视频高度，单位为像素。
  ///
  /// 返回满足模型对齐和像素数量限制的最近有效尺寸。
  Size _boundedAlignedSize({
    required double width,
    required double height,
  }) {
    final alignment = model.inputSizeAlignment;
    final unitPixels = alignment * alignment;
    final minimumUnits =
        (model.minimumInputPixels + unitPixels - 1) ~/ unitPixels;
    final maximumUnits = model.maximumInputPixels ~/ unitPixels;
    var bestSize = Size.zero;
    var bestDistance = double.infinity;

    for (var widthUnits = 1; widthUnits <= maximumUnits; widthUnits += 1) {
      final minimumHeight = (minimumUnits + widthUnits - 1) ~/ widthUnits;
      final maximumHeight = maximumUnits ~/ widthUnits;

      if (minimumHeight > maximumHeight) continue;

      final heightUnits = (height / alignment).round().clamp(
        minimumHeight,
        maximumHeight,
      );
      final candidateWidth = (widthUnits * alignment).toDouble();
      final candidateHeight = (heightUnits * alignment).toDouble();
      final distance =
          math.pow((candidateWidth - width) / width, 2) +
          math.pow((candidateHeight - height) / height, 2);

      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        bestSize = Size(candidateWidth, candidateHeight);
      }
    }

    return bestSize;
  }

  /// 校验尺寸为有限正数，并返回可继续计算的尺寸。
  ///
  /// - [size]：用于尺寸解析的媒体像素宽高。
  ///
  /// 返回按整数像素取整的有效尺寸；非有限数或非正数抛出配置错误。
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
