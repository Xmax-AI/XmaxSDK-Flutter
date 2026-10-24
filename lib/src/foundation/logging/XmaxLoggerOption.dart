//
//  XmaxLoggerOption.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The categories of logs emitted by XmaxSDK.
final class XmaxLoggerOption {

  /// Creates a log category bitmask.
  const XmaxLoggerOption({
    required this.rawValue,
  });

  /// The log category bits, combinable with bitwise OR.
  final int rawValue;

  /// The flag for API, session, generation, and file service logs.
  static const business = XmaxLoggerOption(rawValue: 1 << 0);

  /// The flag for performance logs such as RTC statistics and startup timing.
  static const performance = XmaxLoggerOption(rawValue: 1 << 1);

  /// All optional log categories.
  static const all = XmaxLoggerOption(rawValue: 3);

  /// Checks whether this bitmask contains the specified log categories.
  ///
  /// Parameters:
  /// - [option]: The category flag controlling whether to output this message.
  ///
  /// Returns whether this bitmask contains every bit of the specified categories.
  bool contains(
    XmaxLoggerOption option,
  ) => option.rawValue != 0 && (rawValue & option.rawValue) == option.rawValue;

  /// Combines two log category bitmasks.
  ///
  /// Parameters:
  /// - [other]: The other log categories to combine.
  ///
  /// Returns a bitmask containing both sets of categories.
  XmaxLoggerOption operator |(
    XmaxLoggerOption other,
  ) => XmaxLoggerOption(rawValue: rawValue | other.rawValue);

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxLoggerOption && rawValue == other.rawValue;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => rawValue.hashCode;
}
