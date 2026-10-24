import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test(
    'realtime adaptation defaults on and participates in value equality',
    () {
      const enabled = RealtimeConfiguration(
        model: RealtimeModel.x2_1_1_preview_cn,
      );
      const same = RealtimeConfiguration(
        model: RealtimeModel.x2_1_1_preview_cn,
        isAdaptiveQualityEnabled: true,
      );
      const disabled = RealtimeConfiguration(
        model: RealtimeModel.x2_1_1_preview_cn,
        isAdaptiveQualityEnabled: false,
      );
      expect(enabled.isAdaptiveQualityEnabled, isTrue);
      expect(enabled, same);
      expect(enabled.hashCode, same.hashCode);
      expect(enabled, isNot(disabled));
      expect(
        enabled,
        isNot(
          const RealtimeConfiguration(model: RealtimeModel.x2_1_1_preview_us),
        ),
      );
    },
  );

  test('XmaxConfiguration trims and validates API key', () {
    final configuration = XmaxConfiguration(apiKey: '  key-123 \n');

    expect(configuration.apiKey, 'key-123');
    expect(configuration.environment, XmaxEnvironment.china);
    expect(configuration.validate, returnsNormally);
  });

  test('XmaxEnvironment matches iOS service regions', () {
    expect(XmaxEnvironment.values, <XmaxEnvironment>[
      XmaxEnvironment.china,
      XmaxEnvironment.global,
    ]);
    expect(
      XmaxConfiguration(apiKey: 'key', environment: XmaxEnvironment.global),
      isNot(XmaxConfiguration(apiKey: 'key')),
    );
  });

  test('XmaxConfiguration rejects an empty API key', () {
    final configuration = XmaxConfiguration(apiKey: ' \n ');

    expect(
      configuration.validate,
      throwsA(
        isA<XmaxError>()
            .having((error) => error.code, 'code', XmaxErrorCode.invalidAPIKey)
            .having(
              (error) => error.message,
              'message',
              'API key cannot be empty',
            ),
      ),
    );
  });

  test('XmaxLoggerOption keeps iOS bit values', () {
    expect(XmaxLoggerOption.business.rawValue, 1);
    expect(XmaxLoggerOption.performance.rawValue, 2);
    expect(XmaxLoggerOption.all.rawValue, 3);
    expect(
      (XmaxLoggerOption.business | XmaxLoggerOption.performance),
      XmaxLoggerOption.all,
    );
  });
}
