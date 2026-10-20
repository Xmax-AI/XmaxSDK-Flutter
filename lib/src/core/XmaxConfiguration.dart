//
//  XmaxConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../foundation/errors/XmaxError.dart';
import '../foundation/logging/XmaxLoggerOption.dart';
import 'XmaxEnvironment.dart';

/// SDK 的访问凭证、存储服务环境和日志配置。
final class XmaxConfiguration {

  /// 创建 SDK 配置，并去除 API key 首尾的空白字符。
  ///
  /// - [apiKey]：开放平台签发的访问密钥；可调用 [validate] 检查是否为空。
  /// - [environment]：存储服务区域和日志语言，默认使用国内环境。
  /// - [loggerOptions]：允许输出的日志类别，默认关闭 SDK 日志。
  XmaxConfiguration({
    required String apiKey,
    this.environment = XmaxEnvironment.china,
    this.loggerOptions = const XmaxLoggerOption(rawValue: 0),
  }) : apiKey = apiKey.trim();

  /// 开放平台签发的 API key，不应写入公开仓库或日志。
  final String apiKey;

  /// 存储服务区域及 SDK 日志语言配置。
  final XmaxEnvironment environment;

  /// 允许输出的日志类别。
  final XmaxLoggerOption loggerOptions;

  /// 检查 API key 是否为空；为空时抛出 invalidAPIKey 错误。
  void validate() {
    if (apiKey.isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidAPIKey,
        message: 'API key cannot be empty',
      );
    }
  }

  /// 与 [other] 比较类型及 [apiKey]、[environment]、[loggerOptions] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is XmaxConfiguration &&
          apiKey == other.apiKey &&
          environment == other.environment &&
          loggerOptions == other.loggerOptions;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(apiKey, environment, loggerOptions);
}
