//
//  RuntimeInfo.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../../XmaxSDKInfo.dart';

/// 用于请求和房间信令的运行环境快照，包含系统、设备和 SDK 版本。
final class RuntimeInfo {

  /// 创建运行环境信息快照。
  const RuntimeInfo({
    required this.platform,
    required this.osVersion,
    required this.sdkVersion,
    required this.deviceModel,
  });

  /// 当前操作系统的标识。
  final String platform;

  /// 操作系统版本。
  final String osVersion;

  /// 当前 XmaxSDK 版本。
  final String sdkVersion;

  /// 设备型号；无法获取时为 unknown。
  final String deviceModel;

  /// 已缓存的运行环境快照。
  static RuntimeInfo current = RuntimeInfo(
    platform: Platform.operatingSystem,
    osVersion: Platform.isIOS || Platform.isAndroid
        ? 'unknown'
        : _currentOSVersion(),
    sdkVersion: XmaxSDKInfo.version,
    deviceModel: 'unknown',
  );

  /// 共享的运行环境读取任务。
  static Future<RuntimeInfo>? _resolution;

  /// 首次读取并缓存运行环境信息；读取失败使用回退值，不影响业务请求。
  ///
  /// 返回当前可用的运行环境快照。
  static Future<RuntimeInfo> resolve() => _resolution ??= _resolve();

  /// 读取设备信息并缓存运行环境；读取失败保留回退值。
  ///
  /// 返回当前可用的运行环境快照。
  static Future<RuntimeInfo> _resolve() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo.timeout(
          const Duration(seconds: 3),
        );

        current = RuntimeInfo(
          platform: 'ios',
          osVersion: _nonEmpty(info.systemVersion),
          sdkVersion: XmaxSDKInfo.version,
          deviceModel: _nonEmpty(info.utsname.machine),
        );
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo.timeout(
          const Duration(seconds: 3),
        );

        current = RuntimeInfo(
          platform: 'android',
          osVersion: _nonEmpty(info.version.release),
          sdkVersion: XmaxSDKInfo.version,
          deviceModel: _nonEmpty(info.model),
        );
      }
    } catch (_) {
      // 设备信息插件缺失或响应过慢时使用回退值，不能阻塞 API 请求和 RTC 信令。
    }

    return current;
  }

  /// 去除设备信息首尾空白，空白内容改为 unknown。
  ///
  /// - [value]：设备信息原始文本。
  static String _nonEmpty(
    String value,
  ) => value.trim().isEmpty ? 'unknown' : value.trim();

  /// 编码可提交给云端的运行环境字段。
  ///
  /// 返回可序列化的运行环境字段。
  Map<String, String> toJson() => <String, String>{
    'platform': platform,
    'os_version': osVersion,
    'sdk_version': sdkVersion,
    'device_model': deviceModel,
  };

  /// 从系统版本文本提取可提交的版本信息。
  ///
  /// 返回提取出的系统版本号；无法提取时使用系统版本文本。
  static String _currentOSVersion() {
    final version = Platform.operatingSystemVersion;
    final match = RegExp(r'\d+(?:\.\d+){1,2}').firstMatch(version);

    return match?.group(0) ?? version.trim();
  }
}
