import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionService.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test(
    'credentials require RTC identity, bot and matching application',
    () async {
      const extra = {
        'room_id': 'room',
        'room_token': 'token',
        'rtc_user_id': 'rtc-user',
        'rtc_bot_id': 'bot',
        'rtc_app_id': '5588dfe2e7874bd08ea28f4968ec2d40',
      };
      for (final key in extra.keys) {
        final api = _RecordingApiService()
          ..modelExtra = (Map<String, String>.of(extra)..remove(key));
        await expectLater(
          RealtimeSessionService(
            apiService: api,
          ).createSession(model: RealtimeModel.x2_1),
          throwsA(
            isA<XmaxError>().having(
              (error) => error.code,
              'code',
              XmaxErrorCode.sessionError,
            ),
          ),
        );
      }
      final invalid = _RecordingApiService()
        ..modelExtra = {...extra, 'rtc_app_id': 'other-app'};
      await expectLater(
        RealtimeSessionService(
          apiService: invalid,
        ).createSession(model: RealtimeModel.x2_1),
        throwsA(isA<XmaxError>()),
      );
      final valid = _RecordingApiService()..modelExtra = jsonEncode(extra);
      final session = await RealtimeSessionService(
        apiService: valid,
      ).createSession(model: RealtimeModel.x2_1);
      expect(session.connection!.userID, 'rtc-user');
      expect(session.connection!.botName, 'bot');
    },
  );
  test('x2.0-pro session request sends the iOS model identifier', () async {
    final api = _RecordingApiService();
    final service = RealtimeSessionService(apiService: api);

    final session = await service.createSession(
      model: RealtimeModel.x2_1,
    );

    expect(api.method, ApiMethod.post);
    expect(api.path, '/session');
    expect(api.body, <String, Object?>{'model': 'x2.1'});
    expect(session.id, 'session-pro');
  });
}

final class _RecordingApiService implements ApiServicing {
  Object? modelExtra;
  ApiMethod? method;
  String? path;
  Object? body;

  @override
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(Object? json) decode,
  }) async {
    this.method = method;
    this.path = path;
    this.body = body;
    return decode(<String, Object?>{
      'sessionUid': 'session-pro',
      'userUid': 'user-pro',
      'modelExtra':
          modelExtra ??
          <String, String>{
            'room_id': 'room-pro',
            'room_token': 'token-pro',
            'rtc_user_id': 'user-pro',
            'rtc_bot_id': 'bot',
            'rtc_app_id': '5588dfe2e7874bd08ea28f4968ec2d40',
          },
    });
  }
}
