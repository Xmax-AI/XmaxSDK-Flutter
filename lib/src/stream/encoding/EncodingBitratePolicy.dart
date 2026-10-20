//
//  EncodingBitratePolicy.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:math' as math;

import '../../foundation/errors/XmaxError.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// 根据视频规格计算上下行可复用的编码预算，单位为 kbps。
abstract final class EncodingBitratePolicy {

  /// 校验视频规格并计算最低、最高码率；显式码率配置优先于默认曲线。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  ///
  /// 返回最低和最高码率，单位为 kbps。
  static (int, int) resolve(
    RealtimeVideoFormat videoFormat,
  ) {
    videoFormat.validate();

    final int minimum;
    final int maximum;
    final explicitMinimum = videoFormat.minimumBitrate;
    final explicitMaximum = videoFormat.maximumBitrate;

    if (explicitMinimum != null && explicitMaximum != null) {
      minimum = explicitMinimum;
      maximum = explicitMaximum;
    } else {
      final defaults = _defaultBitrates(videoFormat);

      minimum = explicitMinimum ?? defaults.$1;
      maximum = explicitMaximum ?? defaults.$2;
    }

    if (minimum > maximum) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Minimum bitrate must not exceed maximum bitrate after applying '
            'SDK defaults',
      );
    }

    return (minimum, maximum);
  }

  /// 计算视频规格的默认最低和最高码率预算。
  ///
  /// - [format]：目标视频尺寸、帧率和编码配置。
  ///
  /// 返回最低和最高码率，单位为 kbps。
  static (int, int) _defaultBitrates(
    RealtimeVideoFormat format,
  ) {
    final bitrates = _resolveBitrates(
      pixels: format.width.toDouble() * format.height.toDouble(),
      fps: format.fps.toDouble(),
    );
    final value = bitrates.$2 * 0.6;
    final floor = value.floorToDouble();
    final roundedMaximum = value - floor == 0.5 && floor % 2 == 0
        ? floor
        : value.roundToDouble();

    // 拒绝超出原生有符号整数范围的码率。
    if (!roundedMaximum.isFinite || roundedMaximum >= 9223372036854775808.0) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Realtime video format exceeds the supported bitrate range',
      );
    }

    return (100, math.max(100, roundedMaximum.toInt()));
  }

  // 参考曲线按像素面积插值，表外尺寸按最近端点比例外推。

  /// 15 fps 对应的像素量与参考码率采样表。
  static const _referenceBitratesAt15FPS = <_BitratePoint>[
    _BitratePoint(120 * 120, 50),
    _BitratePoint(160 * 120, 65),
    _BitratePoint(180 * 180, 100),
    _BitratePoint(240 * 180, 120),
    _BitratePoint(320 * 180, 140),
    _BitratePoint(320 * 240, 200),
    _BitratePoint(424 * 240, 220),
    _BitratePoint(360 * 360, 260),
    _BitratePoint(480 * 360, 320),
    _BitratePoint(640 * 360, 400),
    _BitratePoint(640 * 480, 500),
    _BitratePoint(848 * 480, 610),
    _BitratePoint(960 * 720, 910),
    _BitratePoint(1280 * 720, 1130),
    _BitratePoint(1920 * 1080, 2080),
  ];

  /// 30 fps 对应的像素量与参考码率采样表。
  static const _referenceBitratesAt30FPS = <_BitratePoint>[
    _BitratePoint(360 * 360, 400),
    _BitratePoint(480 * 360, 490),
    _BitratePoint(640 * 360, 600),
    _BitratePoint(640 * 480, 750),
    _BitratePoint(848 * 480, 930),
    _BitratePoint(960 * 720, 1380),
    _BitratePoint(1280 * 720, 1710),
    _BitratePoint(1920 * 1080, 3150),
  ];

  /// 按像素量和帧率插值计算参考码率预算。
  ///
  /// - [pixels]：视频宽高相乘得到的总像素数。
  /// - [fps]：视频帧率，单位为 fps。
  ///
  /// 返回参考最低和最高码率，单位为 kbps。
  static (double, double) _resolveBitrates({
    required double pixels,
    required double fps,
  }) {
    final bitrate15 = _interpolate(pixels, _referenceBitratesAt15FPS);
    final first30 = _referenceBitratesAt30FPS.first;
    final bitrate30 = pixels < first30.value
        ? bitrate15 *
              (first30.bitrate /
                  _interpolate(first30.value, _referenceBitratesAt15FPS))
        : _interpolate(pixels, _referenceBitratesAt30FPS);

    // 10fps 沿用 15fps 尺寸曲线；60fps 沿用 30fps 尺寸曲线。
    final bitrate10 = bitrate15 * (400.0 / 500);
    final minimum60 = bitrate30 * (4780.0 / 3150);
    final maximum60 = bitrate30 * (6500.0 / 3150);

    return (
      _interpolate(fps, <_BitratePoint>[
        _BitratePoint(10, bitrate10),
        _BitratePoint(15, bitrate15),
        _BitratePoint(30, bitrate30),
        _BitratePoint(60, minimum60),
      ]),
      _interpolate(fps, <_BitratePoint>[
        _BitratePoint(10, bitrate10 * 2),
        _BitratePoint(15, bitrate15 * 2),
        _BitratePoint(30, bitrate30 * 2),
        _BitratePoint(60, maximum60),
      ]),
    );
  }

  /// 对参考曲线的相邻采样点进行线性插值或边界外推。
  ///
  /// - [value]：待求参考码率的总像素量。
  /// - [points]：按总像素量升序排列的码率参考曲线采样点。
  ///
  /// 返回计算得到的数值。
  static double _interpolate(
    double value,
    List<_BitratePoint> points,
  ) {
    final first = points.first;

    if (value <= first.value) {
      return first.bitrate * (value / first.value);
    }

    for (var index = 1; index < points.length; index++) {
      final upper = points[index];

      if (value <= upper.value) {
        final lower = points[index - 1];
        final ratio = (value - lower.value) / (upper.value - lower.value);

        return lower.bitrate + (upper.bitrate - lower.bitrate) * ratio;
      }
    }

    final last = points.last;

    return last.bitrate * (value / last.value);
  }
}

/// 码率参考曲线上的像素量与码率采样点。
final class _BitratePoint {

  /// 创建码率曲线采样点。
  const _BitratePoint(
    this.value,
    this.bitrate,
  );

  /// 参考曲线采样点的总像素量。
  final double value;

  /// 参考码率，单位为 kbps。
  final double bitrate;
}
