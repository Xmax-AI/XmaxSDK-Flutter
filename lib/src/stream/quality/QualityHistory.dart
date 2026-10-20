//
//  QualityHistory.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:shared_preferences/shared_preferences.dart';

/// 按模型及传输方向保存一小时内成功应用的档位。
final class QualityHistory {

  /// 创建模型质量档位存储入口。
  ///
  /// - [model]：用于隔离历史档位的模型。
  /// - [preferences]：偏好存储；默认使用设备本地存储。
  QualityHistory(
    this.model, {
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences;

  /// 实时模型；用于确定会话路由及媒体规格约束。
  final String model;

  /// 档位历史的存储入口；为空时使用设备本地偏好存储。
  final SharedPreferencesAsync? _preferences;

  /// 用于档位历史的设备本地偏好存储。
  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  /// 构造按模型和上下行方向隔离的偏好存储键。
  ///
  /// - [downlink]：是否读写下行档位历史；false 表示上行。
  ///
  /// 返回包含模型及传输方向的偏好存储键。
  String _key(
    bool downlink,
  ) => 'xmax.quality.agora.$model.${downlink ? 'downlink' : 'uplink'}';

  /// 读取一小时内成功使用的质量档位。
  ///
  /// - [downlink]：是否读取下行档位；false 表示上行。
  /// - [now]：判断记录是否过期的时间，默认使用系统时间。
  ///
  /// 记录不存在、已过期或读取失败时，返回默认档位 2。
  Future<int> read({
    required bool downlink,
    DateTime? now,
  }) async {
    try {
      final key = _key(downlink);
      final level = await _store
          .getInt(key)
          .timeout(const Duration(seconds: 1));
      final saved = await _store
          .getDouble('$key.time')
          .timeout(const Duration(seconds: 1));
      final time = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;

      if (level != null &&
          level >= 1 &&
          level <= 5 &&
          saved != null &&
          saved > 0 &&
          time >= saved &&
          time - saved < 3600) {
        return level;
      }
    } catch (_) {
      // 历史不可用时使用默认档位，不阻断连接。
    }

    return 2;
  }

  /// 保存当前方向成功应用的档位和时间，存储失败不影响媒体传输。
  ///
  /// - [level]：已成功应用的质量档位，范围为 1～5。
  /// - [downlink]：是否保存下行档位；false 表示上行。
  /// - [now]：记录保存时间，默认使用系统时间。
  Future<void> write(
    int level, {
    required bool downlink,
    DateTime? now,
  }) async {
    try {
      final key = _key(downlink);

      await _store.setInt(key, level).timeout(const Duration(seconds: 1));
      await _store
          .setDouble(
            '$key.time',
            (now ?? DateTime.now()).millisecondsSinceEpoch / 1000,
          )
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // 档位历史属于可选优化，保存失败不影响当前传输。
    }
  }
}
