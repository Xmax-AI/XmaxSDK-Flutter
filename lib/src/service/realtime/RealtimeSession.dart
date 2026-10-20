//
//  RealtimeSession.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 云端分配的 RTC 房间凭证和预期结果流用户账号。
final class RealtimeSessionConnection {

  /// 创建云端分配的 RTC 连接参数。
  const RealtimeSessionConnection({
    required this.roomID,
    required this.userID,
    required this.token,
    this.botName,
  });

  /// 云端分配的 RTC 房间标识。
  final String roomID;

  /// RTC 用户账号，不是数字 UID。
  final String userID;

  /// 加入房间使用的 RTC 访问令牌。
  final String token;

  /// 预期结果流的 RTC 用户账号；未提供或为空时不按特定账号筛选结果流。
  final String? botName;
}

/// 云端实时会话的标识、状态、连接参数和关闭原因。
final class RealtimeSession {

  /// 创建云端会话状态快照。
  const RealtimeSession({
    required this.id,
    this.userID,
    this.status,
    this.connection,
    this.closeReason,
  });

  /// 云端实时会话的唯一标识。
  final String id;

  /// 云端业务用户标识，不是 RTC 用户账号；服务未提供时为 null。
  final String? userID;

  /// 云端会话状态；未返回该字段时为空。
  final String? status;

  /// 云端分配的 RTC 房间凭证；心跳响应中可能为空。
  final RealtimeSessionConnection? connection;

  /// 云端会话的关闭原因；未提供时为空。
  final String? closeReason;
}

/// 接收云端会话失效或心跳失败的异步回调。
///
/// - [sessionID]：云端实时会话标识。
/// - [error]：本次操作的错误。
typedef RealtimeSessionHeartbeatFailureHandler =
    Future<void> Function(
      String sessionID,
      Object error,
    );
