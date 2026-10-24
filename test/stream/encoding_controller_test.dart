import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/VideoEncodingConfiguration.dart';
import 'package:xmax_sdk/src/stream/encoding/EncodingController.dart';
import 'package:xmax_sdk/src/stream/quality/QualityVideoFormat.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test(
    'encoder rejects non-four-aligned dimensions before native calls',
    () async {
      final rtc = _Rtc();
      final controller = EncodingController(rtcManager: rtc);
      for (final (width, height) in [
        (912, 1710),
        (528, 990),
        (1282, 720),
        (2, 2),
      ]) {
        await expectLater(
          controller.configure(
            RealtimeVideoFormat(width: width, height: height, fps: 30),
          ),
          throwsA(
            isA<XmaxError>().having(
              (error) => error.code,
              'code',
              XmaxErrorCode.invalidConfiguration,
            ),
          ),
        );
      }
      expect(rtc.configuration, isNull);
    },
  );

  test('all model uplink tiers can be applied with the minimum area', () async {
    final rtc = _Rtc();
    final controller = EncodingController(rtcManager: rtc);
    for (final model in RealtimeModel.values) {
      for (final baseline in model.supportedVideoFormats) {
        for (final level in RealtimeQualityLevel.values) {
          final format = QualityVideoFormat.resolve(
            baseline,
            level,
            downlink: false,
            minimumInputPixels: model.minimumInputPixels,
          );
          await controller.configure(format);
          expect(rtc.configuration!.width, format.width);
          expect(rtc.configuration!.height, format.height);
          expect(rtc.configuration!.frameRate, format.fps);
          expect(format.width * format.height, greaterThanOrEqualTo(500000));
        }
      }
    }
  });

  test(
    'explicit zero minimum disables the floor and default minimum respects a low maximum',
    () async {
      final rtc = _Rtc();
      final encoder = EncodingController(rtcManager: rtc);
      await encoder.configure(
        const RealtimeVideoFormat(
          width: 1080,
          height: 1920,
          fps: 30,
          minimumBitrate: 0,
          maximumBitrate: 3000,
        ),
      );
      expect(rtc.configuration!.minimumBitrate, 0);
      await encoder.configure(
        const RealtimeVideoFormat(
          width: 1080,
          height: 1920,
          fps: 30,
          maximumBitrate: 300,
        ),
      );
      expect(rtc.configuration!.minimumBitrate, 300);
    },
  );
  test('default video budgets match the transport reference values', () async {
    final rtc = _Rtc(), encoder = EncodingController(rtcManager: _Rtc());
    final controller = EncodingController(rtcManager: rtc);
    for (final (width, height, fps, maximum) in [
      (1920, 1080, 30, 3780),
      (1920, 1080, 24, 3266),
      (832, 1472, 24, 2166),
      (1024, 1920, 30, 3619),
      (1024, 1920, 24, 3127),
      (1024, 768, 30, 1820),
      (3840, 2160, 30, 15120),
      (120, 120, 30, 100),
      (4, 4, 1, 100),
    ]) {
      await controller.configure(
        RealtimeVideoFormat(width: width, height: height, fps: fps),
      );
      expect(rtc.configuration!.minimumBitrate, maximum < 500 ? maximum : 500);
      expect(
        rtc.configuration!.encoderPreference,
        RealtimeVideoEncoderPreference.maintainFramerate,
      );
      expect(
        rtc.configuration!.maximumBitrate,
        maximum,
        reason: '$width×$height@$fps',
      );
    }
    await expectLater(
      encoder.configure(
        const RealtimeVideoFormat(
          width: 1099511627776,
          height: 1099511627776,
          fps: 60,
        ),
      ),
      throwsA(isA<XmaxError>()),
    );
  });
  test('explicit bounds and encoder preference are preserved', () async {
    final rtc = _Rtc(), controller = EncodingController(rtcManager: _Rtc());
    final encoder = EncodingController(rtcManager: rtc);
    await encoder.configure(
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        minimumBitrate: 1500,
        maximumBitrate: 3000,
        encoderPreference: RealtimeVideoEncoderPreference.maintainQuality,
      ),
    );
    expect(
      (rtc.configuration!.minimumBitrate, rtc.configuration!.maximumBitrate),
      (1500, 3000),
    );
    expect(
      rtc.configuration!.encoderPreference,
      RealtimeVideoEncoderPreference.maintainQuality,
    );
    await encoder.configure(
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        maximumBitrate: 4000,
      ),
    );
    expect(
      (rtc.configuration!.minimumBitrate, rtc.configuration!.maximumBitrate),
      (500, 4000),
    );
    await encoder.configure(
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        minimumBitrate: 1000,
      ),
    );
    expect(
      (rtc.configuration!.minimumBitrate, rtc.configuration!.maximumBitrate),
      (1000, 3619),
    );
    for (final format in [
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        minimumBitrate: -1,
      ),
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        maximumBitrate: 0,
      ),
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        maximumBitrate: 50,
      ),
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        minimumBitrate: 5000,
      ),
      const RealtimeVideoFormat(
        width: 1024,
        height: 1920,
        fps: 30,
        minimumBitrate: 3000,
        maximumBitrate: 1500,
      ),
    ]) {
      await expectLater(
        controller.configure(format),
        throwsA(isA<XmaxError>()),
      );
    }
  });
}

class _Rtc implements RtcManaging {
  VideoEncodingConfiguration? configuration;
  @override
  Future<void> configureVideoEncoding(
    VideoEncodingConfiguration configuration,
  ) async => this.configuration = configuration;
  @override
  dynamic noSuchMethod(Invocation call) => super.noSuchMethod(call);
}
