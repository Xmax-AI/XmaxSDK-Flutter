//
//  RtcEngineManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import '../errors/XmaxError.dart';
import 'RtcPlatform.dart';
import 'AgoraRtcPlatform.dart';

/// RTC 引擎的独占使用凭证（租约），释放引擎时用于确认资源归属。
final class RtcEngineLease {

  /// 创建 RTC 引擎独占租约。
  RtcEngineLease(
    this.engine,
  );

  /// 当前使用的原生 RTC 引擎。
  final RtcPlatform engine;

  /// 识别引擎使用者的唯一标识。
  final Object id = Object();
}

/// 按申请顺序分配 RTC 引擎，同一时刻只允许一个使用者持有引擎。
final class RtcEngineManager {

  /// 创建使用原生 RTC 引擎工厂的独占分配器。
  RtcEngineManager._() : _createEngine = _createNativeEngine;

  /// 使用指定引擎工厂创建独占分配器。
  ///
  /// - [createEngine]：每次分配租约时创建并初始化平台资源的函数。
  RtcEngineManager.internal({
    required Future<RtcPlatform> Function() createEngine,
  }) : _createEngine = createEngine;

  /// 进程共享的独占 RTC 引擎分配器。
  static final shared = RtcEngineManager._();

  /// RTC 引擎与服务端凭证约定的应用标识。
  static const defaultAppID = '5588dfe2e7874bd08ea28f4968ec2d40';

  /// 创建原生 RTC 引擎资源的函数。
  final Future<RtcPlatform> Function() _createEngine;

  /// 创建使用约定应用标识的原生 RTC 平台资源。
  ///
  /// 返回已初始化且本地采集尚未开启的 RTC 平台资源。
  static Future<RtcPlatform> _createNativeEngine() =>
      AgoraRtcPlatform.create(defaultAppID);

  /// 当前占用引擎的独占租约。
  RtcEngineLease? _activeLease;

  /// 按申请顺序排队的独占引擎租约请求。
  final List<Completer<RtcEngineLease>> _requests =
      <Completer<RtcEngineLease>>[];

  /// 按请求顺序获取 RTC 引擎的独占租约。
  ///
  /// 返回当前调用持有的独占 RTC 引擎租约。
  Future<RtcEngineLease> acquire() async {
    final completer = Completer<RtcEngineLease>();

    _requests.add(completer);
    unawaited(_fulfillNext());

    return completer.future;
  }

  /// 仅释放匹配的当前引擎租约，并继续处理等待中的使用者。
  ///
  /// - [lease]：需要释放的独占 RTC 引擎租约。
  Future<void> release(
    RtcEngineLease lease,
  ) async {
    if (!identical(_activeLease?.id, lease.id)) {
      return;
    }

    try {
      await lease.engine.destroy();
    } finally {
      // 即使原生引擎释放失败，也要清除占用状态，让排队中的其他管理器继续申请引擎。
      _activeLease = null;
      await _fulfillNext();
    }
  }

  /// 创建新的原生引擎租约；初始化失败时返回 RTC 错误。
  ///
  /// 返回当前调用持有的独占 RTC 引擎租约。
  Future<RtcEngineLease> _createLease() async {
    try {
      final engine = await _createEngine();

      return RtcEngineLease(engine);
    } catch (error) {
      throw XmaxError(
        code: XmaxErrorCode.rtcError,
        message: 'Failed to create RTC Engine: $error',
      );
    }
  }

  /// 在没有活动租约时依次满足排队的引擎使用请求。
  Future<void> _fulfillNext() async {
    if (_creating) return;

    _creating = true;

    try {
      while (_activeLease == null && _requests.isNotEmpty) {
        final request = _requests.removeAt(0);

        try {
          final lease = await _createLease();

          _activeLease = lease;
          request.complete(lease);
        } catch (error, stackTrace) {
          request.completeError(error, stackTrace);
        }
      }
    } finally {
      _creating = false;
    }
  }

  /// 是否正在串行创建新的 RTC 引擎。
  bool _creating = false;
}
