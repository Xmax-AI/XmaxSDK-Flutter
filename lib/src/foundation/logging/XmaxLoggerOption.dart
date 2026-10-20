//
//  XmaxLoggerOption.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 控制 XmaxSDK 输出的日志类型。
final class XmaxLoggerOption {

  /// 创建日志分类位标志。
  const XmaxLoggerOption({
    required this.rawValue,
  });

  /// 日志类别的位标志值，可通过按位或组合。
  final int rawValue;

  /// API、会话、生成及文件服务的业务日志标志。
  static const business = XmaxLoggerOption(rawValue: 1 << 0);

  /// RTC 统计和启动耗时等性能日志标志。
  static const performance = XmaxLoggerOption(rawValue: 1 << 1);

  /// 全部可选类别。
  static const all = XmaxLoggerOption(rawValue: 3);

  /// 判断当前标志是否包含指定日志类别。
  ///
  /// - [option]：控制本条日志是否输出的类别标志。
  ///
  /// 返回当前日志标志是否包含指定类别的全部位。
  bool contains(
    XmaxLoggerOption option,
  ) => option.rawValue != 0 && (rawValue & option.rawValue) == option.rawValue;

  /// 合并两组日志类别标志。
  ///
  /// - [other]：要合并的另一组日志类别。
  ///
  /// 返回同时包含两组类别的日志标志。
  XmaxLoggerOption operator |(
    XmaxLoggerOption other,
  ) => XmaxLoggerOption(rawValue: rawValue | other.rawValue);

  /// 与 [other] 比较类型及 [rawValue] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is XmaxLoggerOption && rawValue == other.rawValue;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => rawValue.hashCode;
}
