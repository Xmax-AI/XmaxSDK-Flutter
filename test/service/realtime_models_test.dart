import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test('public enum values match iOS raw values', () {
    expect(RealtimeModel.x2_1_1_preview_cn.value, 'x2.1.1-preview-cn');
    expect(RealtimeModel.x2_1_1_preview_us.value, 'x2.1.1-preview-us');
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

  test('RealtimeModel follows iOS input and camera defaults', () {
    expect(RealtimeModel.values, <RealtimeModel>[
      RealtimeModel.x2_1_1_preview_cn,
      RealtimeModel.x2_1_1_preview_us,
    ]);
    expect(RealtimeModel.x2_1_1_preview_cn.resolutionBuckets, const [
      Size(1024, 1920),
      Size(1920, 1024),
    ]);
    expect(RealtimeModel.x2_1_1_preview_us.resolutionBuckets, const <Size>[
      Size(1024, 1920),
      Size(1920, 1024),
    ]);
    expect(RealtimeModel.x2_1_1_preview_cn.minimumInputPixels, 600000);
    expect(RealtimeModel.x2_1_1_preview_cn.maximumInputPixels, 2100000);
    expect(RealtimeModel.x2_1_1_preview_us.maximumInputPixels, 2100000);
    expect(RealtimeModel.x2_1_1_preview_cn.inputSizeAlignment, 32);
    expect(RealtimeModel.x2_1_1_preview_cn.defaultFrameRate, 30);
    expect(RealtimeModel.x2_1_1_preview_us.defaultFrameRate, 30);
    expect(
      RealtimeModel.x2_1_1_preview_cn.defaultCameraVideoFormat,
      const RealtimeVideoFormat(width: 1024, height: 1920, fps: 30),
    );
    expect(
      RealtimeModel.x2_1_1_preview_us.defaultCameraVideoFormat,
      const RealtimeVideoFormat(width: 1024, height: 1920, fps: 30),
    );
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
