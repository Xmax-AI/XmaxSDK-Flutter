//
//  StreamControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:ui';

import '../service/realtime/RealtimeContext.dart';
import '../service/realtime/RealtimeNetworkQuality.dart';
import '../service/realtime/RealtimePerformanceAlarm.dart';
import '../service/realtime/RealtimePoint.dart';
import '../service/realtime/RealtimeSession.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../foundation/rtc/VideoStatistics.dart';

/// 等待生成结果流的任务，可主动取消。
///
/// 启动信令发送成功后，[value] 继续等待服务端发布匹配的结果流。
/// 调用 [cancel] 可结束等待，但不退出 RTC 房间，后续任务仍可复用该连接。
final class GenerationStartConfirmation {

  /// 创建可取消的生成结果确认任务。
  GenerationStartConfirmation({
    required this.value,
    required void Function() onCancel,
  }) : _onCancel = onCancel;

  /// 等待结果流确认的异步任务；失败或取消时抛出异常。
  final Future<void> value;

  /// 主动取消结果流确认时执行的函数。
  final void Function() _onCancel;

  /// 取消结果流等待，不退出 RTC 房间。
  void cancel() => _onCancel();
}

/// 实时媒体连接、生成信令和网络质量控制的内部接口。
abstract interface class StreamControlling {

  /// 读取模型的有效档位历史，准备独立上下行策略并应用初始传输规格。
  ///
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [model]：实时模型；用于确定会话路由及媒体规格约束。
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
  });

  /// 生成结果的回传宽高，单位为像素。
  Size? get targetSize;

  /// 设置上行视频统计监听器；停止发布或断开连接时通知 null。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  );

  /// 设置当前结果流的下行视频统计监听器；结果流清理时通知 null。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  );

  /// 是否有正在启动或运行的生成任务。
  bool get hasGenerationTask;

  /// 远端音频播放音量，范围为 0～1，精度为 0.01。
  double get remoteAudioVolume;

  /// 解析视频码率预算并应用 RTC 编码配置。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  Future<void> setVideoEncoderConfig(
    RealtimeVideoFormat videoFormat,
  );

  /// 设置上下行网络质量监听器，不替换 SDK 内部自适应策略。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  );

  /// 设置性能受限及恢复事件的监听器。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  );

  /// 设置远端音频音量，范围为 0～1，精度为 0.01；RTC 调用失败时保留上次成功值。
  ///
  /// - [volume]：0～1 范围内的有限音量值。
  Future<void> setRemoteAudioVolume(
    double volume,
  );

  /// 在结果流确认后应用音量并订阅远端音频，同时允许网络自适应。
  Future<void> activateRemoteAudio();

  /// 使用已有会话凭证加入 RTC 房间，并发布本地视频。
  ///
  /// - [connection]：当前会话的 RTC 房间参数。
  /// - [ensureActive]：执行前检查操作是否仍有效的函数；已失效时须抛出取消错误。
  Future<void> connect({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  });

  /// 结束当前生成并断开远端连接，保留本地摄像头预览。
  Future<void> disconnect();

  /// 发送生成启动信令，并返回可取消的结果流等待任务。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：生成画布的尺寸和帧率配置。
  /// - [context]：本次生成条件。
  /// - [targetSize]：回传宽高；未指定时不发送 target_size 字段，默认使用生成画布尺寸。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭。
  ///
  /// 返回的任务仅在匹配到预期用户且已订阅的视频流后完成。
  Future<GenerationStartConfirmation> beginGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  });

  /// 等待当前调档完成后更新当前生成条件，使用最新回传尺寸。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [context]：本次生成条件。
  /// - [targetSize]：未准备质量策略时使用的回传尺寸；优先使用当前自适应尺寸，省略且无当前尺寸时不发送该字段。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  Future<void> updateGeneration({
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

  /// 停止当前生成任务和交互输入，保留 RTC 连接。
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
