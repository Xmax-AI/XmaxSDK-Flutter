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

/// SDK 日志的分类过滤、语言选择和输出入口；配置在进程内共享。
abstract final class XmaxLogger {

  /// 当前启用的日志类别。
  static XmaxLoggerOption _options = const XmaxLoggerOption(rawValue: 0);

  /// 当前日志语言环境。
  static XmaxEnvironment _environment = XmaxEnvironment.china;

  /// 接收格式化日志的输出函数。
  static XmaxLogSink _sink = _defaultSink;

  /// 与原生平台通信的方法通道。
  static const _channel = MethodChannel('ai.xmax.sdk/logging');

  /// 设置所有 SDK 客户端共用的日志类别和语言，后一次配置会覆盖前一次。
  ///
  /// - [options]：允许输出的日志类别。
  /// - [environment]：日志语言环境；默认使用国内环境，输出中文详情。
  static void configure({
    required XmaxLoggerOption options,
    XmaxEnvironment environment = XmaxEnvironment.china,
  }) {
    _options = options;
    _environment = environment;
  }

  /// 根据环境选择 SDK 内置文本，不修改服务端内容或业务提示词。
  ///
  /// - [chinese]：国内环境使用的中文文本。
  /// - [english]：海外环境使用的英文文本。
  ///
  /// 返回当前环境对应的中文或英文文本。
  static String localized(
    String chinese,
    String english,
  ) => _environment == XmaxEnvironment.china ? chinese : english;

  /// 检查指定日志类别是否已启用。
  ///
  /// - [option]：控制本条日志是否输出的类别标志。
  ///
  /// 返回该日志类别是否包含在当前进程日志配置中。
  static bool isEnabled(
    XmaxLoggerOption option,
  ) => _options.contains(option);

