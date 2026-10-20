//
//  RtcManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/media/camera/CameraPosition.dart';
import 'RtcEventListener.dart';
import 'RtcModels.dart';

/// RTC 采集、编码、房间、发布订阅和音量控制的内部接口。
abstract interface class RtcManaging {

  /// 获取并初始化当前生命周期使用的 RTC 引擎。
  Future<void> initialize();

  /// 关闭当前 RTC 资源，并使后续原生回调失效。
  Future<void> destroy();

  /// 将视频分辨率、帧率、码率及编码偏好应用到 RTC。
  ///
  /// - [configuration]：视频分辨率、帧率、最低与目标码率及编码偏好。
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  );

  /// 按给定规格启动摄像头采集和本地预览，不开启麦克风。
  ///
  /// - [width]：视频宽度，单位为像素。
  /// - [height]：视频高度，单位为像素。
  /// - [frameRate]：视频帧率，单位为 fps。
  Future<void> startVideoCapture({
    required int width,
    required int height,
    required int frameRate,
  });

  /// 停止本地预览和摄像头采集。
  Future<void> stopVideoCapture();

  /// 将原生采集切换到指定摄像头。
  ///
  /// - [position]：需要切换到的摄像头位置。
  Future<void> switchCamera({
    required CameraPosition position,
  });

  /// 加入指定 RTC 房间，并在失败时清理本次房间资源。
  ///
  /// - [configuration]：本次入房使用的房间标识、用户账号和访问令牌。
  Future<void> joinRoom({
    required RoomJoinConfiguration configuration,
  });

  /// 退出当前 RTC 房间，取消待发信令并移除房间事件。
  Future<void> leaveRoom();

  /// 设置当前房间是否发布摄像头视频；不发布麦克风音频。
  ///
  /// - [publish]：是否发布本地摄像头视频。
  Future<void> publishLocalVideo({
    required bool publish,
  });

  /// 设置是否接收指定远端用户的视频。
  ///
  /// - [streamID]：远端视频流标识，用于查找对应的数字 UID。
  /// - [subscribe]：是否订阅指定用户的远端媒体。
  Future<void> subscribeRemoteVideo({
    required String streamID,
    required bool subscribe,
  });

  /// 设置是否接收指定远端用户的音频。
  ///
  /// - [streamID]：远端音频流标识，用于查找对应的数字 UID。
  /// - [subscribe]：是否订阅指定用户的远端媒体。
  Future<void> subscribeRemoteAudio({
    required String streamID,
    required bool subscribe,
  });

  /// 将指定远端用户的播放音量百分比提交给 RTC。
  ///
  /// - [volume]：0～100 范围内的远端播放音量百分比。
  /// - [streamID]：需要调整播放音量的远端音频流标识。
  Future<void> setRemoteAudioVolume({
    required int volume,
    required String streamID,
  });

  /// 按队列顺序发送完整房间 JSON 信令，必要时进行分片和限速。
  ///
  /// - [message]：完整消息文本。
  Future<void> sendRoomMessage(
    String message,
  );

  /// 替换 RTC 内部事件监听器。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setEventListener(
    RtcEventListener? listener,
  );

  /// 设置本地摄像头首帧就绪的内部通知。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setCameraPreviewReadyListener(
    void Function()? listener,
  );
}
