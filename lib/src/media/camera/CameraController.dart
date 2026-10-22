//
//  CameraController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/permissions/PermissionManager.dart';
import '../../foundation/permissions/PermissionManaging.dart';
import '../../foundation/rtc/RtcManaging.dart';
import '../../foundation/rtc/RtcManager.dart';
import '../../core/realtime/RealtimeMediaSource.dart';
import '../../render/video/VideoRenderBinding.dart';
import '../../render/video/VideoRenderRegistry.dart';
import '../../service/media/MediaService.dart';
import '../../service/media/MediaServicing.dart';
import '../../service/realtime/RealtimeMediaStream.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../service/realtime/RealtimeVideoTrack.dart';
import '../../foundation/media/camera/CameraPosition.dart';

/// 申请摄像头权限并创建采集轨道，在首帧和预览挂载后通知就绪。
final class CameraController {

  /// 创建摄像头控制器。
  ///
  /// - [rtcManager]：采集和本地预览入口。
  /// - [permissionManager]：媒体权限检查入口，默认查询系统权限。
  /// - [mediaService]：尺寸解析服务，默认使用 [MediaService] 的模型配置。
  CameraController({
    required RtcManaging rtcManager,
    PermissionManaging permissionManager = const PermissionManager(),
    MediaServicing? mediaService,
  }) : _rtcManager = rtcManager,
       _permissionManager = permissionManager,
       _mediaService = mediaService ?? MediaService();

  /// 本地摄像头视频轨道的内部标识。
  static const localVideoTrackID = 'video0';

  /// 本地摄像头媒体流的内部标识。
  static const localStreamID = 'stream-local';

  /// RTC 采集、房间及传输操作入口。
  final RtcManaging _rtcManager;

  /// 媒体采集权限检查入口。
  final PermissionManaging _permissionManager;

  /// 媒体、生成及回传尺寸解析服务。
  final MediaServicing _mediaService;

  /// 当前摄像头流持有的视频轨道。
  RealtimeVideoTrack? _activeTrack;

  /// 正在创建、尚未启用的视频轨道。
  RealtimeVideoTrack? _preparingTrack;

  /// 本地摄像头首帧及预览挂载均就绪后的通知。
  RealtimeCameraPreviewReadyListener? _previewReadyListener;

  /// 当前本地轨道是否已采集到有效首帧。
  bool _hasCapturedFrame = false;

  /// 本地视频原生预览是否已完成挂载。
  bool _isPreviewAttached = false;

  /// 当前本地轨道是否已通知预览就绪。
  bool _didNotifyPreviewReady = false;

  /// 当前有效的本地视频轨道；尚未创建或已停止时为空。
  RealtimeVideoTrack? get currentTrack => _activeTrack;

