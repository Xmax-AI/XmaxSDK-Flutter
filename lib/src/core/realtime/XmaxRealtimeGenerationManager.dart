//
//  XmaxRealtimeGenerationManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:io';
import 'dart:math';

import '../../foundation/errors/XmaxError.dart';
import '../../media/interaction/InteractionControlling.dart';
import '../../service/realtime/RealtimeContext.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import '../../stream/StreamControlling.dart';
import 'RealtimeTiming.dart';

/// 为每次新生成任务创建唯一标识的函数。
///
/// 返回本次新生成任务的唯一标识。
typedef RealtimeTaskIDGenerator = String Function();

/// 管理生成任务、缓存生成条件，并绑定当前任务的交互输入。
final class XmaxRealtimeGenerationManager {

  /// 创建生成任务协调器。
  ///
  /// - [interactionController]：将触点输入绑定到生成任务的组件。
  /// - [streamController]：发送生成信令的组件。
  /// - [taskIDGenerator]：任务标识生成函数；默认使用 [createTaskID]。
  XmaxRealtimeGenerationManager({
    required InteractionControlling interactionController,
    required StreamControlling streamController,
    RealtimeTaskIDGenerator? taskIDGenerator,
  }) : _interactionController = interactionController,
       _streamController = streamController,
       _taskIDGenerator = taskIDGenerator ?? createTaskID;

  /// 当前生成任务的触点采样和坐标处理组件。
  final InteractionControlling _interactionController;

  /// 管理 RTC 连接、发布订阅和生成信令的组件。
  final StreamControlling _streamController;

  /// 创建生成任务标识的函数。
  final RealtimeTaskIDGenerator _taskIDGenerator;

  /// 最近一次成功提交的生成条件。
  RealtimeContext? _currentContext;

  /// 最近一次成功提交的人脸回贴设置。
  bool _currentFaceRestoration = false;

  /// 恢复生成时使用的人脸回贴设置。
  bool get cachedFaceRestoration => _currentFaceRestoration;

  /// 等待当前生成结果流的任务，可主动取消。
  GenerationStartConfirmation? _startConfirmation;

  /// 生成启动版本号。
  int _startVersion = 0;

  /// 取消当前结果流的等待任务，保留 RTC 连接供后续生成使用。
  void cancelPendingStart() {
    _startVersion += 1;
    _startConfirmation?.cancel();
  }

  /// 创建新任务，等待结果流确认并绑定任务交互输入，成功后缓存生成条件。
  ///
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [context]：生成条件；null 时复用缓存，首次启动没有缓存时抛出配置错误。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  /// - [ensureCurrent]：检查当前生命周期是否仍有效的函数；已失效时须抛出取消错误。
  /// - [timing]：当前生成启动的耗时记录；为空时不记录。
  ///
  /// 返回新生成任务的标识。
  Future<String> start({
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext? context,
    bool faceRestoration = false,
    required void Function() ensureCurrent,
    RealtimeTiming? timing,
  }) async {
    final resolvedContext = validateContext(context);

    final taskID = _taskIDGenerator();
    final startVersion = _startVersion;
    GenerationStartConfirmation? ownedConfirmation;

    try {
      timing?.beginSignal();

      final confirmation = await _streamController.beginGeneration(
        taskID: taskID,
        videoFormat: videoFormat,
        context: resolvedContext,
        faceRestoration: faceRestoration,
        targetSize: _streamController.targetSize,
      );

      ownedConfirmation = confirmation;
      _startConfirmation = confirmation;
      if (startVersion != _startVersion) {
        confirmation.cancel();
      }

      await confirmation.value;
      timing?.confirmRemoteStream();
      if (startVersion != _startVersion) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Realtime generation start cancelled',
        );
      }

      ensureCurrent();

      _interactionController.startInteraction(
        taskID: taskID,
        videoFormat: videoFormat,
      );

      _currentContext = resolvedContext;
      _currentFaceRestoration = faceRestoration;

      return taskID;
    } catch (error) {
      // 后续步骤失败时，启动信令可能已经送达，需要通知服务端停止任务。
      try {
        await _streamController.stopGeneration(taskID: taskID);
      } catch (_) {
        // 保留原始启动错误，房间资源仍由连接协调器释放。
      }

      throw XmaxError.from(error);
    } finally {
      if (identical(_startConfirmation, ownedConfirmation)) {
        _startConfirmation = null;
      }
    }
  }

  /// 解析本次或缓存的生成条件；首次生成未提供条件时抛出配置错误。
  ///
  /// - [context]：待使用的生成条件；null 时读取最近成功的条件。
  ///
  /// 返回本次或最近缓存的有效生成条件。
  RealtimeContext validateContext(
    RealtimeContext? context,
  ) {
    final resolvedContext = context ?? _currentContext;

    if (resolvedContext == null) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'A realtime context is required for the first generation',
      );
    }

    return resolvedContext;
  }

  /// 更新当前任务的生成条件和人脸回贴设置，成功后替换缓存条件。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  /// - [context]：更新后的生成条件；null 时复用最近成功的条件。
  /// - [faceRestoration]：是否回贴原始人脸，默认关闭；每次调用提交本次值。
  Future<void> update({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
    required RealtimeContext? context,
    bool faceRestoration = false,
  }) async {
    _interactionController.startInteraction(
      taskID: taskID,
      videoFormat: videoFormat,
    );

    final resolvedContext = validateContext(context);

    await _streamController.updateGeneration(
      taskID: taskID,
      videoFormat: videoFormat,
      context: resolvedContext,
      faceRestoration: faceRestoration,
      targetSize: _streamController.targetSize,
    );

    _currentContext = resolvedContext;
    _currentFaceRestoration = faceRestoration;
  }

  /// 取消尚未完成的启动请求并停止当前生成任务及交互输入。
  ///
  /// - [taskID]：当前生成任务标识。
  Future<void> stop({
    required String taskID,
  }) async {
    cancelPendingStart();
    _interactionController.stopInteraction();
    await _streamController.stopGeneration(taskID: taskID);
  }

  /// 停止当前任务和交互，并清除缓存生成条件。
  ///
  /// - [taskID]：当前生成任务标识。省略时为空字符串，停止当前活动生成任务。
  Future<void> reset({
    String taskID = '',
  }) async {
    _currentContext = null;
    _currentFaceRestoration = false;
    await stop(taskID: taskID);
  }

  /// 生成以 task- 开头的随机任务标识，并附带 Flutter 运行平台查询字段。
  ///
  /// 返回 task- 随机标识及 os=flutter-平台 查询字段。
  static String createTaskID() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // 将 128 位随机数编码为不带填充字符的 base64url。
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final output = StringBuffer('task-');

    for (var index = 0; index < bytes.length; index += 3) {
      final remaining = bytes.length - index;
      final value =
          (bytes[index] << 16) |
          (remaining > 1 ? bytes[index + 1] << 8 : 0) |
          (remaining > 2 ? bytes[index + 2] : 0);

      output.write(alphabet[(value >> 18) & 63]);
      output.write(alphabet[(value >> 12) & 63]);
      if (remaining > 1) output.write(alphabet[(value >> 6) & 63]);

      if (remaining > 2) output.write(alphabet[value & 63]);
    }

    // 用平台查询字段标记客户端来源，不改变随机任务标识。
    output.write('?os=flutter-${Platform.operatingSystem}');

    return output.toString();
  }
}
