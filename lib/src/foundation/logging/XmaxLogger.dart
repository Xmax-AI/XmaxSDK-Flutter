//
//  XmaxLogger.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/XmaxEnvironment.dart';
import 'XmaxLoggerOption.dart';

/// Filters, localizes, and outputs SDK logs using process-wide configuration.
abstract final class XmaxLogger {

  /// The currently enabled log categories.
  static XmaxLoggerOption _options = const XmaxLoggerOption(rawValue: 0);

  /// The current log language environment.
  static XmaxEnvironment _environment = XmaxEnvironment.china;

  /// The output function receiving formatted log messages.
  static XmaxLogSink _sink = _defaultSink;

  /// The method channel for communication with the native platform.
  static const _channel = MethodChannel('ai.xmax.sdk/logging');

  /// Configures logging for all SDK clients; subsequent configuration replaces the previous
  /// settings.
  ///
  /// Parameters:
  /// - [options]: The enabled log categories.
  /// - [environment]: The log language environment; defaults to the domestic environment with
  ///   Chinese details.
  static void configure({
    required XmaxLoggerOption options,
    XmaxEnvironment environment = XmaxEnvironment.china,
  }) {
    _options = options;
    _environment = environment;
  }

  /// Selects SDK text for the environment without modifying server content or application prompts.
  ///
  /// Parameters:
  /// - [chinese]: The label for the China environment.
  /// - [english]: The label for the global environment.
  ///
  /// Returns the Chinese or English text for the current environment.
  static String localized(
    String chinese,
    String english,
  ) => _environment == XmaxEnvironment.china ? chinese : english;

  /// Checks whether the specified log category is enabled.
  ///
  /// Parameters:
  /// - [option]: The category flag controlling whether to output this message.
  ///
  /// Returns whether the process-wide configuration enables this category.
  static bool isEnabled(
    XmaxLoggerOption option,
  ) => _options.contains(option);

