//
//  RealtimeModel.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../service/realtime/RealtimeVideoFormat.dart';

/// SDK 当前支持的实时生成模型。
enum RealtimeModel {

  /// 国内实时生成模型。
  // ignore: constant_identifier_names
  x2_1_1_preview_cn('x2.1.1-preview-cn'),

  /// 海外实时生成模型。
  // ignore: constant_identifier_names
  x2_1_1_preview_us('x2.1.1-preview-us');

  /// 定义模型的序列化标识。
  const RealtimeModel(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;

  /// 模型展示名称。
  String get displayName => switch (this) {
    RealtimeModel.x2_1_1_preview_cn => 'X2.1.1-preview-cn',
    RealtimeModel.x2_1_1_preview_us => 'X2.1.1-preview-us',
  };

  /// 模型支持的摄像头采集分辨率和生成画布分辨率。
  List<Size> get resolutionBuckets => const [
    Size(1024, 1920),
    Size(1920, 1024),
  ];

  /// 最小输入像素数；仅在模型没有预设分辨率时用于计算尺寸。
  int get minimumInputPixels => 600000;

  /// 本地媒体允许的最大像素数；模型没有预设分辨率时，也作为生成画布的上限。
  int get maximumInputPixels => 2100000;

  /// 生成画布宽高必须为该像素数的整数倍；仅在没有预设分辨率时使用。
  int get inputSizeAlignment => 32;

  /// 未指定视频规格时使用的默认帧率。
  int get defaultFrameRate => 30;

  /// 摄像头采集使用的默认视频规格。
  RealtimeVideoFormat get defaultCameraVideoFormat =>
      const RealtimeVideoFormat(width: 1024, height: 1920, fps: 30);
}
