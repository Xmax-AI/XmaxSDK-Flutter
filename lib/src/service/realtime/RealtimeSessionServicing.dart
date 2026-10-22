//
//  RealtimeSessionServicing.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../core/realtime/RealtimeModel.dart';
import 'RealtimeSession.dart';

/// 云端会话创建、心跳和关闭的内部接口。
abstract interface class RealtimeSessionServicing {

  /// 为指定模型创建云端实时会话，并校验完整 RTC 连接凭证。
  ///
  /// - [model]：实时生成模型，决定可用的媒体规格。
  ///
  /// 返回解析后的云端实时会话。
  Future<RealtimeSession> createSession({
    required RealtimeModel model,
  });

  /// 启动当前会话的心跳，替换先前心跳周期。
  ///
  /// - [sessionID]：云端实时会话标识。
  /// - [onFailure]：操作失败时的处理回调。
  void startHeartbeat({
    required String sessionID,
    required RealtimeSessionHeartbeatFailureHandler onFailure,
  });

  /// 停止会话心跳，并使旧心跳请求的响应失效。
  void stopHeartbeat();

  /// 关闭指定云端实时会话。
  ///
  /// - [sessionID]：云端实时会话标识。
  Future<void> closeSession({
    required String sessionID,
  });
}
