import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test('realtime routing is selected by environment rather than model', () {
    expect(
      XmaxEnvironment.china.realtimeApiBaseURL.toString(),
      'https://cloud.xmax.22duck.cn/open/api/v1',
    );
    expect(
      XmaxEnvironment.global.realtimeApiBaseURL.toString(),
      'https://api.xmax.ai/open/api/v1',
    );
    expect(RealtimeCameraPreset.values.map((preset) => preset.size), [
      const Size(1920, 1080),
      const Size(1080, 1920),
      const Size(1408, 1408),
      const Size(1152, 1536),
      const Size(1536, 1152),
    ]);
    expect(RealtimeQualityLevel.values.map((level) => level.value), [
      1,
      2,
      3,
      4,
      5,
    ]);
  });
  test('public enum values use the serialized API contract', () {
    expect(RealtimeModel.x2_1.value, 'x2.1');
    expect(CameraPosition.front.value, 'front');
    expect(VideoContentMode.fill.value, 'fill');
    expect(RealtimeConnectionState.generating.value, 'Generating');
    expect(RealtimeConnectionState.values.map((state) => state.value), <String>[
      'Idle',
      'Preparing',
      'Ready',
      'Connecting',
      'Connected',
      'Generating',
      'Disconnecting',
    ]);
    expect(RealtimeNetworkQualityLevel.veryBad.value, 'VeryBad');
    expect(RealtimePerformanceStatus.recovered.value, 'Recovered');
    expect(XmaxErrorCode.unsafeImage.value, 'UNSAFE_IMAGE');
  });

  test('RealtimeState reason follows the iOS value contract', () {
    const error = XmaxError(
      code: XmaxErrorCode.rtcError,
      message: 'RTC failed',
    );
    final failure = RealtimeReason.failure(error);

    expect(failure, RealtimeReason.failure(error));
    expect(failure.error, error);
    expect(RealtimeReason.normal.error, isNull);
    expect(RealtimeReason.orientationChanged, isNot(RealtimeReason.normal));
    expect(
      RealtimeState(
        connectionState: RealtimeConnectionState.ready,
        reason: failure,
      ),
      isNot(
        const RealtimeState(connectionState: RealtimeConnectionState.ready),
      ),
    );
  });

  test('RealtimeModel exposes only X2.1 and its supported capture formats', () {
    expect(RealtimeModel.values, [RealtimeModel.x2_1]);
    expect(RealtimeModel.values.map((model) => model.value), ['x2.1']);
    expect(RealtimeModel.values.map((model) => model.displayName), ['X2.1']);
    for (final model in RealtimeModel.values) {
      expect(
        model.supportedVideoFormats.map(
          (format) => Size(format.width.toDouble(), format.height.toDouble()),
        ),
        const [
          Size(1920, 1080),
          Size(1080, 1920),
          Size(1408, 1408),
          Size(1152, 1536),
          Size(1536, 1152),
        ],
      );
      expect(
        model.supportedVideoFormats.map((format) => format.fps),
        everyElement(30),
      );
      expect(
        model.supportedVideoFormats.map(
          (format) => Size(format.width.toDouble(), format.height.toDouble()),
        ),
        RealtimeCameraPreset.values.map((preset) => preset.size),
      );
      expect(model.minimumInputPixels, 200000);
      expect(model.maximumInputPixels, 2100000);
      expect(model.inputSizeAlignment, 32);
      expect(model.defaultFrameRate, 30);
      expect(
        model.defaultCameraVideoFormat,
        const RealtimeVideoFormat(width: 1080, height: 1920, fps: 30),
      );
    }
  });

  test('RealtimeContext normalizes prompt and reference path', () {
    expect(
      RealtimeContext(prompt: '  dress  ', referencePath: '  /image.png  '),
      RealtimeContext(prompt: 'dress', referencePath: '/image.png'),
    );
    expect(
      RealtimeContext(prompt: 'test', referencePath: ' ').referencePath,
      isNull,
    );
  });

  test('RealtimeVideoFormat validates positive even dimensions and fps', () {
    expect(
      const RealtimeVideoFormat(width: 768, height: 1024, fps: 24).validate,
      returnsNormally,
    );

    for (final format in <RealtimeVideoFormat>[
      const RealtimeVideoFormat(width: 0, height: 1024, fps: 24),
      const RealtimeVideoFormat(width: 767, height: 1024, fps: 24),
      const RealtimeVideoFormat(width: 768, height: 1023, fps: 24),
      const RealtimeVideoFormat(width: 768, height: 1024, fps: 0),
    ]) {
      expect(
        format.validate,
        throwsA(
          isA<XmaxError>().having(
            (error) => error.code,
            'code',
            XmaxErrorCode.invalidConfiguration,
          ),
        ),
      );
    }
  });

  test(
    'RealtimeVideoFormat validates bitrates and preserves encoding on resize',
    () {
      const format = RealtimeVideoFormat(
        width: 832,
        height: 1472,
        fps: 30,
        minimumBitrate: 1000,
        maximumBitrate: 3000,
        encoderPreference: RealtimeVideoEncoderPreference.maintainQuality,
      );
      expect(format.validate, returnsNormally);
      expect(
        format.resized(width: 1024, height: 1920),
        const RealtimeVideoFormat(
          width: 1024,
          height: 1920,
          fps: 30,
          minimumBitrate: 1000,
          maximumBitrate: 3000,
          encoderPreference: RealtimeVideoEncoderPreference.maintainQuality,
        ),
      );
      expect(
        format,
        isNot(const RealtimeVideoFormat(width: 832, height: 1472, fps: 30)),
      );

      for (final invalid in <RealtimeVideoFormat>[
        const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 30,
          minimumBitrate: -1,
        ),
        const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 30,
          maximumBitrate: 0,
        ),
        const RealtimeVideoFormat(
          width: 832,
          height: 1472,
          fps: 30,
          minimumBitrate: 3001,
          maximumBitrate: 3000,
        ),
      ]) {
        expect(invalid.validate, throwsA(isA<XmaxError>()));
      }
    },
  );
}
