//
//  XmaxRealtimeManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/media/camera/CameraPosition.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../../service/realtime/RealtimeState.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'RealtimeConfiguration.dart';
import 'RealtimeCameraPreset.dart';
import 'RealtimeQualityLevel.dart';
import '../../foundation/rtc/VideoStatistics.dart';

/// 实时媒体采集、连接和生成接口。
abstract interface class XmaxRealtimeManaging {

  /// 创建当前管理器时使用的实时模型配置。
  RealtimeConfiguration get options;

  /// 当前实时连接与生成状态。
  Future<RealtimeState> get currentState;

  /// 当前摄像头采集规格，不随传输档位变化；没有摄像头流时为空。
  Future<RealtimeVideoFormat?> get currentCameraVideoFormat;

  /// 当前采集分辨率对应的预设；不匹配预设或没有摄像头流时为空。
  Future<RealtimeCameraPreset?> get currentCameraPreset;

  /// 当前连接成功应用的上行档位；连接完成前或开始断开后为空。
  Future<RealtimeQualityLevel?> get uplinkQualityLevel;

  /// 当前连接成功提交的下行目标档位；实际回传画面可能稍后才变化。
  /// 连接完成前或开始断开后为空。
  Future<RealtimeQualityLevel?> get downlinkQualityLevel;

  /// 原地更新摄像头规格，不重建本地流或预览视图。
  ///
  /// - [videoFormat]：完整采集规格，分辨率须属于模型支持列表。
  /// - [preset]：只更新分辨率，保留当前帧率、码率与编码偏好。
  ///
  /// 两个参数须且只能提供一个。仅允许在预览就绪且未连接时调用，
  /// 与其他媒体操作冲突或设置失败时抛出错误。
  Future<void> updateCameraFormat({
    RealtimeVideoFormat? videoFormat,
    RealtimeCameraPreset? preset,
  });

  /// 设置上行传输档位，不改变摄像头采集和模型生成规格。
  ///
  /// - [level]：目标档位，仅允许在生成中调用。
  ///
  /// 调档失败或存在冲突操作时抛出错误；成功后仍保留自动网络调档。
  Future<void> setUplinkQualityLevel(
    RealtimeQualityLevel level,
  );

  /// 设置下行回传档位，成功提交后更新目标档位，实际画面稍后生效。
  ///
  /// - [level]：目标档位，仅允许在生成中调用。
  ///
  /// 调档失败或存在冲突操作时抛出错误；成功后仍保留自动网络调档。
  Future<void> setDownlinkQualityLevel(
    RealtimeQualityLevel level,
  );

  /// 当前本地媒体预览音量，范围为 0～1。
  /// 摄像头没有本地音频播放器，返回默认值 `0.45`。
  Future<double> get localAudioVolume;

  /// 当前远端音频播放音量，范围为 0～1，精度为 0.01。
  /// 新建管理器时为 `1.0`；每次成功创建摄像头流后重置为 `0`。
  Future<double> get remoteAudioVolume;

  /// 设置状态回调，并立即通知当前状态。
  ///
  /// - [listener]：状态回调；传入 null 可取消监听。
  ///
  /// 运行失败时，通过状态中的 reason 字段报告原因。
  Future<void> setStateListener(
    RealtimeStateListener? listener,
  );

  /// 设置上行视频统计回调。
  ///
  /// - [listener]：统计回调；传入 null 可取消监听。
  ///
  /// 停止发布视频或断开连接时，回调参数为 null，表示清除统计数据。
  Future<void> setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  );

  /// 设置当前生成结果流的下行视频统计回调。
  ///
  /// - [listener]：统计回调；传入 null 可取消监听。
  ///
  /// 结果流清理后，回调参数为 null，表示清除统计数据。
  Future<void> setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  );

  /// 设置上下行网络质量回调，不影响 SDK 内部的自适应调节。
  ///
  /// - [listener]：网络质量回调；传入 null 可取消监听。
  Future<void> setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  );

  /// 设置性能受限或恢复时的回调。
  ///
  /// - [listener]：性能状态回调；传入 null 可取消监听。
  Future<void> setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  );

  /// 设置本地预览音量。
  ///
  /// 摄像头没有本地音频播放器，因此仅校验参数，不调整音量；读取值仍为 0.45。
  ///
  /// - [volume]：音量，范围为 0～1；超出范围、NaN 或无穷大时抛出 invalidConfiguration 错误。
  Future<void> setLocalAudioVolume(
    double volume,
  );

  /// 设置远端音频播放音量，精度为 0.01。
  ///
  /// 尚未订阅音频时先保存设置，订阅前再应用；RTC 设置失败时保留上次成功值。
  /// 每次成功创建摄像头流后，远端音量重置为 0。需要播放声音时，请在创建摄像头流后设置。
  ///
  /// - [volume]：音量，范围为 0～1；超出范围、NaN 或无穷大时抛出 invalidConfiguration 错误。
  Future<void> setRemoteAudioVolume(
    double volume,
  );

  /// 创建本地摄像头流并开始预览。
  ///
  /// - [videoFormat]：采集尺寸、帧率和编码配置。
  /// - [position]：摄像头位置，默认使用前置摄像头。
  ///
  /// 返回本地媒体流。收到首帧且预览视图挂载后，状态更新为 ready；
  /// 需要等待预览就绪时，请监听状态变化。参数无效或未获授权时抛出相应错误。
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    CameraPosition position = CameraPosition.front,
  });

  /// 停止摄像头并释放采集资源。调用前须先断开实时连接。
  Future<void> stopLocalCameraStream();

  /// 切换前后置摄像头。
  ///
  /// 生成期间会先停止任务，再用缓存的生成条件和人脸回贴设置恢复生成，不断开 RTC 连接。
  ///
  /// 返回切换后的本地摄像头流。
  Future<RealtimeMediaStream> switchCamera();

  /// 创建云端会话，连接 RTC 房间并发布本地视频。
  ///
  /// - [localStream]：本地媒体流，必须由当前管理器创建且尚未停止。
  ///
  /// 返回用于显示生成结果的远端媒体流。
  Future<RealtimeMediaStream> connect({
    required RealtimeMediaStream localStream,
  });

  /// 停止生成并断开远端连接，保留本地摄像头预览。
  ///
  /// - [reason]：断开原因；默认 normal，表示主动结束。
  Future<void> disconnect({
    RealtimeReason reason = RealtimeReason.normal,
  });

  /// 停止生成、断开连接并释放本地采集资源。
  ///
  /// 重复调用会等待同一次清理完成。清理后仍可用当前管理器重新创建本地媒体流。
  Future<void> close();

  /// 开始生成；已在生成时，改为更新生成条件，不重新等待首帧。
  ///
  /// 首次生成必须提供条件。启动过程中也可以更新条件或断开连接。
  ///
  /// - [localStream]：本地媒体流；需要自动连接时提供，已连接时可省略。
  /// - [context]：生成条件；首次必填，之后传入 null 会沿用最近成功提交的条件。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用均使用本次传入的值。
  ///
  /// 提供 [localStream] 时返回当前远端媒体流，否则返回 null。
  /// 首次启动会等待结果流确认、首帧解码和音频激活；更新条件只等待信令发送完成。
  Future<RealtimeMediaStream?> startGeneration({
    RealtimeMediaStream? localStream,
    RealtimeContext? context,
    bool faceRestoration = false,
  });
}
