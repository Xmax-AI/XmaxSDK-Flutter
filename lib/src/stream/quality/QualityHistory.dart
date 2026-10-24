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

import 'RealtimeQualityLevel.dart';

/// Stores successful quality levels for one hour, isolated by model and transport direction.
final class QualityHistory {

  /// Creates a model quality-level history store.
  ///
  /// Parameters:
  /// - [model]: The model used to isolate saved levels.
  /// - [preferences]: The preferences store; defaults to device-local preferences.
  QualityHistory(
    this.model, {
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences;

  /// The model identifier used to isolate quality-level history.
  final String model;

  /// The history preferences store; null uses device-local preferences.
  final SharedPreferencesAsync? _preferences;

  /// The device-local preferences used for quality history.
  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  /// Builds a preferences key isolated by model and transport direction.
  ///
  /// Parameters:
  /// - [downlink]: Whether to access downlink history; false means uplink.
  ///
  /// Returns a preferences key containing the model and transport direction.
  String _key(
    bool downlink,
  ) => 'xmax.quality.agora.$model.${downlink ? 'downlink' : 'uplink'}';

  /// Reads a successfully applied quality level from the last hour.
  ///
  /// Parameters:
  /// - [downlink]: Whether to read the downlink level; false means uplink.
  /// - [now]: The time used to check expiry; defaults to the system time.
  ///
  /// Returns level 2 if the record is missing, expired, or unreadable.
  Future<RealtimeQualityLevel> read({
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
        return RealtimeQualityLevel.values[level - 1];
      }
    } catch (_) {
      // Unavailable history must not block connection; use the default level.
    }

    return RealtimeQualityLevel.l2;
  }

  /// Saves the applied level and timestamp without interrupting media transport on storage failure.
  ///
  /// Parameters:
  /// - [level]: The successfully applied quality level, from 1 to 5.
  /// - [downlink]: Whether to save the downlink level; false means uplink.
  /// - [now]: The record timestamp; defaults to the system time.
  Future<void> write(
    RealtimeQualityLevel level, {
    required bool downlink,
    DateTime? now,
  }) async {
    try {
      final key = _key(downlink);

      await _store.setInt(
        key,
        level.value,
      ).timeout(const Duration(seconds: 1));
      await _store
          .setDouble(
            '$key.time',
            (now ?? DateTime.now()).millisecondsSinceEpoch / 1000,
          )
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // History is an optional optimization; persistence failures must not affect transport.
    }
  }
}