  /// 在对应日志类别启用时输出调试级别日志。
  ///
  /// - [category]：日志所属功能分类；为空时使用 SDK 通用前缀。
  /// - [message]：完整消息文本。
  /// - [option]：控制本条日志是否输出的类别标志。省略时归入 business 日志类别。
  static void debug({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(XmaxLogLevel.debug, message, category: category, option: option);
  }

  /// 在对应日志类别启用时输出信息级别日志。
  ///
  /// - [category]：日志所属功能分类；为空时使用 SDK 通用前缀。
  /// - [message]：完整消息文本。
  /// - [option]：控制本条日志是否输出的类别标志。省略时归入 business 日志类别。
  static void info({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(XmaxLogLevel.info, message, category: category, option: option);
  }

  /// 在对应日志类别启用时输出警告级别日志。
  ///
  /// - [category]：日志所属功能分类；为空时使用 SDK 通用前缀。
  /// - [message]：完整消息文本。
  /// - [option]：控制本条日志是否输出的类别标志。省略时归入 business 日志类别。
  static void warn({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(XmaxLogLevel.warning, message, category: category, option: option);
  }

  /// 在对应日志类别启用时输出错误级别日志。
  ///
  /// - [category]：日志所属功能分类；为空时使用 SDK 通用前缀。
  /// - [message]：完整消息文本。
  /// - [option]：控制本条日志是否输出的类别标志。省略时归入 business 日志类别。
  static void error({
    XmaxLoggerCategory? category,
    required String message,
    XmaxLoggerOption option = XmaxLoggerOption.business,
  }) {
    _write(XmaxLogLevel.error, message, category: category, option: option);
  }

  /// 为每一行日志添加 SDK 和可选功能分类前缀。
  ///
  /// - [category]：日志所属功能分类；为空时使用 SDK 通用前缀。
  /// - [message]：完整消息文本。
  ///
  /// 返回每行都包含 SDK 和功能分类前缀的日志文本。
  static String formattedMessage({
    XmaxLoggerCategory? category,
    required String message,
  }) {
    final prefix = category == null ? '[Xmax]' : '[Xmax][${category.value}]';

    return message.split('\n').map((line) => '$prefix $line').join('\n');
  }

  /// 按当前日志选项输出已格式化的日志。
  ///
  /// - [level]：当前日志的严重程度。
  /// - [message]：完整消息文本。
  /// - [category]：日志所属功能分类；为空时使用 SDK 通用前缀。
  /// - [option]：控制本条日志是否输出的类别标志。
  static void _write(
    XmaxLogLevel level,
    String message, {
    required XmaxLoggerCategory? category,
    required XmaxLoggerOption option,
  }) {
    if (!isEnabled(option)) {
      return;
    }

    _sink(level, formattedMessage(category: category, message: message));
  }

  /// 将格式化日志提交给运行时及可用的原生日志通道。
  ///
  /// - [level]：当前日志的严重程度。
  /// - [message]：完整消息文本。
  static void _defaultSink(
    XmaxLogLevel level,
    String message,
  ) {
    developer.log(message, name: 'ai.xmax.XmaxSDK', level: level.value);
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      debugPrint(message);

      return;
    }

    // 原生日志输出与业务操作独立。
    // 通过 loggerOptions 启用后，Profile 和 Release 模式也会输出日志。
    unawaited(_writeNative(level, message));
  }

  /// 通过方法通道输出原生日志；通道不可用时不影响业务调用。
  ///
  /// - [level]：当前日志的严重程度。
  /// - [message]：完整消息文本。
  static Future<void> _writeNative(
    XmaxLogLevel level,
    String message,
  ) async {
    try {
      await _channel.invokeMethod<void>('log', <String, String>{
        'level': level.name,
        'message': message,
      });
    } catch (_) {
      // 插件尚未注册或不可用时，改用 Dart 日志输出。
      // 日志自身出错时不再调用 SDK 错误处理，避免循环报错。
      debugPrint(message);
    }
  }

  /// 替换进程级日志输出函数。
  ///
  /// - [sink]：接收格式化日志的输出函数。
  @visibleForTesting
  static void setSink(
    XmaxLogSink sink,
  ) {
    _sink = sink;
  }

  /// 恢复默认日志配置和输出函数。
  @visibleForTesting
  static void reset() {
    _options = const XmaxLoggerOption(rawValue: 0);
    _environment = XmaxEnvironment.china;
    _sink = _defaultSink;
  }
}

/// SDK 日志所属的功能分类。
enum XmaxLoggerCategory {

  /// API 请求日志。
  api('API'),

  /// RTC 原生传输与性能日志。
  rtc('RTC'),

  /// 房间身份、心跳和信令日志。
  room('Room'),

  /// 媒体流发布、订阅、生成启动和质量调节日志。
  stream('Stream'),

  /// 文件上传下载及安全检查日志。
  storage('Storage'),

  /// 实时业务生命周期日志。
  realtime('Realtime'),

  /// 媒体采集及处理日志。
  media('Media'),

  /// 视频和轨迹渲染日志。
  render('Render'),

  /// 媒体权限检查日志。
  permission('Permission'),

  /// 触点交互日志。
  interaction('Interaction');

  /// 定义日志分类名称。
  const XmaxLoggerCategory(
    this.value,
  );

  /// 添加到日志前缀中的分类名称。
  final String value;
}

/// 日志的严重程度及系统日志等级。
enum XmaxLogLevel {

  /// 调试级别。
  debug(500),

  /// 信息级别。
  info(800),

  /// 警告级别。
  warning(900),

  /// 错误级别。
  error(1000);

  /// 定义系统日志优先级。
  const XmaxLogLevel(
    this.value,
  );

  /// 对应系统日志的整数优先级。
  final int value;
}

/// 接收已分类、已格式化日志的输出函数；实现方应避免记录凭证。
///
/// - [level]：当前日志的严重程度。
/// - [message]：完整消息文本。
typedef XmaxLogSink =
    void Function(
      XmaxLogLevel level,
      String message,
    );
