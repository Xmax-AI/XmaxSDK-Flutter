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

/// The credentials, service environment, and logging options for an Xmax client.
final class XmaxConfiguration {

  /// Creates a client configuration.
  XmaxConfiguration({
    required String apiKey,
    this.environment = XmaxEnvironment.china,
    this.loggerOptions = const XmaxLoggerOption(rawValue: 0),
  }) : apiKey = apiKey.trim();

  /// The API key used to access Xmax services. Do not include it in public source or logs.
  final String apiKey;

  /// The service environment and log detail language; defaults to China with Chinese details.
  final XmaxEnvironment environment;

  /// The enabled log categories; defaults to no logging.
  final XmaxLoggerOption loggerOptions;

  /// Verifies that the API key is not empty. Throws an invalidAPIKey error if it is empty.
  void validate() {
    if (apiKey.isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidAPIKey,
        message: 'API key cannot be empty',
      );
    }
  }

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxConfiguration &&
          apiKey == other.apiKey &&
          environment == other.environment &&
          loggerOptions == other.loggerOptions;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    apiKey,
    environment,
    loggerOptions,
  );
}
