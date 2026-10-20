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

/// 本地媒体、生成画布和回传视频的尺寸解析接口。
abstract interface class MediaServicing {

  /// 当前媒体服务使用的模型，决定输入尺寸约束。
  RealtimeModel get model;

  /// 校验摄像头预设分辨率，计算不放大且宽高按 4 像素对齐的本地媒体尺寸。
  ///
  /// - [sourceMediaSize]：原始本地媒体的像素尺寸，宽高必须为正整数。
  /// - [source]：媒体来源类型；摄像头必须精确匹配模型预设分辨率。
  ///
  /// 返回不放大来源、满足像素数量限制且宽高按 4 像素对齐的媒体尺寸。
  Size resolveMediaSize(
    Size sourceMediaSize, {
    required RealtimeMediaSource source,
  });

  /// 选择宽高比最接近本地媒体的模型生成画布，不修改本地采集规格。
  ///
  /// - [resolvedMediaSize]：处理后的本地媒体像素尺寸。
  ///
  /// 返回宽高比最接近处理后媒体的模型生成画布尺寸。
  Size resolveGenerationSize(
    Size resolvedMediaSize,
  );

  /// 在最大宽高限制内缩小回传视频，优先保留精确比例并按 4 像素对齐。
  ///
  /// - [resolvedMediaSize]：处理后的本地媒体像素尺寸。
  /// - [maximumSize]：回传视频允许的最大宽高，单位为像素。
  ///
  /// 返回不超过媒体和回传上限、宽高按 4 像素对齐的回传尺寸。
  Size resolveTargetSize(
    Size resolvedMediaSize, {
    required Size maximumSize,
  });
}
