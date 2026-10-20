//
//  MediaControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../foundation/media/camera/CameraPosition.dart';
import '../service/realtime/RealtimeMediaStream.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import 'interaction/InteractionControlling.dart';

/// 本地媒体创建、停止、切换和所有权检查的内部接口。
abstract interface class MediaControlling implements InteractionControlling {

  /// 当前有效的本地视频轨道；尚未创建或已停止时为空。
  RealtimeVideoTrack? get currentTrack;

  /// 当前本地轨道的视频规格；尚未创建时为空。
  RealtimeVideoFormat? get currentVideoFormat;

  /// 本地媒体是否包含可播放音频；摄像头来源为 false。
  bool get hasAudio;

  /// 本地媒体预览音量；摄像头没有音频播放器，固定为 0.45。
  Future<double> get localAudioVolume;

  /// 设置本地摄像头首帧就绪的内部通知。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setCameraPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  );

  /// 创建本地摄像头流并开始预览，就绪后调用预览监听器。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [position]：要使用的摄像头位置。
  ///
  /// 返回新建的本地摄像头媒体流；参数或权限错误通过 Future 抛出。
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
  });

  /// 停止本地摄像头流并释放采集资源。
  Future<void> stopLocalCameraStream();

  /// 停止当前本地媒体来源并释放其 RTC 引擎使用权。
  Future<void> stopLocalStream();

  /// 切换前后置摄像头。
  ///
  /// 返回切换后的本地摄像头媒体流。
  Future<RealtimeMediaStream> switchCamera();

  /// 校验并设置本地媒体音量；摄像头没有音频播放器，合法设置不改变默认读取值 0.45。
  ///
  /// - [volume]：0～1 范围内的有限音量值。
  Future<void> setLocalAudioVolume(
    double volume,
  );

  /// 检查媒体流是否属于当前本地媒体生命周期。
  ///
  /// - [stream]：待检查的本地媒体流。
  ///
  /// 返回媒体流是否属于当前本地媒体生命周期。
  bool owns(
    RealtimeMediaStream stream,
  );
}
