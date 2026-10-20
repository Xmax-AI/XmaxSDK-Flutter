//
//  MediaController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../foundation/errors/XmaxError.dart';
import '../foundation/logging/XmaxLogger.dart';
import '../foundation/media/camera/CameraPosition.dart';
import '../foundation/rtc/RtcManaging.dart';
import '../service/realtime/RealtimeMediaStream.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../service/realtime/RealtimeVideoTrack.dart';
import 'camera/CameraController.dart';
import 'interaction/InteractionController.dart';
import 'interaction/InteractionFrame.dart';
import 'MediaControlling.dart';

/// 管理本地摄像头、媒体资源所有权和交互输入的生命周期。
final class MediaController implements MediaControlling {

  /// 创建本地媒体控制器，并将触点采样连接到指定处理入口。
  ///
  /// - [rtcManager]：采集和传输入口。
  /// - [cameraController]：摄像头组件；默认基于同一 RTC 管理器创建。
  /// - [interactionListener]：接收任务标识及归一化触点的处理函数。
  MediaController({
    required RtcManaging rtcManager,
    CameraController? cameraController,
    required InteractionListener interactionListener,
  }) : _rtcManager = rtcManager,
       _cameraController =
           cameraController ?? CameraController(rtcManager: rtcManager),
       _interactionController = InteractionController(
         listener: interactionListener,
       );

  /// RTC 采集、房间及传输操作入口。
  final RtcManaging _rtcManager;

  /// 摄像头轨道创建、预览就绪及切换组件。
  final CameraController _cameraController;

  /// 当前生成任务的触点采样和坐标处理组件。
  final InteractionController _interactionController;

  /// 当前是否已创建本地媒体流。
  bool _hasActiveSource = false;

  /// 是否正在执行不能并发的本地媒体操作。
  bool _operationInProgress = false;

  /// 当前本地媒体操作结束时的通知。
  Completer<void>? _operationCompletion;

  /// 正在进行的本地媒体停止任务。
  Future<void>? _stopFuture;

  /// 当前有效的本地视频轨道；尚未创建或已停止时为空。
  @override
  RealtimeVideoTrack? get currentTrack =>
      _hasActiveSource ? _cameraController.currentTrack : null;

  /// 当前本地轨道的视频规格；尚未创建时为空。
  @override
  RealtimeVideoFormat? get currentVideoFormat => currentTrack?.videoFormat;

  /// 本地媒体是否包含可播放音频；摄像头来源为 false。
  @override
  bool get hasAudio => false;

  // 没有本地文件播放器时，读取固定的预览音量。

  /// 本地媒体预览音量；摄像头没有音频播放器，固定为 0.45。
  @override
  Future<double> get localAudioVolume async => 0.45;

