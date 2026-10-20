//
//  StreamController.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:ui';

import '../foundation/errors/XmaxError.dart';
import '../foundation/logging/XmaxLogger.dart';
import '../foundation/rtc/RtcEventListener.dart';
import '../foundation/rtc/RtcManaging.dart';
import '../foundation/rtc/RtcModels.dart';
import '../foundation/rtc/VideoStatistics.dart';
import '../service/realtime/RealtimeContext.dart';
import '../service/realtime/RealtimeError.dart';
import '../service/realtime/RealtimeNetworkQuality.dart';
import '../service/realtime/RealtimePerformanceAlarm.dart';
import '../service/realtime/RealtimePoint.dart';
import '../service/realtime/RealtimeSession.dart';
import '../service/realtime/RealtimeVideoFormat.dart';
import '../service/media/MediaService.dart';
import '../service/media/MediaServicing.dart';
import 'quality/QualityVideoFormat.dart';
import 'encoding/EncodingController.dart';
import 'encoding/EncodingControlling.dart';
import 'quality/QualityController.dart';
import 'quality/QualityControlling.dart';
import 'room/RoomController.dart';
import 'room/RoomControlling.dart';
import 'StreamControlling.dart';

/// 接收当前结果流绑定变化的内部回调；清理绑定时为 null。
///
/// - [stream]：待处理的远端 RTC 流。
typedef RemoteStreamListener =
    void Function(
      RemoteStream? stream,
    );

/// 接收指定结果流首帧就绪事件的内部回调。
///
/// - [stream]：待处理的远端 RTC 流。
typedef RemoteFrameRenderedListener =
    void Function(
      RemoteStream stream,
    );

/// 协调 RTC 发布订阅、生成信令、结果确认和自适应传输质量。
final class StreamController implements StreamControlling {

  /// 创建传输控制器，并注册 RTC 事件处理。
  ///
  /// - [rtcManager]：采集、房间与传输入口。
  /// - [roomController]：信令组件；默认基于同一 RTC 管理器创建。
  /// - [encodingController]：编码组件；默认基于同一 RTC 管理器创建。
  /// - [qualityController]：质量策略组件；默认创建独立策略。
  /// - [mediaService]：尺寸解析服务；默认使用 [MediaService] 的模型配置。
  /// - [errorListener]：远端连接或生成失败通知。
  /// - [localMediaErrorListener]：未连接时的本地媒体失败通知；默认复用 [errorListener]。
  /// - [remoteStreamListener]：结果流绑定变化通知。
  /// - [remoteFrameRenderedListener]：结果流首帧渲染通知。
  /// - [remoteFrameReadyListener]：结果流首帧解码通知。
  /// - [generationTimeout]：生成信令与结果确认的等待时限，默认 15 秒。
  ///
  /// 当前控制器负责接收此 RTC 管理器的事件。
  StreamController({
    required RtcManaging rtcManager,
    RoomControlling? roomController,
    EncodingControlling? encodingController,
    QualityControlling? qualityController,
    MediaServicing? mediaService,
    RealtimeErrorListener? errorListener,
    RealtimeErrorListener? localMediaErrorListener,
    RemoteStreamListener? remoteStreamListener,
    RemoteFrameRenderedListener? remoteFrameRenderedListener,
    RemoteFrameRenderedListener? remoteFrameReadyListener,
    this.generationTimeout = const Duration(seconds: 15),
  }) : _rtcManager = rtcManager,
       _roomController =
           roomController ?? RoomController(rtcManager: rtcManager),
       _encodingController =
           encodingController ?? EncodingController(rtcManager: rtcManager),
       _qualityController = qualityController ?? QualityController(),
       _mediaService = mediaService ?? MediaService(),
       _errorListener = errorListener,
       _localMediaErrorListener = localMediaErrorListener,
       _remoteStreamListener = remoteStreamListener,
       _remoteFrameReadyListener = remoteFrameReadyListener,
       _remoteFrameRenderedListener = remoteFrameRenderedListener {
    rtcManager.setEventListener(
      RtcEventListener(
        onRemoteVideoPublished: _onRemoteVideoPublished,
        onFirstRemoteVideoFrameRendered: _onFirstRemoteVideoFrameRendered,
        onFirstRemoteVideoFrameDecoded: _onFirstRemoteVideoFrameDecoded,
        onRemoteAudioPublished: _onRemoteAudioPublished,
        onUplinkVideoStatistics: (value) {
          if (_localVideoPublished) _uplinkStatisticsListener?.call(value);
        },
        onDownlinkVideoStatistics: (value) {
          if (value != null && _activeRemoteStream?.userID == value.userID) {
            _downlinkStatisticsListener?.call(value);
          }
        },
        onError: _onError,
        onNetworkQuality: _networkQualityDidChange,
        onPerformanceAlarm: _qualityController.emitPerformanceAlarm,
      ),
    );
  }

