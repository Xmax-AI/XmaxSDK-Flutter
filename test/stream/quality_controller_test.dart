import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/src/stream/quality/QualityDirection.dart';
import 'package:xmax_sdk/src/stream/quality/QualityController.dart';
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
    'disabled adaptation ignores history and manual changes do not persist',
    () async {
      const model = 'x2.1.1-preview-cn';
      final history = QualityHistory(model);
      await history.write(RealtimeQualityLevel.l4, downlink: false);
      await history.write(RealtimeQualityLevel.l5, downlink: true);
      final controller = QualityController();
      await controller.prepareQuality(
        baseline: _baseline,
        model: model,
        minimumInputPixels: 500000,
        isAdaptiveQualityEnabled: false,
      );
      expect(
        controller.qualityConfiguration!.uplinkLevel,
        RealtimeQualityLevel.l1,
      );
      expect(
        controller.qualityConfiguration!.downlinkLevel,
        RealtimeQualityLevel.l1,
      );
      expect(controller.qualityConfiguration!.minimumInputPixels, 500000);
      await controller.completeQuality(
        RealtimeQualityLevel.l3,
        downlink: false,
        success: true,
        now: 0,
      );
      expect(
        controller.qualityConfiguration!.uplinkLevel,
        RealtimeQualityLevel.l3,
      );
      expect(await history.read(downlink: false), RealtimeQualityLevel.l4);
      controller.resetQuality();
      await controller.prepareQuality(baseline: _baseline, model: model);
      expect(
        controller.qualityConfiguration!.uplinkLevel,
        RealtimeQualityLevel.l4,
      );
      expect(
        controller.qualityConfiguration!.downlinkLevel,
        RealtimeQualityLevel.l5,
      );
    },
  );

  for (final model in RealtimeModel.values) {
    test(
      '${model.value} uplink tiers retain the minimum area and alignment',
      () {
        for (final baseline in model.supportedVideoFormats) {
          for (final level in RealtimeQualityLevel.values) {
            final format = QualityVideoFormat.resolve(
              baseline,
              level,
              downlink: false,
              minimumInputPixels: model.minimumInputPixels,
            );
            expect(format.width % 4, 0);
            expect(format.height % 4, 0);
            expect(
              format.width * format.height,
              greaterThanOrEqualTo(model.minimumInputPixels),
            );
            expect(format.width, lessThanOrEqualTo(baseline.width));
            expect(format.height, lessThanOrEqualTo(baseline.height));
            expect(
              format.width * baseline.height,
              format.height * baseline.width,
            );
            expect(format.fps, lessThanOrEqualTo(baseline.fps));
          }
          final l5 = QualityVideoFormat.resolve(
            baseline,
            RealtimeQualityLevel.l5,
            downlink: false,
            minimumInputPixels: model.minimumInputPixels,
          );
          expect(l5.width, baseline.width ~/ 2);
          expect(l5.height, baseline.height ~/ 2);
          expect(l5.width * l5.height, 491520);
          expect(l5.fps, 16);
          final down = QualityVideoFormat.resolve(
            baseline,
            RealtimeQualityLevel.l5,
            downlink: true,
            minimumInputPixels: model.minimumInputPixels,
          );
          expect(down.width * down.height, 491520);
          expect(down.fps, 24);
        }
      },
    );
  }

  test('uplink alignment fallback honors the area floor without upscaling', () {
    for (final baseline in [
      const RealtimeVideoFormat(width: 1004, height: 600, fps: 30),
      const RealtimeVideoFormat(width: 600, height: 1004, fps: 30),
      const RealtimeVideoFormat(width: 512, height: 960, fps: 30),
    ]) {
      for (final level in RealtimeQualityLevel.values) {
        final format = QualityVideoFormat.resolve(
          baseline,
          level,
          downlink: false,
          minimumInputPixels: 500000,
        );
        expect(format.width % 4, 0);
        expect(format.height % 4, 0);
        expect(format.width, lessThanOrEqualTo(baseline.width));
        expect(format.height, lessThanOrEqualTo(baseline.height));
        expect(
          format.width * format.height,
          greaterThanOrEqualTo(
            baseline.width * baseline.height < 500000
                ? baseline.width * baseline.height
                : 500000,
          ),
        );
      }
    }
  });

  test(
    'manual completion preserves automatic adaptation and commits only accepted levels',
    () async {
      final controller = QualityController();
      await controller.prepareQuality(baseline: _baseline, model: 'x2.1');
      await controller.completeQuality(
        RealtimeQualityLevel.l1,
        downlink: false,
        success: true,
        now: 0,
      );
      for (var now = 5; now <= 7; now++) {
        final change = controller.proposeQuality(
          const RealtimeNetworkQuality(
            uplink: RealtimeNetworkQualityLevel.bad,
            downlink: RealtimeNetworkQualityLevel.unknown,
          ),
          now.toDouble(),
        );
        expect(change.uplink, now == 7 ? RealtimeQualityLevel.l2 : isNull);
      }
      expect(
        controller.qualityConfiguration!.uplinkLevel,
        RealtimeQualityLevel.l1,
      );
      await controller.completeQuality(
        RealtimeQualityLevel.l2,
        downlink: false,
        success: false,
        now: 7,
      );
      expect(
        controller.qualityConfiguration!.uplinkLevel,
        RealtimeQualityLevel.l1,
      );
      expect(
        await QualityHistory('x2.1').read(downlink: false),
        RealtimeQualityLevel.l1,
      );
      controller.resetQuality();
      expect(controller.qualityConfiguration, isNull);
    },
  );
  test(
    'three poor samples downgrade, five good samples upgrade after stability',
    () {
      final direction = QualityDirection(
        baseline: _baseline,
        level: RealtimeQualityLevel.l2,
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
        RealtimeQualityLevel.l3,
      );
      direction.complete(RealtimeQualityLevel.l3, success: true, now: 3);
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
        RealtimeQualityLevel.l2,
      );
      direction.complete(RealtimeQualityLevel.l2, success: true, now: 11);
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
        RealtimeQualityLevel.l3,
      );
      direction.complete(RealtimeQualityLevel.l3, success: true, now: 17);
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
      expect(direction.level, RealtimeQualityLevel.l3);
    },
  );
  test('stale, repeated and interrupted samples do not trigger changes', () {
    final direction = QualityDirection(
      baseline: _baseline,
      level: RealtimeQualityLevel.l2,
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
    expect(direction.level, RealtimeQualityLevel.l2);
    direction.complete(RealtimeQualityLevel.l3, success: false, now: 16);
    expect(direction.level, RealtimeQualityLevel.l2);
  });
  test(
    'quality adjusts transmission while preserving source and explicit budgets',
    () {
      final format = QualityVideoFormat.resolve(
        _baseline,
        RealtimeQualityLevel.l2,
        downlink: false,
      );
      expect((format.width, format.height, format.fps), (896, 1680, 24));
      expect(_baseline.width, 1024);
      expect(
        QualityVideoFormat.resolve(
          _baseline,
          RealtimeQualityLevel.l5,
          downlink: true,
        ).fps,
        24,
      );
      final small = QualityVideoFormat.resolve(
        const RealtimeVideoFormat(width: 200, height: 200, fps: 10),
        RealtimeQualityLevel.l5,
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
      expect(await cn.read(downlink: false, now: now), RealtimeQualityLevel.l2);
      await cn.write(RealtimeQualityLevel.l4, downlink: false, now: now);
      expect(await cn.read(downlink: false, now: now), RealtimeQualityLevel.l4);
      expect(await cn.read(downlink: true, now: now), RealtimeQualityLevel.l2);
      expect(await us.read(downlink: false, now: now), RealtimeQualityLevel.l2);
      expect(
        await cn.read(downlink: false, now: now.add(const Duration(hours: 1))),
        RealtimeQualityLevel.l2,
      );
      expect(
        await cn.read(
          downlink: false,
          now: now.subtract(const Duration(seconds: 1)),
        ),
        RealtimeQualityLevel.l2,
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
