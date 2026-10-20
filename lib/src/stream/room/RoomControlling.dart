//
//  RoomControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:ui';

import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeSession.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';

/// 房间加入退出及生成、条件、尺寸和轨迹信令的内部接口。
abstract interface class RoomControlling {

  /// 加入 RTC 房间，成功后保存用户身份并启动房间心跳。
  ///
  /// - [connection]：当前会话的 RTC 房间参数。
  /// - [ensureActive]：执行前检查操作是否仍有效的函数；已失效时须抛出取消错误。
  Future<void> join({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  });

  /// 停止房间心跳、清除本地用户身份并退出 RTC 房间。
  Future<void> leave();

  /// 向已加入的房间发送生成启动信令；不在此层建立连接或等待结果首帧。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：服务端生成画布尺寸及帧率配置，不是当前上行编码档位。
  /// - [context]：本次生成条件。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。省略时不提交 target_size 字段，使用生成画布尺寸作为回传默认规格。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  Future<void> startGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  });

  /// 向当前任务发送新条件；省略参考图字段会清除先前参考图条件。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [context]：本次生成条件。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。省略时不提交 target_size 字段，使用生成画布尺寸作为回传默认规格。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  Future<void> changeGenerationCondition({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  });

  /// 提交当前生成任务的回传尺寸和下行码率预算。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。
  /// - [ensureActive]：执行前检查操作是否仍有效的函数；已失效时须抛出取消错误。
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  });

  /// 发送生成停止信令，保留 RTC 房间连接。
  ///
  /// - [taskID]：当前生成任务标识。
  Future<void> stopGeneration({
    required String taskID,
  });

  /// 提交当前生成任务的归一化交互轨迹；任务标识或触点列表为空时不发送。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [points]：0～1 范围的媒体坐标点序列，不是视图像素坐标。
  Future<void> sendTracks({
    required String taskID,
    required List<RealtimePoint> points,
  });
}
