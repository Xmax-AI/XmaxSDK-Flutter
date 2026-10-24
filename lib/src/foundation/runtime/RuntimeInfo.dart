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

/// A runtime snapshot for requests and room signaling, including OS, device, and SDK versions.
final class RuntimeInfo {

  /// Creates a runtime information snapshot.
  const RuntimeInfo({
    required this.platform,
    required this.osVersion,
    required this.sdkVersion,
    required this.deviceModel,
  });

  /// The current operating system identifier.
  final String platform;

  /// The operating system version.
  final String osVersion;

  /// The current XmaxSDK version.
  final String sdkVersion;

  /// The device model; unknown if unavailable.
  final String deviceModel;

  /// The cached runtime snapshot.
  static RuntimeInfo current = RuntimeInfo(
    platform: Platform.operatingSystem,
    osVersion: Platform.isIOS || Platform.isAndroid
        ? 'unknown'
        : _currentOSVersion(),
    sdkVersion: XmaxSDKInfo.version,
    deviceModel: 'unknown',
  );

  /// The shared runtime information read operation.
  static Future<RuntimeInfo>? _resolution;

  /// Reads and caches runtime information, using fallback values on failure without disrupting
  /// requests.
  ///
  /// Returns the available runtime snapshot.
  static Future<RuntimeInfo> resolve() => _resolution ??= _resolve();

  /// Reads device information and caches the runtime snapshot, retaining fallback values on
  /// failure.
  ///
  /// Returns the available runtime snapshot.
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
      // Use fallback values if device information is unavailable or slow; do not block API or RTC signaling.
    }

    return current;
  }

  /// Trims device information and replaces blank values with unknown.
  ///
  /// Parameters:
  /// - [value]: The raw device information text.
  static String _nonEmpty(
    String value,
  ) => value.trim().isEmpty ? 'unknown' : value.trim();

  /// Encodes runtime fields for cloud requests.
  ///
  /// Returns serializable runtime fields.
  Map<String, String> toJson() => <String, String>{
    'platform': platform,
    'os_version': osVersion,
    'sdk_version': sdkVersion,
    'device_model': deviceModel,
  };

  /// Extracts a reportable version from the operating system version text.
  ///
  /// Returns the extracted OS version, falling back to the original system version text.
  static String _currentOSVersion() {
    final version = Platform.operatingSystemVersion;
    final match = RegExp(r'\d+(?:\.\d+){1,2}').firstMatch(version);

    return match?.group(0) ?? version.trim();
  }
}
