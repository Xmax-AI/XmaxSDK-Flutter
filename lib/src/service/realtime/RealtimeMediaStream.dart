//
//  RealtimeMediaStream.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeVideoTrack.dart';

/// 实时生成输入或输出的媒体流。
final class RealtimeMediaStream {

  /// 创建媒体流及其视频轨道关联。
  const RealtimeMediaStream._({
    required this.id,
    this.videoTrack,
  });

  /// 当前媒体流的标识，视频显示使用关联的 videoTrack。
  final String id;

  /// 媒体流关联的视频轨道。
  final RealtimeVideoTrack? videoTrack;
}

/// 创建关联指定视频轨道的媒体流。
///
/// - [id]：媒体流标识。
/// - [videoTrack]：用于显示该流的视频轨道。
///
/// 返回持有指定身份和视频轨道的媒体流对象。
RealtimeMediaStream createRealtimeMediaStream({
  required String id,
  RealtimeVideoTrack? videoTrack,
}) => RealtimeMediaStream._(id: id, videoTrack: videoTrack);
