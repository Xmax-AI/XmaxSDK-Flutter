//
//  InteractionControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';
import 'InteractionFrame.dart';

/// 生成任务的交互输入启停及采样提交接口。
abstract interface class InteractionControlling {

  /// 为当前生成任务启用交互输入，并清除旧任务的待发采样。
  ///
  /// - [taskID]：当前生成任务标识。
  /// - [videoFormat]：视频尺寸、帧率和编码配置。
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  });

  /// 停止交互输入，并使尚未提交的采样失效。
  void stopInteraction();

  /// 提交当前视图触点采样；没有有效生成任务时忽略。
  ///
  /// - [frame]：一次视图触点采样。
  void submitInteraction(
    InteractionFrame frame,
  );
}
