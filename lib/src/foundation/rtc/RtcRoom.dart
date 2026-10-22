//
//  RtcRoom.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RtcModels.dart';

/// 单次房间连接及其发布、订阅和信令资源。
abstract interface class RtcRoom {

  /// 当前房间是否已关闭。
  bool get isClosed;

  /// 加入 RTC 房间并创建信令发送队列，不自动发布或订阅媒体。
  ///
  /// - [configuration]：本次入房使用的房间标识、用户账号和访问令牌。
  Future<void> join(
    RoomJoinConfiguration configuration,
  );

  /// 关闭房间并等待原生离房，期间仅保留离房通知，不改变本地摄像头采集。
  Future<void> destroy();

  /// 提交房间 JSON 信令；条件变更清理待发轨迹，自动调档失败不关闭连接。
  ///
  /// - [message]：完整消息文本。
  Future<void> sendMessage(
    String message,
  );
}
