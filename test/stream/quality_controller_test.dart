import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/src/stream/quality/QualityDirection.dart';
import 'package:xmax_sdk/src/stream/quality/QualityHistory.dart';
import 'package:xmax_sdk/src/stream/quality/QualityVideoFormat.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

const _baseline = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({}),
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  test(
    'three poor samples downgrade, five good samples upgrade after stability',
    () {
      final direction = QualityDirection(
        baseline: _baseline,
        level: 2,
        downlink: false,
      );
      expect(
        direction.observe(
          RealtimeNetworkQualityLevel.bad,
          sampledAt: 1,
          now: 1,
        ),
        isNull,
      );
      expect(
        direction.observe(
          RealtimeNetworkQualityLevel.bad,
          sampledAt: 2,
          now: 2,
        ),
        isNull,
      );
      expect(
        direction.observe(
          RealtimeNetworkQualityLevel.bad,
          sampledAt: 3,
          now: 3,
        ),
        3,
      );
      direction.complete(3, success: true, now: 3);
      expect(
        direction.observe(
          RealtimeNetworkQualityLevel.good,
          sampledAt: 4,
          now: 4,
        ),
        isNull,
      );
      for (var t = 7; t < 11; t++) {
        expect(
          direction.observe(
            RealtimeNetworkQualityLevel.good,
            sampledAt: t.toDouble(),
            now: t.toDouble(),
          ),
          isNull,
        );
      }
      expect(
        direction.observe(
          RealtimeNetworkQualityLevel.good,
          sampledAt: 11,
          now: 11,
        ),
        2,
      );
      direction.complete(2, success: true, now: 11);
      for (var t = 15; t < 17; t++) {
        expect(
          direction.observe(
            RealtimeNetworkQualityLevel.bad,
            sampledAt: t.toDouble(),
            now: t.toDouble(),
          ),
          isNull,
        );
      }
      expect(
        direction.observe(
          RealtimeNetworkQualityLevel.bad,
          sampledAt: 17,
          now: 17,
        ),
        3,
      );
      direction.complete(3, success: true, now: 17);
      for (var t = 21; t < 29; t++) {
        expect(
          direction.observe(
            RealtimeNetworkQualityLevel.good,
            sampledAt: t.toDouble(),
            now: t.toDouble(),
          ),
          isNull,
        );
      }
      expect(direction.level, 3);
    },
  );
  test('stale, repeated and interrupted samples do not trigger changes', () {
    final direction = QualityDirection(
      baseline: _baseline,
      level: 2,
      downlink: true,
    );
    direction.observe(RealtimeNetworkQualityLevel.bad, sampledAt: 1, now: 1);
    direction.observe(RealtimeNetworkQualityLevel.bad, sampledAt: 2, now: 2);
    expect(
      direction.observe(RealtimeNetworkQualityLevel.bad, sampledAt: 2, now: 2),
      isNull,
    );
    expect(
      direction.observe(RealtimeNetworkQualityLevel.bad, sampledAt: 8, now: 8),
      isNull,
    );
    expect(
      direction.observe(RealtimeNetworkQualityLevel.bad, sampledAt: 9, now: 16),
      isNull,
    );
    expect(direction.level, 2);
    direction.complete(3, success: false, now: 16);
    expect(direction.level, 2);
  });
  test(
    'quality adjusts transmission while preserving source and explicit budgets',
    () {
      final format = QualityVideoFormat.resolve(_baseline, 2, downlink: false);
      expect((format.width, format.height, format.fps), (816, 1530, 24));
      expect(_baseline.width, 1024);
      expect(QualityVideoFormat.resolve(_baseline, 5, downlink: true).fps, 24);
      final small = QualityVideoFormat.resolve(
        const RealtimeVideoFormat(width: 200, height: 200, fps: 10),
        5,
        downlink: false,
      );
      expect((small.width, small.height, small.fps), (200, 200, 10));
    },
  );
  test(
    'quality history is model isolated and expires after one hour',
    () async {
      final preferences = _Preferences();
      final now = DateTime.fromMillisecondsSinceEpoch(10000000);
      final cn = QualityHistory('cn', preferences: preferences),
          us = QualityHistory('us', preferences: preferences);
      expect(await cn.read(downlink: false, now: now), 2);
      await cn.write(4, downlink: false, now: now);
      expect(await cn.read(downlink: false, now: now), 4);
      expect(await cn.read(downlink: true, now: now), 2);
      expect(await us.read(downlink: false, now: now), 2);
      expect(
        await cn.read(downlink: false, now: now.add(const Duration(hours: 1))),
        2,
      );
      expect(
        await cn.read(
          downlink: false,
          now: now.subtract(const Duration(seconds: 1)),
        ),
        2,
      );
    },
  );
}

class _Preferences extends SharedPreferencesAsync {
  final data = <String, Object>{};
  @override
  Future<int?> getInt(String key) async => data[key] as int?;
  @override
  Future<double?> getDouble(String key) async => data[key] as double?;
  @override
  Future<void> setInt(String key, int value) async {
    data[key] = value;
  }

  @override
  Future<void> setDouble(String key, double value) async {
    data[key] = value;
  }
}