  /// 设置首帧与原生预览均就绪后的通知。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  void setPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  ) {
    _previewReadyListener = listener;
    if (_didNotifyPreviewReady) listener?.call();
  }

  /// 创建本地摄像头流并开始预览，首帧采集和视图挂载均完成后触发就绪回调。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [position]：摄像头位置；创建流时默认使用前置摄像头。
  ///
  /// 返回新建的本地摄像头媒体流；参数或权限错误通过 Future 抛出。
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
  }) async {
    if (_activeTrack != null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Stop the current local camera stream before creating another one',
      );
    }

    final format = _resolveVideoFormat(videoFormat);
    final track = createRealtimeVideoTrack(
      id: localVideoTrackID,
      videoFormat: format,
      position: position,
    );

    _preparingTrack = track;
    _hasCapturedFrame = false;
    _isPreviewAttached = false;
    _didNotifyPreviewReady = false;

    try {
      await _permissionManager.ensureCameraPermission();

      // RtcManager.destroy() 会清除原生回调。
      // 管理器保留预览监听器，每次重新创建摄像头流时再次注册。
      _rtcManager.setCameraPreviewReadyListener(() => _capturedFrame(track));
      await _rtcManager.switchCamera(position: position);
      await _rtcManager.startVideoCapture(
        width: format.width,
        height: format.height,
        frameRate: format.fps,
      );

      // 摄像头采集成功后再注册预览渲染。
      VideoRenderRegistry.register(
        track,
        LocalVideoRenderBinding(
          onPreviewAttached: () => _previewAttached(track),
          engine: _rtcManager is RtcManager ? _rtcManager.renderEngine : null,
        ),
      );
      _activeTrack = track;
      _notifyPreviewReady(track);

      return createRealtimeMediaStream(id: localStreamID, videoTrack: track);
    } catch (error) {
      if (identical(_preparingTrack, track)) {
        _preparingTrack = null;
      }
      // 创建中途失败时，同时撤销渲染注册并停止采集。
      VideoRenderRegistry.unregister(track);

      try {
        await _rtcManager.stopVideoCapture();
      } catch (cleanupError) {
        XmaxLogger.error(
          category: XmaxLoggerCategory.realtime,
          message:
              '回滚 RTC 相机采集失败 (Failed to Roll Back RTC Camera Capture)\n'
              '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$cleanupError',
        );
      }

      throw XmaxError.from(error);
    }
  }

  /// 停止本地摄像头流并释放采集资源；公开管理器仅允许在实时连接断开后调用。
  Future<void> stopLocalCameraStream() async {
    final track = _activeTrack;

    _activeTrack = null;
    _preparingTrack = null;
    _hasCapturedFrame = false;
    _isPreviewAttached = false;
    _didNotifyPreviewReady = false;

    if (track != null) {
      VideoRenderRegistry.unregister(track);
    }

    await _rtcManager.stopVideoCapture();
  }

  /// 记录指定本地轨道已采集首帧，并检查预览是否就绪。
  ///
  /// - [track]：目标视频轨道。
  void _capturedFrame(
    RealtimeVideoTrack track,
  ) {
    if (!identical(_preparingTrack, track)) return;

    _hasCapturedFrame = true;
    _notifyPreviewReady(track);
  }

  /// 记录指定本地轨道的原生预览已挂载。
  ///
  /// - [track]：目标视频轨道。
  void _previewAttached(
    RealtimeVideoTrack track,
  ) {
    if (!identical(_preparingTrack, track)) return;

    _isPreviewAttached = true;
    _notifyPreviewReady(track);
  }

  /// 首帧采集和预览视图挂载都完成后，通知预览就绪；每个轨道只通知一次。
  ///
  /// - [track]：目标视频轨道。
  void _notifyPreviewReady(
    RealtimeVideoTrack track,
  ) {
    if (_didNotifyPreviewReady ||
        !_hasCapturedFrame ||
        !_isPreviewAttached ||
        !identical(_activeTrack, track)) {
      return;
    }

    _didNotifyPreviewReady = true;
    _previewReadyListener?.call();
  }

  /// 切换前后置摄像头，返回更新后的本地媒体流。
  ///
  /// 返回切换后的本地摄像头媒体流。
  Future<RealtimeMediaStream> switchCamera() async {
    final track = _activeTrack;
    final position = track?.position;

    if (track == null || track.videoFormat == null || position == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Local camera preview is not started',
      );
    }

    final next = position == CameraPosition.front
        ? CameraPosition.back
        : CameraPosition.front;

    try {
      await _rtcManager.switchCamera(position: next);
      updateRealtimeVideoTrack(track: track, position: next);

      return createRealtimeMediaStream(id: localStreamID, videoTrack: track);
    } catch (error) {
      throw XmaxError.from(error);
    }
  }

  /// 校验并原地更新采集规格；原生设置成功后才更新轨道信息。
  ///
  /// - [videoFormat]：符合当前模型约束的采集规格。
  Future<void> updateVideoFormat(
    RealtimeVideoFormat videoFormat,
  ) async {
    final track = _activeTrack;

    if (track == null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Camera preview is not started',
      );
    }

    final format = _resolveVideoFormat(videoFormat);

    if (format == track.videoFormat) return;

    await _rtcManager.updateVideoCapture(
      width: format.width,
      height: format.height,
      frameRate: format.fps,
    );
    updateRealtimeVideoTrack(track: track, videoFormat: format);
  }

  /// 依据当前模型校验并解析摄像头采集规格。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  ///
  /// 返回包含有效尺寸、帧率及编码配置的视频规格。
  RealtimeVideoFormat _resolveVideoFormat(
    RealtimeVideoFormat videoFormat,
  ) {
    videoFormat.validate();

    final size = _mediaService.resolveMediaSize(
      Size(videoFormat.width.toDouble(), videoFormat.height.toDouble()),
      source: RealtimeMediaSource.camera,
    );
    final format = videoFormat.resized(
      width: size.width.toInt(),
      height: size.height.toInt(),
    );

    format.validate();

    return format;
  }
}