  /// 设置本地摄像头首帧就绪的内部通知。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setCameraPreviewReadyListener(
    RealtimeCameraPreviewReadyListener? listener,
  ) {
    _cameraController.setPreviewReadyListener(listener);
  }

  /// 创建本地摄像头流并开始预览，就绪后调用预览监听器。
  ///
  /// 详细说明见 [MediaControlling.createLocalCameraStream]。
  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    required RealtimeVideoFormat videoFormat,
    required CameraPosition position,
  }) async {
    if (_hasActiveSource) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            'Stop the current local media stream before creating another one',
      );
    }

    _ensureNoOperation();

    // 等待 RTC 初始化前先标记媒体操作已开始，防止重复创建。
    _operationInProgress = true;

    final completion = _operationCompletion = Completer<void>();

    _hasActiveSource = true;

    try {
      await _rtcManager.initialize();

      return await _cameraController.createLocalCameraStream(
        videoFormat: videoFormat,
        position: position,
      );
    } catch (error) {
      _hasActiveSource = false;
      await _releaseEngine();
      throw XmaxError.from(error);
    } finally {
      _operationInProgress = false;
      completion.complete();
    }
  }

  /// 停止本地摄像头流并释放采集资源；公开管理器仅允许在实时连接断开后调用。
  @override
  Future<void> stopLocalCameraStream() async {
    if (!_hasActiveSource) {
      return;
    }

    await _stopCurrentSource();
  }

  /// 停止当前本地媒体来源并释放其 RTC 引擎使用权。
  @override
  Future<void> stopLocalStream() => stopLocalCameraStream();

  /// 共享正在进行的本地媒体停止操作。
  Future<void> _stopCurrentSource() {
    final active = _stopFuture;

    if (active != null) return active;

    final future = _performStopCurrentSource();

    _stopFuture = future;

    return future.whenComplete(() => _stopFuture = null);
  }

  /// 等待当前媒体操作结束，再停止采集和释放资源。
  Future<void> _performStopCurrentSource() async {
    // 先等待正在进行的采集或切换操作完成，再释放共用的 RTC 引擎。
    await _operationCompletion?.future;
    _operationInProgress = true;

    try {
      try {
        await _cameraController.stopLocalCameraStream();
      } catch (error) {
        _logCleanupFailure('停止相机采集失败 (Failed to Stop Camera Capture)', error);
      }

      await _releaseEngine();
    } finally {
      _hasActiveSource = false;
      _operationInProgress = false;
    }
  }

  /// 释放当前媒体持有的 RTC 引擎资源。
  Future<void> _releaseEngine() async {
    try {
      await _rtcManager.destroy();
    } catch (error) {
      _logCleanupFailure('释放 RTC 引擎失败 (Failed to Release RTC Engine)', error);
    }
  }

  /// 记录资源释放错误，不替换当前业务错误。
  ///
  /// - [title]：日志组的标题。
  /// - [error]：本次操作的错误。
  void _logCleanupFailure(
    String title,
    Object error,
  ) {
    try {
      XmaxLogger.error(
        category: XmaxLoggerCategory.realtime,
        message: '$title\n└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
      );
    } catch (_) {
      // 记录日志失败不能中断资源清理。
    }
  }

  /// 切换前后置摄像头，返回更新后的本地媒体流。
  ///
  /// 返回切换后的本地摄像头媒体流。
  @override
  Future<RealtimeMediaStream> switchCamera() async {
    if (!_hasActiveSource) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Local camera preview is not started',
      );
    }

    _ensureNoOperation();
    _operationInProgress = true;

    final completion = _operationCompletion = Completer<void>();

    try {
      return await _cameraController.switchCamera();
    } finally {
      _operationInProgress = false;
      completion.complete();
    }
  }

  /// 校验并设置本地媒体音量；摄像头没有音频播放器，合法设置不改变默认读取值 0.45。
  ///
  /// - [volume]：0～1 范围内的有限音量值。
  @override
  Future<void> setLocalAudioVolume(
    double volume,
  ) async {
    // 摄像头没有本地播放器，因此这里只校验音量，不调整播放音量。
  }

  /// 检查媒体流是否属于当前本地媒体生命周期。
  ///
  /// 详细说明见 [MediaControlling.owns]。
  @override
  bool owns(
    RealtimeMediaStream stream,
  ) {
    final track = stream.videoTrack;

    return track != null && identical(track, currentTrack);
  }

  /// 为当前生成任务启用交互输入，并清除旧任务的待发采样。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  @override
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  }) {
    _interactionController.startInteraction(
      taskID: taskID,
      videoFormat: videoFormat,
    );
  }

  /// 停止交互输入，并使尚未提交的采样失效。
  @override
  void stopInteraction() {
    _interactionController.stopInteraction();
  }

  /// 提交当前视图触点采样；没有有效生成任务时忽略。
  ///
  /// - [frame]：一次视图触点采样。
  @override
  void submitInteraction(
    InteractionFrame frame,
  ) {
    _interactionController.submitInteraction(frame);
  }

  /// 检查当前没有相互冲突的本地媒体操作。
  void _ensureNoOperation() {
    if (_operationInProgress) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'A local media operation is already in progress',
      );
    }
  }
}
