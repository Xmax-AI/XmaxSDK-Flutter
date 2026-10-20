//
//  RealtimeVideoTrack.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/media/camera/CameraPosition.dart';
import 'RealtimeVideoFormat.dart';

/// 实时视频轨道及其动态元数据。
final class RealtimeVideoTrack {

  /// 创建视频轨道及其规格元数据。
  RealtimeVideoTrack._({
    required this.id,
    RealtimeVideoFormat? videoFormat,
    CameraPosition? position,
  }) : _videoFormat = videoFormat,
       _position = position;

  /// 视频轨道标识；元数据更新不改变该轨道对象的身份。
  final String id;

  /// 视频尺寸、帧率和编码配置。
  RealtimeVideoFormat? _videoFormat;

  /// 当前轨道的摄像头位置元数据；未提供或不适用时为 null。
  CameraPosition? _position;

  /// 视频尺寸、帧率和编码配置。
  RealtimeVideoFormat? get videoFormat => _videoFormat;

  /// 当前轨道的摄像头位置；远端轨道或位置未知时为 null。
  CameraPosition? get position => _position;
}

/// 本地摄像头采集和预览均就绪后的内部回调。
typedef RealtimeCameraPreviewReadyListener = void Function();

/// 创建带有初始媒体规格和摄像头位置的视频轨道。
///
/// - [id]：视频轨道标识。
/// - [videoFormat]：轨道的初始视频规格。
/// - [position]：摄像头位置元数据。
///
/// 返回封装指定身份和初始元数据的视频轨道。
RealtimeVideoTrack createRealtimeVideoTrack({
  required String id,
  RealtimeVideoFormat? videoFormat,
  CameraPosition? position,
}) =>
    RealtimeVideoTrack._(id: id, videoFormat: videoFormat, position: position);

/// 更新已存在轨道的非空元数据，不替换轨道身份。
///
/// - [track]：目标视频轨道。
/// - [videoFormat]：视频尺寸、帧率和编码配置。省略时保留轨道已有的视频规格。
/// - [position]：摄像头位置元数据。省略时保留轨道已有的摄像头位置。
void updateRealtimeVideoTrack({
  required RealtimeVideoTrack track,
  RealtimeVideoFormat? videoFormat,
  CameraPosition? position,
}) {
  if (videoFormat != null) {
    track._videoFormat = videoFormat;
  }

  if (position != null) {
    track._position = position;
  }
}