  /// Outputs a debug message if its category is enabled.
  ///
  /// Parameters:
  /// - [category]: The functional category; null uses the general SDK prefix.
  /// - [message]: The complete message text.
  /// - [option]: The flag controlling message output; defaults to the business log category.
  static void debug({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(
      XmaxLogLevel.debug,
      message,
      category: category,
      option: option,
    );
  }

  /// Outputs an informational message if its category is enabled.
  ///
  /// Parameters:
  /// - [category]: The functional category; null uses the general SDK prefix.
  /// - [message]: The complete message text.
  /// - [option]: The flag controlling message output; defaults to the business log category.
  static void info({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(
      XmaxLogLevel.info,
      message,
      category: category,
      option: option,
    );
  }

  /// Outputs a warning if its category is enabled.
  ///
  /// Parameters:
  /// - [category]: The functional category; null uses the general SDK prefix.
  /// - [message]: The complete message text.
  /// - [option]: The flag controlling message output; defaults to the business log category.
  static void warn({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(
      XmaxLogLevel.warning,
      message,
      category: category,
      option: option,
    );
  }

  /// Outputs an error message if its category is enabled.
  ///
  /// Parameters:
  /// - [category]: The functional category; null uses the general SDK prefix.
  /// - [message]: The complete message text.
  /// - [option]: The flag controlling message output; defaults to the business log category.
  static void error({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(
      XmaxLogLevel.error,
      message,
      category: category,
      option: option,
    );
  }

  /// Prefixes each log line with the SDK name and optional functional category.
  ///
  /// Parameters:
  /// - [category]: The functional category; null uses the general SDK prefix.
  /// - [message]: The complete message text.
  ///
  /// Returns log text with SDK and category prefixes on every line.
  static String formattedMessage({
    XmaxLoggerCategory? category,
    required String message,
  }) {
    final prefix = category == null ? '[Xmax]' : '[Xmax][${category.value}]';

    return message.split('\n').map((
      line,
    ) => '$prefix $line').join('\n');
  }

  /// Writes formatted logs using the current logging options.
  ///
  /// Parameters:
  /// - [level]: The severity of the current log message.
  /// - [message]: The complete message text.
  /// - [category]: The functional category; null uses the general SDK prefix.
  /// - [option]: The category flag controlling whether to output this message.
  static void _write(
    XmaxLogLevel level,
    String message, {
    required XmaxLoggerCategory? category,
    required XmaxLoggerOption option,
  }) {
    if (!isEnabled(option)) {
      return;
    }

    _sink(
      level,
      formattedMessage(
        category: category,
        message: message,
      ),
    );
  }

  /// Submits formatted messages to runtime logging and the available native logging channel.
  ///
  /// Parameters:
  /// - [level]: The severity of the current log message.
  /// - [message]: The complete message text.
  static void _defaultSink(
    XmaxLogLevel level,
    String message,
  ) {
    developer.log(
      message,
      name: 'ai.xmax.XmaxSDK',
      level: level.value,
    );
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      debugPrint(message);

      return;
    }

    // Native logging is independent of application operations.
    // Logs enabled through loggerOptions are also output in Profile and Release modes.
    unawaited(_writeNative(
      level,
      message,
    ));
  }

  /// Outputs native logs through a method channel without affecting application calls if
  /// unavailable.
  ///
  /// Parameters:
  /// - [level]: The severity of the current log message.
  /// - [message]: The complete message text.
  static Future<void> _writeNative(
    XmaxLogLevel level,
    String message,
  ) async {
    try {
      await _channel.invokeMethod<void>(
        'log',
        <String, String>{
        'level': level.name,
        'message': message,
      },
      );
    } catch (_) {
      // Fall back to Dart logging if the plugin is unregistered or unavailable.
      // Do not report logging failures through SDK error handling, which would create a reporting loop.
      debugPrint(message);
    }
  }

  /// Replaces the process-wide log output function.
  ///
  /// Parameters:
  /// - [sink]: The output function receiving formatted log messages.
  @visibleForTesting
  static void setSink(
    XmaxLogSink sink,
  ) {
    _sink = sink;
  }

  /// Restores the default log configuration and output function.
  @visibleForTesting
  static void reset() {
    _options = const XmaxLoggerOption(rawValue: 0);
    _environment = XmaxEnvironment.china;
    _sink = _defaultSink;
  }
}

/// A functional category for SDK logs.
enum XmaxLoggerCategory {

  /// API request logs.
  api('API'),

  /// Native RTC transport and performance logs.
  rtc('RTC'),

  /// Room identity, heartbeat, and signaling logs.
  room('Room'),

  /// Stream publication, subscription, generation startup, and quality adjustment logs.
  stream('Stream'),

  /// File transfer and safety check logs.
  storage('Storage'),

  /// Realtime lifecycle logs.
  realtime('Realtime'),

  /// Media capture and processing logs.
  media('Media'),

  /// Video and trail rendering logs.
  render('Render'),

  /// Media permission check logs.
  permission('Permission'),

  /// Interaction input logs.
  interaction('Interaction');

  /// Defines a log category name.
  const XmaxLoggerCategory(
    this.value,
  );

  /// The category name included in log prefixes.
  final String value;
}

/// A log severity and its system logging priority.
enum XmaxLogLevel {

  /// Debug severity.
  debug(500),

  /// Informational severity.
  info(800),

  /// Warning severity.
  warning(900),

  /// Error severity.
  error(1000);

  /// Defines a system logging priority.
  const XmaxLogLevel(
    this.value,
  );

  /// The corresponding integer system logging priority.
  final int value;
}

/// An output function for categorized, formatted logs; implementations must avoid logging
/// credentials.
///
/// Parameters:
/// - [level]: The severity of the current log message.
/// - [message]: The complete message text.
typedef XmaxLogSink =
    void Function(
      XmaxLogLevel level,
      String message,
    );