  /// RTC 采集、房间及传输操作入口。
  final RtcManaging _rtcManager;

  /// 房间身份、心跳和业务信令组件。
  final RoomControlling _roomController;

  /// RTC 视频编码配置组件。
  final EncodingControlling _encodingController;

  /// 上下行网络质量策略组件。
  final QualityControlling _qualityController;

  /// 媒体、生成及回传尺寸解析服务。
  final MediaServicing _mediaService;

  /// 网络质量采样使用的单调时钟。
  final _qualityClock = Stopwatch()..start();

  /// 生成结果的回传宽高，单位为像素。
  Size? _targetSize;

  /// 正在应用的网络质量调档任务。
  Future<void>? _adaptation;

  /// 当前任务是否允许自动调整上下行质量。
  bool _canAdapt = false;

  /// 正在等待或发送的生成条件更新数量。
  int _conditionUpdates = 0;

  /// 网络质量配置所属连接的版本号。
  int _qualityVersion = 0;

  /// 生成结果的回传宽高，单位为像素。
  @override
  Size? get targetSize => _targetSize;

  /// 读取模型的有效档位历史，准备独立上下行策略并应用初始传输规格。
  ///
  /// 详细说明见 [StreamControlling.prepareQuality]。
  @override
  Future<void> prepareQuality({
    required RealtimeVideoFormat baseline,
    required String model,
  }) async {
    final version = ++_qualityVersion;

    await _qualityController.prepareQuality(baseline: baseline, model: model);
    if (version != _qualityVersion) return;

    _targetSize = _resolveTargetSize(
      baseline,
      _qualityController.downlinkLevel,
    );
    await _encodingController.configure(
      _qualityController.uplinkFormat ?? baseline,
    );
  }

  /// 按下行档位计算限制内的对齐回传尺寸。
  ///
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [level]：目标质量档位，范围为 1～5。
  ///
  /// 返回当前下行档位限制内的对齐回传尺寸。
  Size _resolveTargetSize(
    RealtimeVideoFormat baseline,
    int level,
  ) => _mediaService.resolveTargetSize(
    Size(baseline.width.toDouble(), baseline.height.toDouble()),
    maximumSize: QualityVideoFormat.downlinkMaximumSize(baseline, level),
  );

