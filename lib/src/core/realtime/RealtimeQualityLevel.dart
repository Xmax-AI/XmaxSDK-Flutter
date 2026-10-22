//
//  RealtimeQualityLevel.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 实时传输档位；L1 质量最高，L5 更侧重降低带宽占用。
///
/// 档位不表示当前网络质量。手动调档后，SDK 仍会根据网络情况自动调整。
enum RealtimeQualityLevel {

  /// 使用最高传输规格。
  l1(1),

  /// 使用较高传输规格，也是首次连接的默认档位。
  l2(2),

  /// 兼顾画质和带宽占用。
  l3(3),

  /// 降低传输尺寸和上行帧率。
  l4(4),

  /// 使用较低上行帧率，优先降低带宽占用。
  l5(5);

  /// 定义档位的序列化数值。
  const RealtimeQualityLevel(
    this.value,
  );

  /// 档位数值，范围为 1～5。
  final int value;
}
