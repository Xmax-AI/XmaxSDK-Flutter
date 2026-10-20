//
//  RealtimeState.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';

/// 进入当前实时状态的原因。
final class RealtimeReason {

  /// 创建内部状态原因记录。
  const RealtimeReason._(
    this._kind,
    this.error,
  );

  /// 主动停止或正常释放资源。
  static const normal = RealtimeReason._('normal', null);

  /// 显示方向发生变化，需要重新配置生成任务。
  static const orientationChanged = RealtimeReason._(
    'orientationChanged',
    null,
  );

  /// 创建失败原因。
  ///
  /// - [error]：导致状态结束的 SDK 错误，保存在 [RealtimeReason.error]。
  factory RealtimeReason.failure(
    XmaxError error,
  ) => RealtimeReason._('failure', error);

  /// 状态结束原因的内部分类标识。
  final String _kind;

  /// 失败原因对应的 SDK 错误；其他原因时为 `null`。
  final XmaxError? error;

  /// 与 [other] 比较类型及 [_kind]、[error] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimeReason && _kind == other._kind && error == other.error;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(_kind, error);
}

/// 实时业务连接状态。
enum RealtimeConnectionState {

  /// 没有可用的本地媒体流。
  idle('Idle'),

  /// 正在准备本地媒体流；摄像头需等待首帧和预览视图绑定。
  preparing('Preparing'),

  /// 本地媒体流已就绪，可预览、连接和生成。
  ready('Ready'),

  /// 正在创建云端会话、加入 RTC 房间并发布本地视频。
  connecting('Connecting'),

  /// 实时连接已建立，当前没有生成任务。
  connected('Connected'),

  /// 实时连接已建立且生成任务正在运行。
  generating('Generating'),

  /// 正在停止生成、退出 RTC 房间并关闭云端会话。
  disconnecting('Disconnecting');

  /// 定义实时连接状态标识。
  const RealtimeConnectionState(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}

/// 实时业务当前状态快照。
final class RealtimeState {

  /// 创建实时状态快照。
  const RealtimeState({
    required this.connectionState,
    this.sessionID,
    this.taskID,
    this.reason,
  });

  /// 当前连接生命周期状态。
  final RealtimeConnectionState connectionState;

  /// 当前或最近一次云端实时会话的标识。
  final String? sessionID;

  /// 当前生成任务标识。
  final String? taskID;

  /// 进入当前状态的原因；正常开始新的操作时清空。
  final RealtimeReason? reason;

  /// 与 [other] 比较类型及 [connectionState]、[sessionID]、[taskID]、[reason] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is RealtimeState &&
          connectionState == other.connectionState &&
          sessionID == other.sessionID &&
          taskID == other.taskID &&
          reason == other.reason;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(connectionState, sessionID, taskID, reason);
}

/// 接收实时生命周期状态快照的回调。
///
/// - [state]：当前实时生命周期状态。
typedef RealtimeStateListener =
    void Function(
      RealtimeState state,
    );
