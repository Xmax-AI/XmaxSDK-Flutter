//
//  RtcModels.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// 加入 RTC 房间所需的房间标识、用户账号和令牌。
final class RoomJoinConfiguration {

  /// 创建 RTC 入房凭证。
  const RoomJoinConfiguration({
    required this.roomID,
    required this.userID,
    required this.token,
  });

  /// 云端分配的 RTC 房间标识。
  final String roomID;

  /// RTC 用户账号，不是数字 UID。
  final String userID;

  /// 加入房间使用的 RTC 访问令牌。
  final String token;
}

/// 提交给 RTC 编码器的分辨率、帧率、码率及降级偏好。
final class VideoEncodingConfiguration {

  /// 创建 RTC 视频编码配置。
  const VideoEncodingConfiguration({
    required this.width,
    required this.height,
    required this.frameRate,
    this.minimumBitrate = 0,
    this.maximumBitrate = -1,
    this.encoderPreference = RealtimeVideoEncoderPreference.auto,
  });

  /// 编码视频宽度，单位为像素。
  final int width;

  /// 编码视频高度，单位为像素。
  final int height;

  /// 视频帧率，单位为 fps。
  final int frameRate;

  /// 最低编码码率，单位为 kbps；默认 0，使用 RTC 的最低码率策略。
  final int minimumBitrate;

  /// 编码目标码率，单位为 kbps，传给 RTC 的 bitrate；默认 -1，使用 RTC 兼容码率模式。
  final int maximumBitrate;

  /// 带宽变化时的帧率与画质取舍策略，默认自动平衡。
  final RealtimeVideoEncoderPreference encoderPreference;
}

/// 远端用户的视频流标识及原生渲染所需的绑定信息。
final class RemoteStream {

  /// 创建远端媒体流绑定信息。
  const RemoteStream({
    required this.roomID,
    required this.userID,
    required this.streamID,
    this.uid,
    this.engine,
  });

  /// 云端分配的 RTC 房间标识。
  final String roomID;

  /// RTC 用户账号，不是数字 UID。
  final String userID;

  /// 远端视频流标识。
  final String streamID;

  /// 原生 RTC 分配的数字用户标识；未解析出 UID 时不能创建远端视频纹理。
  final int? uid;

  /// 远端视频渲染使用的 RTC 引擎；未指定时不能创建视频纹理。
  final RtcEngine? engine;

  /// 房间与远端账号的组合标识，用于匹配同一用户的媒体事件。
  String get key => '$roomID:$userID';
}
