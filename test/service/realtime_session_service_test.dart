import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionService.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test(
    'stopping heartbeat aborts the in-flight request without reporting a stale failure',
    () async {
      final api = _RecordingApiService();
      final started = Completer<void>();
      final cancelled = Completer<void>();
      api.onHeartbeat = (cancellation) async {
        expect(cancellation, isNotNull);
        started.complete();
        await cancellation;
        cancelled.complete();
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'cancelled',
        );
      };
      final service = RealtimeSessionService(
        apiService: api,
        heartbeatInterval: const Duration(milliseconds: 5),
      );
      var failures = 0;
      service.startHeartbeat(
        sessionID: 'session',
        onFailure: (_, _) async => failures++,
      );
      await started.future;
      service.stopHeartbeat();
      await cancelled.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(failures, 0);
    },
  );
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
  for (final model in RealtimeModel.values) {
    test(
      '${model.value} session request sends the selected model identifier',
      () async {
        final api = _RecordingApiService();
        final service = RealtimeSessionService(apiService: api);

        final session = await service.createSession(model: model);

        expect(api.method, ApiMethod.post);
        expect(api.path, '/session');
        expect(api.body, <String, Object?>{'model': model.value});
        expect(session.id, 'session-pro');
      },
    );
  }
}

final class _RecordingApiService implements ApiServicing {
  Future<void> Function(Future<void>?)? onHeartbeat;
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
    Future<void>? cancellation,
  }) async {
    if (path.endsWith('/heartbeat')) await onHeartbeat?.call(cancellation);
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
