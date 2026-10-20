import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/service/media/MediaService.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  for (final model in RealtimeModel.values) {
    final service = MediaService(model: model);
    test('${model.value} camera accepts only exact buckets', () {
      for (final size in const [Size(1024, 1920), Size(1920, 1024)]) {
        expect(
          service.resolveMediaSize(size, source: RealtimeMediaSource.camera),
          size,
        );
      }
      for (final size in const [
        Size(832, 1472),
        Size(1920, 1080),
        Size(1024, 1919.9),
        Size(double.nan, 1920),
      ]) {
        expect(
          () => service.resolveMediaSize(
            size,
            source: RealtimeMediaSource.camera,
          ),
          throwsA(isA<XmaxError>()),
        );
      }
    });
    test('${model.value} separates generation canvas from media size', () {
      expect(
        service.resolveGenerationSize(const Size(300, 500)),
        const Size(1024, 1920),
      );
      expect(
        service.resolveGenerationSize(const Size(500, 300)),
        const Size(1920, 1024),
      );
      expect(
        () => service.resolveGenerationSize(const Size(0, 300)),
        throwsA(isA<XmaxError>()),
      );
    });
  }
  test('target size keeps the exact aspect and respects fractional bounds', () {
    final service = MediaService();
    expect(
      service.resolveTargetSize(
        const Size(1024, 1920),
        maximumSize: const Size(819.2, 1536),
      ),
      const Size(800, 1500),
    );
    expect(
      service.resolveTargetSize(
        const Size(300, 500),
        maximumSize: const Size(1000, 1000),
      ),
      const Size(300, 500),
    );
    final size = service.resolveTargetSize(
      const Size(1001, 1501),
      maximumSize: const Size(700, 1000),
    );
    expect(size.width % 4, 0);
    expect(size.height % 4, 0);
    expect(size.width, lessThanOrEqualTo(700));
    expect(size.height, lessThanOrEqualTo(1000));
    expect(
      () => service.resolveTargetSize(
        const Size(1024, 1920),
        maximumSize: const Size(1, 1),
      ),
      throwsA(isA<XmaxError>()),
    );
  });
}
