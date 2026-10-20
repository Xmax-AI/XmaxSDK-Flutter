//
//  RoomEvent.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:convert';
import 'dart:ui';

import '../../foundation/runtime/RuntimeInfo.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimePoint.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../encoding/EncodingBitratePolicy.dart';
import '../../foundation/errors/XmaxError.dart';

/// 编码包含用户、任务和运行环境信息的房间 JSON 信令。
abstract final class RoomEvent {

  /// 编码生成启动信令，包含模型画布、回传规格和本次生成条件。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：服务端生成画布的尺寸和帧率配置。
  /// - [context]：本次生成条件。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。省略时不提交 target_size 字段，使用生成画布尺寸作为回传默认规格。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  ///
  /// 返回包含启动参数、任务关联字段和运行环境的 JSON 文本。
  static String start({
    required String userID,
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) => _generation(
    event: 'start',
    userID: userID,
    taskID: taskID,
    videoFormat: videoFormat,
    context: context,
    targetSize: targetSize,
    faceRestoration: faceRestoration,
    includeBitrates: true,
  );

  /// 编码生成条件变更信令，包含本次人脸回贴设置。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：服务端生成画布的尺寸和帧率配置。
  /// - [context]：本次生成条件。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。省略时不提交 target_size 字段，使用生成画布尺寸作为回传默认规格。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  ///
  /// 返回本次提示词、可选参考图和人脸回贴配置的 JSON 文本。
  static String changeCondition({
    required String userID,
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) => _generation(
    event: 'change_condition',
    userID: userID,
    taskID: taskID,
    videoFormat: videoFormat,
    context: context,
    targetSize: targetSize,
    faceRestoration: faceRestoration,
  );

  /// 编码回传尺寸及相应下行码率预算的变更信令。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  /// - [taskID]：当前生成任务标识。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。
  ///
  /// 返回回传尺寸和下行码率预算事件的 JSON 文本。
  static String changeTargetSize({
    required String userID,
    required String taskID,
    required Size targetSize,
  }) => _encode(<String, Object?>{
    'event': 'change_target_size',
    'params': <String, Object?>{
      'target_size': _size(targetSize),
      ..._downlinkBitrates(targetSize),
    },
    'user_id': userID,
    'uid': taskID,
  });

  /// 编码指定生成任务的停止信令。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  /// - [taskID]：当前生成任务标识。
  ///
  /// 返回包含用户、任务关联字段和运行环境的停止事件 JSON。
  static String stop({
    required String userID,
    required String taskID,
  }) => _encode(<String, Object?>{
    'event': 'stop',
    'user_id': userID,
    'uid': taskID,
  });

  /// 编码当前任务的归一化交互轨迹信令。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  /// - [taskID]：当前生成任务标识。
  /// - [points]：0～1 范围的媒体坐标点序列，不是视图像素坐标。
  ///
  /// 返回包含归一化点序列的交互轨迹 JSON 文本。
  static String tracks({
    required String userID,
    required String taskID,
    required List<RealtimePoint> points,
  }) => _encode(<String, Object?>{
    'event': 'tracks',
    'tracks': points.map((point) => <double>[point.x, point.y]).toList(),
    'user_id': userID,
    'uid': taskID,
  });

  /// 编码当前用户的房间心跳信令。
  ///
  /// - [userID]：RTC 用户账号，不是数字 UID。
  ///
  /// 返回包含当前房间用户和运行环境的心跳 JSON 文本。
  static String heartbeat({
    required String userID,
  }) => _encode(<String, Object?>{'event': 'heartbeat', 'user_id': userID});

  /// 编码生成启动或条件变更信令，并按需加入回传尺寸和码率预算。
  ///
  /// - [event]：待编码的房间事件。
  /// - [userID]：RTC 用户账号，不是数字 UID。
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：服务端生成画布的尺寸和帧率配置。
  /// - [context]：本次生成条件。
  /// - [targetSize]：生成结果的回传宽高，单位为像素。省略时不提交 target_size 字段，使用生成画布尺寸作为回传默认规格。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  /// - [includeBitrates]：是否在生成信令中加入下行码率预算。省略时不附带码率预算。
  ///
  /// 返回包含本次生成条件和可选传输参数的 JSON 文本。
  static String _generation({
    required String event,
    required String userID,
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
    bool includeBitrates = false,
  }) {
    final params = <String, Object?>{
      'model': 'default',
      'size': <int>[videoFormat.width, videoFormat.height],
      'prompt': context.prompt,
      'face_replace': faceRestoration,
      if (includeBitrates) 'mirror': false,
      if (includeBitrates)
        ..._downlinkBitrates(
          targetSize ??
              Size(videoFormat.width.toDouble(), videoFormat.height.toDouble()),
        ),
    };
    final referencePath = context.referencePath;

    if (targetSize != null) {
      params['target_size'] = _size(targetSize);
    }

    if (referencePath != null) {
      params['ref_image_path'] = referencePath;
    }

    // 不发送参考图字段时，服务端会清除之前的参考图条件。
    return _encode(<String, Object?>{
      'event': event,
      'params': params,
      'user_id': userID,
      'uid': taskID,
    });
  }

  /// 将像素尺寸转换为按宽、高排列的整数数组。
  ///
  /// - [value]：待编码的像素尺寸。
  ///
  /// 返回按宽、高排列的像素整数数组。
  static List<int> _size(
    Size value,
  ) => <int>[
    value.width.toInt(),
    value.height.toInt(),
  ];

  /// 编码房间 JSON 信令，附带运行环境和可用的任务关联标识。
  ///
  /// - [event]：待编码的房间事件。
  ///
  /// 返回附带 runtime 及可用 session_uid 的 JSON 文本。
  static String _encode(
    Map<String, Object?> event,
  ) => jsonEncode(<String, Object?>{
    ...event,
    if (event['uid'] != null) 'session_uid': event['uid'],
    'runtime': RuntimeInfo.current.toJson(),
  });

  /// 按回传尺寸和 24 fps 计算下行码率预算，最高不超过 10000 kbps。
  ///
  /// - [size]：目标视频宽高，单位为像素。
  ///
  /// 返回 min_bitrate 和 max_bitrate，单位为 kbps。
  static Map<String, int> _downlinkBitrates(
    Size size,
  ) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 2 ||
        size.height < 2 ||
        size.width != size.width.truncateToDouble() ||
        size.height != size.height.truncateToDouble()) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Invalid return video dimensions',
      );
    }

    final budget = EncodingBitratePolicy.resolve(
      RealtimeVideoFormat(
        width: size.width.toInt(),
        height: size.height.toInt(),
        fps: 24,
      ),
    );

    return {'min_bitrate': 100, 'max_bitrate': budget.$2.clamp(100, 10000)};
  }
}
