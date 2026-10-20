//
//  RealtimeErrorHandler.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/ErrorMessageFormatter.dart';
import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';

/// 实时错误所影响的资源范围。
enum RealtimeFailureScope {

  /// 仅远端连接资源，保留本地媒体。
  connection,

  /// 本地媒体和远端连接资源。
  all,
}

/// 当前有效生命周期中统一处理实时失败的异步回调。
///
/// - [error]：本次操作的错误。
/// - [scope]：错误影响的资源范围。
/// - [isCurrent]：检查操作是否仍属于当前生命周期的函数。
typedef RealtimeFailureHandler =
    Future<void> Function(
      XmaxError error,
      RealtimeFailureScope scope,
      bool Function() isCurrent,
    );

/// 统一处理实时错误，忽略已结束生命周期的错误回调。
final class RealtimeErrorHandler {

  /// 当前生命周期的失败处理回调。
  RealtimeFailureHandler? _failureHandler;

  /// 本地媒体生命周期的版本号。
  int _mediaRevision = 0;

  /// 远端连接生命周期的版本号。
  int _connectionRevision = 0;

  /// 设置当前生命周期的错误处理回调。
  ///
  /// - [handler]：错误处理回调；传入 null 后不再分发错误。
  void setFailureHandler(
    RealtimeFailureHandler? handler,
  ) {
    _failureHandler = handler;
  }

  /// 使指定资源的旧错误回调失效，避免它们关闭新创建的连接或媒体流。
  ///
  /// - [scope]：受影响的资源范围；默认包含本地媒体和远端连接。
  void invalidatePendingFailures({
    RealtimeFailureScope scope = RealtimeFailureScope.all,
  }) {
    _connectionRevision += 1;
    if (scope == RealtimeFailureScope.all) _mediaRevision += 1;
  }

  /// 记录指定资源的当前版本，供异步回调判断原操作是否仍有效。
  ///
  /// - [scope]：要检查的资源范围。
  ///
  /// 返回版本检查函数；资源已重建或关闭时返回 false。
  bool Function() captureValidity(
    RealtimeFailureScope scope,
  ) {
    final revision = _revision(scope);

    return () => revision == _revision(scope);
  }

  /// 读取指定资源范围的生命周期的版本号。
  ///
  /// - [scope]：错误影响的资源范围。
  ///
  /// 返回指定资源范围当前的版本号。
  int _revision(
    RealtimeFailureScope scope,
  ) => scope == RealtimeFailureScope.all ? _mediaRevision : _connectionRevision;

  /// 将错误转换为 SDK 错误并记录。
  ///
  /// - [error]：本次操作的错误。
  ///
  /// 返回统一 SDK 错误。
  XmaxError report(
    Object error,
  ) {
    final xmaxError = XmaxError.from(error);

    _log(xmaxError);

    return xmaxError;
  }

  /// 仅在来源生命周期仍有效时分发运行错误。
  ///
  /// - [error]：本次操作的错误。
  /// - [scope]：错误影响的资源范围。省略时仅影响远端连接，保留本地媒体。
  void forward(
    XmaxError error, {
    RealtimeFailureScope scope = RealtimeFailureScope.connection,
  }) {
    final isCurrent = captureValidity(scope);
    final handler = _failureHandler;
    // 异步处理前记录所属生命周期，分发错误前再次检查，避免旧错误关闭新的连接或媒体流。
    Future<void>.microtask(() async {
      if (!isCurrent()) return;

      _log(error);
      await handler?.call(error, scope, isCurrent);
    }).catchError((Object failure) {
      _log(XmaxError.from(failure));
    });
  }

  /// 记录统一错误；日志输出失败不影响错误传播。
  ///
  /// - [error]：本次操作的错误。
  void _log(
    XmaxError error,
  ) {
    try {
      XmaxLogger.error(
        category: XmaxLoggerCategory.realtime,
        message:
            '实时操作失败 (Realtime Operation Failed)\n'
            '└─ ${XmaxLogger.localized('原因：', 'Reason: ')}${ErrorMessageFormatter.format(error)}',
      );
    } catch (_) {
      // 日志输出失败不能阻止原始错误继续传递。
    }
  }
}
