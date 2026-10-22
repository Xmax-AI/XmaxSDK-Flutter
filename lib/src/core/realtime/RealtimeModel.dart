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

/// SDK 当前支持的实时生成模型。
enum RealtimeModel {

  /// X2.1 实时生成模型，服务区域由客户端环境决定。
  // ignore: constant_identifier_names
  x2_1('x2.1');

  /// 定义模型的序列化标识。
  const RealtimeModel(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;

  /// 模型展示名称。
  String get displayName => switch (this) {
    RealtimeModel.x2_1 => 'X2.1',
  };

  /// 模型支持的摄像头和生成画布规格；帧率为推荐默认值。
  List<RealtimeVideoFormat> get supportedVideoFormats => const [
    RealtimeVideoFormat(width: 1920, height: 1080, fps: 30),
    RealtimeVideoFormat(width: 1080, height: 1920, fps: 30),
    RealtimeVideoFormat(width: 1408, height: 1408, fps: 30),
    RealtimeVideoFormat(width: 1152, height: 1536, fps: 30),
    RealtimeVideoFormat(width: 1536, height: 1152, fps: 30),
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
      const RealtimeVideoFormat(width: 1080, height: 1920, fps: 30);
}
