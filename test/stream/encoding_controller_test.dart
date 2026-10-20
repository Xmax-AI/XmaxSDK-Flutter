import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcManaging.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcModels.dart';
import 'package:xmax_sdk/src/stream/encoding/EncodingController.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
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
      (2, 2, 1, 100),
    ]) {
      await controller.configure(
        RealtimeVideoFormat(width: width, height: height, fps: fps),
      );
      expect(rtc.configuration!.minimumBitrate, 100);
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
      (100, 4000),
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