  /// 分发网络质量事件，并在可调档期间收集上下行连续样本。
  ///
  /// - [quality]：同一次采样得到的上下行网络质量。
  void _networkQualityDidChange(
    RealtimeNetworkQuality quality,
  ) {
    _qualityController.emitNetworkQuality(quality);
    if (_conditionUpdates > 0 ||
        !_canAdapt ||
        _generationTaskID == null ||
        _generationCompleter != null ||
        _adaptation != null) {
      _qualityController.resetQualitySamples();

      return;
    }

    final baseline = _qualityController.baseline;

    if (baseline == null) return;

    final changes = _qualityController.proposeQuality(
      quality,
      _qualityClock.elapsedMicroseconds / 1e6,
    );

    if (changes.$1 == null && changes.$2 == null) return;

    final taskID = _generationTaskID!;
    final version = _qualityVersion;
    final future = _applyQuality(changes, baseline, taskID, version);

    _adaptation = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_adaptation, future)) _adaptation = null;
      }),
    );
  }

  /// 独立应用上下行候选档位，仅记录成功应用的结果。
  ///
  /// - [changes]：本次建议的上行和下行档位；空值表示保持不变。
  /// - [baseline]：不随网络调档改变的媒体尺寸、帧率和编码配置。
  /// - [taskID]：当前生成任务标识。
  /// - [version]：当前异步操作的版本号。
  Future<void> _applyQuality(
    (int?, int?) changes,
    RealtimeVideoFormat baseline,
    String taskID,
    int version,
  ) async {
    bool current() =>
        version == _qualityVersion && taskID == _generationTaskID && _canAdapt;

    for (final downlink in [false, true]) {
      final level = downlink ? changes.$2 : changes.$1;

      if (level == null || !current()) continue;

      var success = false;

      try {
        if (downlink) {
          final target = _resolveTargetSize(baseline, level);

          await changeTargetSize(
            taskID: taskID,
            targetSize: target,
            ensureActive: () {
              if (!current()) {
                throw const XmaxError(
                  code: XmaxErrorCode.cancelled,
                  message: 'Quality adjustment cancelled',
                );
              }
            },
          );
          if (version == _qualityVersion) {
            _targetSize = target;
            success = true;
          }
        } else {
          await _encodingController.configure(
            QualityVideoFormat.resolve(baseline, level, downlink: false),
          );
          success = version == _qualityVersion;
        }
      } catch (error) {
        if (current()) {
          XmaxLogger.warn(
            category: XmaxLoggerCategory.stream,
            message: '网络档位调整失败 (Quality Adjustment Failed)\n└─ $error',
          );
        }
      }
      // 原生音量设置即使在生成停止后才完成，也只属于当前连接，不能沿用到新连接。
      if (version == _qualityVersion) {
        await _qualityController.completeQuality(
          level,
          downlink: downlink,
          success: success,
          now: _qualityClock.elapsedMicroseconds / 1e6,
        );
      }
    }
  }

  /// 接收远端连接或生成运行错误的监听器。
  final RealtimeErrorListener? _errorListener;

  /// 尚未连接远端时，本地媒体发生错误的回调。
  final RealtimeErrorListener? _localMediaErrorListener;

  /// 生成结果流发生变化时的回调。
  final RemoteStreamListener? _remoteStreamListener;

  /// 结果流首帧渲染完成时的回调。
  final RemoteFrameRenderedListener? _remoteFrameRenderedListener;

  /// 结果流首帧解码完成时的回调。
  final RemoteFrameRenderedListener? _remoteFrameReadyListener;

  /// 启动信令及结果流确认允许等待的总时限。
  final Duration generationTimeout;

  /// 云端分配的 RTC 房间标识。
  String _roomID = '';

  /// 远端连接生命周期的版本号。
  int _connectionRevision = 0;

  /// 预期生成结果流的 RTC 用户账号。
  String _botName = '';

  /// 当前房间是否已成功发布本地摄像头视频。
  bool _localVideoPublished = false;

  /// 当前已成功订阅的结果视频流标识集合。
  final Set<String> _remoteVideoSubscriptions = <String>{};

  /// 按房间、账号和流标识保留的首帧渲染记录。
  final Set<(String, String, String)> _renderedRemoteStreams = {};

  /// 按房间、账号和流标识保留的首帧解码记录。
  final Set<(String, String, String)> _decodedRemoteStreams = {};

  /// 预期结果用户已发布的音频流映射。
  final Map<String, String> _publishedRemoteAudioStreams = <String, String>{};

  /// 当前任务已确认的远端结果流。
  RemoteStream? _activeRemoteStream;

  /// 当前成功订阅的远端音频流标识。
  String? _subscribedRemoteAudioStreamID;

  /// 正在执行的远端音频激活任务。
  Future<void>? _audioActivation;

  /// 当前结果流是否已允许播放音频。
  bool _remoteAudioEnabled = false;

  /// 最近一次成功设置的远端音量百分比。
  int _remoteAudioVolumePercentage = 100;

  /// 远端音频订阅的版本号，用于忽略旧订阅结果。
  int _audioSubscriptionVersion = 0;

  /// 当前处于启动或生成阶段的任务标识。
  String? _generationTaskID;

  /// 用于通知生成结果流已确认或失败的完成器。
  Completer<void>? _generationCompleter;

  /// 当前生成结果确认的超时计时器。
  Timer? _generationTimer;

  /// 当前任务的启动信令是否已发送成功。
  bool _startSignalSent = false;

  /// 预期结果用户已发布的视频流映射。
  final _publishedVideoStreams = <String, RemoteStream>{};

  /// 正在订阅的结果视频流标识集合。
  final _subscribingVideo = <String>{};

  /// 本地视频发布期间的上行统计监听器。
  UplinkVideoStatisticsListener? _uplinkStatisticsListener;

  /// 当前结果流的下行视频统计监听器。
  DownlinkVideoStatisticsListener? _downlinkStatisticsListener;

  /// 设置上行视频统计监听器；停止发布或断开连接时通知 null。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setUplinkVideoStatisticsListener(
    UplinkVideoStatisticsListener? listener,
  ) => _uplinkStatisticsListener = listener;

  /// 设置当前结果流的下行视频统计监听器；结果流清理时通知 null。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setDownlinkVideoStatisticsListener(
    DownlinkVideoStatisticsListener? listener,
  ) => _downlinkStatisticsListener = listener;

  /// 是否有正在启动或运行的生成任务。
  @override
  bool get hasGenerationTask => _generationTaskID != null;

  /// 远端音频播放音量，范围为 0～1，精度为 0.01。
  @override
  double get remoteAudioVolume => _remoteAudioVolumePercentage / 100;

  /// 解析视频码率预算并应用 RTC 编码配置。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  @override
  Future<void> setVideoEncoderConfig(
    RealtimeVideoFormat videoFormat,
  ) => _encodingController.configure(videoFormat);

  /// 设置上下行网络质量监听器，不替换 SDK 内部自适应策略。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setNetworkQualityListener(
    RealtimeNetworkQualityListener? listener,
  ) {
    _qualityController.setNetworkQualityListener(listener);
  }

  /// 设置性能受限及恢复事件的监听器。
  ///
  /// - [listener]：事件回调；传入 null 可取消监听。
  @override
  void setPerformanceAlarmListener(
    RealtimePerformanceAlarmListener? listener,
  ) {
    _qualityController.setPerformanceAlarmListener(listener);
  }

  /// 设置远端音频音量，范围为 0～1，精度为 0.01；RTC 调用失败时保留上次成功值。
  ///
  /// - [volume]：0～1 范围内的有限音量值。
  @override
  Future<void> setRemoteAudioVolume(
    double volume,
  ) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Audio volume must be between 0 and 1',
      );
    }

    final rtcVolume = (volume * 100).round();
    final streamID = _subscribedRemoteAudioStreamID;

    if (streamID != null) {
      await _rtcManager.setRemoteAudioVolume(
        volume: rtcVolume,
        streamID: streamID,
      );
    }

    _remoteAudioVolumePercentage = rtcVolume;
  }

  /// 在结果流确认后应用音量并订阅远端音频，同时允许网络自适应。
  @override
  Future<void> activateRemoteAudio() async {
    final stream = _activeRemoteStream;

    if (_generationTaskID == null || stream == null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Remote generation audio stream is unavailable',
      );
    }

    _remoteAudioEnabled = true;
    _canAdapt = true;
    // 远端音频可能晚于视频发布，收到音频发布通知后再补充订阅。
    final streamID = _publishedRemoteAudioStreams[stream.userID];

    if (streamID == null) return;

    if (_subscribedRemoteAudioStreamID == streamID) return;

    final activeOperation = _audioActivation;

    if (activeOperation != null) return activeOperation;

    final operation = _performActivateRemoteAudio(stream, streamID);

    _audioActivation = operation;

    try {
      await operation;
    } finally {
      if (identical(_audioActivation, operation)) {
        _audioActivation = null;
      }
    }
  }

  /// 按当前结果流和音量完成音频订阅，并取消过期订阅。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  /// - [streamID]：需要发布、订阅或控制的媒体流标识。
  Future<void> _performActivateRemoteAudio(
    RemoteStream stream,
    String streamID,
  ) async {
    final version = _audioSubscriptionVersion;
    final initialVolume = _remoteAudioVolumePercentage;

    await _rtcManager.setRemoteAudioVolume(
      volume: initialVolume,
      streamID: streamID,
    );
    _ensureAudioStreamCurrent(stream, streamID, version);

    await _rtcManager.subscribeRemoteAudio(streamID: streamID, subscribe: true);
    if (!_isAudioStreamCurrent(stream, streamID, version)) {
      await _safe(
        '取消过期 RTC 远端音频订阅失败 '
        '(Failed to Unsubscribe from Stale RTC Remote Audio)',
        () => _rtcManager.subscribeRemoteAudio(
          streamID: streamID,
          subscribe: false,
        ),
      );
      _ensureAudioStreamCurrent(stream, streamID, version);
    }

    _subscribedRemoteAudioStreamID = streamID;
    if (initialVolume != _remoteAudioVolumePercentage) {
      await _rtcManager.setRemoteAudioVolume(
        volume: _remoteAudioVolumePercentage,
        streamID: streamID,
      );
    }
  }

  /// 使用已有会话凭证加入 RTC 房间，并发布本地视频。
  ///
  /// 详细说明见 [StreamControlling.connect]。
  @override
  Future<void> connect({
    required RealtimeSessionConnection connection,
    required void Function() ensureActive,
  }) async {
    // 加入房间尚未完成时，也可能收到已有远端流的发布通知。
    _connectionRevision += 1;
    _renderedRemoteStreams.clear();
    _decodedRemoteStreams.clear();
    _roomID = connection.roomID.trim();
    _publishedVideoStreams.clear();
    _subscribingVideo.clear();
    _botName = connection.botName?.trim() ?? '';

    try {
      await _roomController.join(
        connection: connection,
        ensureActive: ensureActive,
      );

      ensureActive();
      await _rtcManager.publishLocalVideo(publish: true);
      _localVideoPublished = true;
      _uplinkStatisticsListener?.call(null);
    } catch (_) {
      _roomID = '';
      _botName = '';
      _publishedRemoteAudioStreams.clear();
      _renderedRemoteStreams.clear();
      _decodedRemoteStreams.clear();
      rethrow;
    }
  }

  /// 结束当前生成并断开远端连接，保留本地摄像头预览。
  @override
  Future<void> disconnect() async {
    _canAdapt = false;
    _qualityVersion++;
    await _adaptation;
    _qualityController.resetQuality();
    _targetSize = null;
    _connectionRevision += 1;
    // 变更 RTC 订阅前，先取消生成结果流的等待任务。
    await _clearGeneration(notifyRemote: true);

    for (final streamID in _remoteVideoSubscriptions.toList()) {
      await _safe(
        '取消订阅 RTC 远端视频失败 (Failed to Unsubscribe from RTC Remote Video)',
        () => _rtcManager.subscribeRemoteVideo(
          streamID: streamID,
          subscribe: false,
        ),
      );
    }

    if (_localVideoPublished) {
      await _safe(
        '取消发布 RTC 本地视频失败 (Failed to Unpublish RTC Local Video)',
        () => _rtcManager.publishLocalVideo(publish: false),
      );
    }

    _remoteVideoSubscriptions.clear();
    _renderedRemoteStreams.clear();
    _decodedRemoteStreams.clear();
    _publishedRemoteAudioStreams.clear();
    _localVideoPublished = false;
    _uplinkStatisticsListener?.call(null);
    _downlinkStatisticsListener?.call(null);
    _publishedVideoStreams.clear();
    _subscribingVideo.clear();
    _roomID = '';
    _botName = '';

    await _roomController.leave();
  }

  /// 发送生成启动信令，并返回可取消的结果流等待任务。
  ///
  /// 详细说明见 [StreamControlling.beginGeneration]。
  @override
  Future<GenerationStartConfirmation> beginGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) async {
    if (taskID.trim().isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Realtime generation task ID cannot be empty',
      );
    }

    if (_roomID.isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'RTC room is not configured',
      );
    }

    if (_generationTaskID != null) {
      throw const XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Realtime generation is already active',
      );
    }

    // 启动信令提交后，才开始选择匹配的结果流。
    final completer = Completer<void>();
    // 启动信令发出后可能立即收到取消操作，
    // 因此先注册异常处理，再将结果流等待任务交给调用方。
    completer.future.ignore();
    _generationTaskID = taskID;
    _generationCompleter = completer;
    _startSignalSent = false;
    _generationTimer = Timer(generationTimeout, () {
      // 记录生成启动和结果流确认信息，不记录提示词或访问凭证。
      XmaxLogger.warn(
        category: XmaxLoggerCategory.stream,
        message:
            '生成确认超时 (Generation Confirmation Timed Out)\n'
            '├─ ${XmaxLogger.localized('taskID：', 'taskID: ')}$taskID\n'
            '├─ ${XmaxLogger.localized('视频订阅数：', 'Video Subscriptions: ')}${_remoteVideoSubscriptions.length}\n'
            '└─ ${XmaxLogger.localized('目标视频已发布：', 'Expected Video Published: ')}${_publishedVideoStreams.isNotEmpty}',
      );
      _rejectGeneration(
        const XmaxError(
          code: XmaxErrorCode.timeout,
          message: 'Realtime generation start timed out',
        ),
      );
    });

    try {
      // 信令排队和结果流发布共用同一超时时限。
      // 取消操作也要结束仍在等待 RTC 发送完成的任务。
      await Future.any<void>([
        _roomController.startGeneration(
          taskID: taskID,
          videoFormat: videoFormat,
          context: context,
          targetSize: targetSize,
          faceRestoration: faceRestoration,
        ),
        completer.future,
      ]);
      if (_generationTaskID == taskID &&
          identical(_generationCompleter, completer)) {
        _startSignalSent = true;
        _confirmPublishedRemoteStream();
      }

      return GenerationStartConfirmation(
        value: completer.future,
        onCancel: () {
          if (_generationTaskID == taskID &&
              identical(_generationCompleter, completer)) {
            _rejectGeneration(
              const XmaxError(
                code: XmaxErrorCode.cancelled,
                message: 'Realtime generation start cancelled',
              ),
            );
          }
        },
      );
    } catch (error) {
      // 本次调用会将错误返回给调用方，先移除完成器，
      // 避免清理时再次产生无人接收的取消错误。
      if (identical(_generationCompleter, completer)) {
        _generationTimer?.cancel();
        _generationTimer = null;
        _generationCompleter = null;
      }

      // 通知服务端停止任务，因为生成请求可能已经送达。
      await _clearGeneration(notifyRemote: true);
      rethrow;
    }
  }

  /// 等待当前调档完成后更新当前生成条件，使用最新回传尺寸。
  ///
  /// 详细说明见 [StreamControlling.updateGeneration]。
  @override
  Future<void> updateGeneration({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext context,
    Size? targetSize,
    bool faceRestoration = false,
  }) async {
    _conditionUpdates++;

    final revision = _connectionRevision;

    try {
      await _adaptation;
      if (revision != _connectionRevision || _generationTaskID != taskID) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Generation condition update cancelled',
        );
      }

      await _roomController.changeGenerationCondition(
        taskID: taskID,
        videoFormat: videoFormat,
        context: context,
        targetSize: _targetSize ?? targetSize,
        faceRestoration: faceRestoration,
      );
    } finally {
      _conditionUpdates--;
    }
  }

  /// 提交当前生成任务的回传尺寸和下行码率预算。
  ///
  /// 详细说明见 [StreamControlling.changeTargetSize]。
  @override
  Future<void> changeTargetSize({
    required String taskID,
    required Size targetSize,
    required void Function() ensureActive,
  }) => _roomController.changeTargetSize(
    taskID: taskID,
    targetSize: targetSize,
    ensureActive: ensureActive,
  );

  /// 停止当前生成任务和交互输入，保留 RTC 连接。
  ///
  /// - [taskID]：当前生成任务标识。
  @override
  Future<void> stopGeneration({
    required String taskID,
  }) async {
    final stoppedTaskID = _generationTaskID;

    if (stoppedTaskID == null ||
        (taskID.isNotEmpty && taskID != stoppedTaskID)) {
      return;
    }

    await _clearGeneration(notifyRemote: true);
    await _roomController.stopGeneration(taskID: stoppedTaskID);
  }

  /// 提交当前生成任务的归一化交互轨迹；任务标识或触点列表为空时不发送。
  ///
  /// 详细说明见 [StreamControlling.sendTracks]。
  @override
  Future<void> sendTracks({
    required String taskID,
    required List<RealtimePoint> points,
  }) => _roomController.sendTracks(taskID: taskID, points: points);

  /// 维护预期用户的视频发布状态及订阅，取消发布时清理结果绑定。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  /// - [published]：远端流是否处于已发布状态。
  void _onRemoteVideoPublished(
    RemoteStream stream,
    bool published,
  ) {
    if (!_isExpectedRemote(stream)) {
      return;
    }

    if (published) {
      _publishedVideoStreams[stream.streamID] = stream;
      if (!_remoteVideoSubscriptions.contains(stream.streamID) &&
          _subscribingVideo.add(stream.streamID)) {
        unawaited(_subscribeRemoteVideo(stream));
      }
    } else {
      _publishedVideoStreams.remove(stream.streamID);
      _remoteVideoSubscriptions.remove(stream.streamID);
      _decodedRemoteStreams.remove((
        stream.roomID,
        stream.userID,
        stream.streamID,
      ));
      _renderedRemoteStreams.remove((
        stream.roomID,
        stream.userID,
        stream.streamID,
      ));
      if (_activeRemoteStream?.streamID == stream.streamID) {
        _activeRemoteStream = null;
        unawaited(_deactivateRemoteAudio());
        _clearRemoteStream();
      }
    }
  }

  /// 记录结果流已完成首帧解码，并通知等待方。
  ///
  /// - [stream]：完成首帧解码的远端流。
  void _onFirstRemoteVideoFrameDecoded(
    RemoteStream stream,
  ) {
    if (!_isExpectedRemote(stream)) return;

    _decodedRemoteStreams.add((stream.roomID, stream.userID, stream.streamID));

    final active = _activeRemoteStream;

    if (active != null &&
        active.roomID == stream.roomID &&
        active.userID == stream.userID &&
        active.streamID == stream.streamID) {
      _remoteFrameReadyListener?.call(stream);
    }
  }

  /// 记录结果流已完成首帧渲染，并通知视图显示画面。
  ///
  /// - [stream]：完成首帧渲染的远端流。
  void _onFirstRemoteVideoFrameRendered(
    RemoteStream stream,
  ) {
    if (!_isExpectedRemote(stream)) return;

    // RTC 按订阅通知首帧，而不是按生成任务通知。
    // 取消发布或断开连接前保留首帧状态，包括选中结果流之前收到的首帧。
    _renderedRemoteStreams.add((stream.roomID, stream.userID, stream.streamID));

    final active = _activeRemoteStream;

    if (active == null ||
        active.roomID != stream.roomID ||
        active.userID != stream.userID ||
        active.streamID != stream.streamID) {
      return;
    }

    _remoteFrameRenderedListener?.call(stream);
  }

  /// 维护结果用户的音频发布状态并按需订阅。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  /// - [published]：远端流是否处于已发布状态。
  void _onRemoteAudioPublished(
    RemoteStream stream,
    bool published,
  ) {
    if (!_isExpectedRemote(stream)) return;

    if (published) {
      _publishedRemoteAudioStreams[stream.userID] = stream.streamID;
      if (_activeRemoteStream?.userID == stream.userID) {
        unawaited(_activatePublishedAudio());
      }

      return;
    }

    if (_publishedRemoteAudioStreams[stream.userID] != stream.streamID) return;

    _publishedRemoteAudioStreams.remove(stream.userID);
    if (_activeRemoteStream?.userID == stream.userID) {
      unawaited(_deactivateRemoteAudio());
    }
  }

  /// 仅在当前结果音频已启用时激活新发布的音频。
  Future<void> _activatePublishedAudio() async {
    if (!_remoteAudioEnabled) return;

    final revision = _audioSubscriptionVersion;
    final connectionRevision = _connectionRevision;

    try {
      await activateRemoteAudio();
    } catch (error) {
      if (revision != _audioSubscriptionVersion ||
          connectionRevision != _connectionRevision) {
        return;
      }

      final xmaxError = XmaxError.from(error);

      if (xmaxError.code != XmaxErrorCode.cancelled) {
        _errorListener?.call(xmaxError);
      }
    }
  }

  /// 订阅预期用户视频，过滤已失效连接的完成结果。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  Future<void> _subscribeRemoteVideo(
    RemoteStream stream,
  ) async {
    final revision = _connectionRevision;

    try {
      await _rtcManager.subscribeRemoteVideo(
        streamID: stream.streamID,
        subscribe: true,
      );
      if (revision != _connectionRevision ||
          !_publishedVideoStreams.containsKey(stream.streamID)) {
        return;
      }

      _remoteVideoSubscriptions.add(stream.streamID);
      _subscribingVideo.remove(stream.streamID);
      _confirmPublishedRemoteStream();
    } catch (error) {
      // 旧房间迟到的订阅错误不能移除新房间中同标识的订阅，也不能使新生成请求失败。
      if (revision != _connectionRevision) return;

      _subscribingVideo.remove(stream.streamID);
      _remoteVideoSubscriptions.remove(stream.streamID);

      final xmaxError = XmaxError.from(error);

      if (!_rejectGeneration(xmaxError)) {
        _errorListener?.call(xmaxError);
      }
    }
  }

  /// 启动信令发送成功且预期视频已订阅后确认结果流。
  void _confirmPublishedRemoteStream() {
    final taskID = _generationTaskID;
    final completer = _generationCompleter;

    if (!_startSignalSent ||
        taskID == null ||
        completer == null ||
        completer.isCompleted) {
      return;
    }

    final stream = _publishedVideoStreams.values
        .where(
          (stream) =>
              _isExpectedRemote(stream) &&
              _remoteVideoSubscriptions.contains(stream.streamID),
        )
        .firstOrNull;

    if (stream == null) return;

    XmaxLogger.debug(
      category: XmaxLoggerCategory.stream,
      message:
          '生成结果流已确认 (Generation Stream Confirmed)\n└─ ${XmaxLogger.localized('taskID：', 'taskID: ')}$taskID',
    );
    _activeRemoteStream = stream;
    _remoteStreamListener?.call(stream);
    if (_decodedRemoteStreams.contains((
      stream.roomID,
      stream.userID,
      stream.streamID,
    ))) {
      _remoteFrameReadyListener?.call(stream);
    }

    if (_renderedRemoteStreams.contains((
      stream.roomID,
      stream.userID,
      stream.streamID,
    ))) {
      _remoteFrameRenderedListener?.call(stream);
    }

    _generationTimer?.cancel();
    _generationTimer = null;
    _generationCompleter = null;
    completer.complete();
  }

  /// 优先结束正在等待的生成确认，否则转交当前生命周期的错误监听。
  ///
  /// - [error]：本次操作的错误。
  void _onError(
    Object error,
  ) {
    final xmaxError = XmaxError.from(error);

    if (!_rejectGeneration(xmaxError)) {
      final listener = _roomID.isEmpty
          ? (_localMediaErrorListener ?? _errorListener)
          : _errorListener;

      listener?.call(xmaxError);
    }
  }

  /// 检查流的房间和用户账号是否符合当前会话预期。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  ///
  /// 返回远端流的房间及用户账号是否符合当前会话预期。
  bool _isExpectedRemote(
    RemoteStream stream,
  ) =>
      stream.roomID == _roomID &&
      (_botName.isEmpty || stream.userID == _botName);

  /// 以指定错误结束当前生成确认并取消其计时器。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回是否存在并已结束正在等待的生成确认。
  bool _rejectGeneration(
    XmaxError error,
  ) {
    final completer = _generationCompleter;

    _generationTimer?.cancel();
    _generationTimer = null;
    _generationCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);

      return true;
    }

    return false;
  }

  /// 结束当前任务和就绪等待，停止质量调节并清理远端音频及显示。
  ///
  /// - [notifyRemote]：是否通知视图清除当前结果流绑定。
  Future<void> _clearGeneration({
    required bool notifyRemote,
  }) async {
    _rejectGeneration(
      const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Realtime generation start cancelled',
      ),
    );

    _generationTaskID = null;
    _canAdapt = false;
    await _adaptation;
    _startSignalSent = false;
    _downlinkStatisticsListener?.call(null);
    _remoteAudioEnabled = false;
    _activeRemoteStream = null;
    await _deactivateRemoteAudio();

    if (notifyRemote) {
      _clearRemoteStream();
    }
  }

  /// 检查音频订阅操作是否仍属于当前任务和结果流。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  /// - [streamID]：需要发布、订阅或控制的媒体流标识。
  /// - [version]：当前异步操作的版本号。
  ///
  /// 返回任务、音频流和订阅版本是否仍然有效。
  bool _isAudioStreamCurrent(
    RemoteStream stream,
    String streamID,
    int version,
  ) =>
      version == _audioSubscriptionVersion &&
      _generationTaskID != null &&
      identical(_activeRemoteStream, stream) &&
      _publishedRemoteAudioStreams[stream.userID] == streamID;

  /// 音频订阅操作失效时抛出取消错误。
  ///
  /// - [stream]：待处理的远端 RTC 流。
  /// - [streamID]：需要发布、订阅或控制的媒体流标识。
  /// - [version]：当前异步操作的版本号。
  void _ensureAudioStreamCurrent(
    RemoteStream stream,
    String streamID,
    int version,
  ) {
    if (!_isAudioStreamCurrent(stream, streamID, version)) {
      throw const XmaxError(
        code: XmaxErrorCode.cancelled,
        message: 'Remote generation audio subscription was cancelled',
      );
    }
  }

  /// 使旧音频订阅失效，并取消已生效的远端音频订阅。
  Future<void> _deactivateRemoteAudio() async {
    final subscribedID = _subscribedRemoteAudioStreamID;

    _audioSubscriptionVersion += 1;
    _subscribedRemoteAudioStreamID = null;
    if (subscribedID == null) return;

    await _safe(
      '取消订阅 RTC 远端音频失败 (Failed to Unsubscribe from RTC Remote Audio)',
      () => _rtcManager.subscribeRemoteAudio(
        streamID: subscribedID,
        subscribe: false,
      ),
    );
  }

  /// 清空结果流绑定；监听器异常只记录日志。
  void _clearRemoteStream() {
    try {
      _remoteStreamListener?.call(null);
    } catch (error) {
      XmaxLogger.error(
        category: XmaxLoggerCategory.stream,
        message:
            '清理 RTC 远端生成流失败 '
            '(Failed to Clean Up RTC Remote Generation Stream)\n'
            '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
      );
    }
  }

  /// 执行资源清理操作并记录失败，允许其余清理继续进行。
  ///
  /// - [title]：日志组的标题。
  /// - [operation]：要执行的异步操作。
  Future<void> _safe(
    String title,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error) {
      XmaxLogger.error(
        category: XmaxLoggerCategory.stream,
        message: '$title\n└─ ${XmaxLogger.localized('原因：', 'Reason: ')}$error',
      );
    }
  }
}
