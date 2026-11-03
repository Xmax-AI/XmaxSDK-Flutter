import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeSessionService.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  testWidgets(
    'first heartbeat is immediate and startup allowance appears only once',
    (tester) async {
      final api = _RecordingApiService();
      final service = RealtimeSessionService(apiService: api);
      addTearDown(service.stopHeartbeat);
      service.startHeartbeat(
        sessionID: 'session',
        firstHeartbeatGraceSeconds: 4,
        onFailure: (_, error) async =>
            fail('Unexpected heartbeat error: $error'),
      );
      expect(api.requests, isEmpty);
      await tester.pump();
      expect(api.requests, hasLength(1));
      expect(api.requests.single.method, ApiMethod.put);
      expect(api.requests.single.path, '/session/session/heartbeat');
      expect(api.requests.single.body, {'firstHeartbeatGraceSeconds': 4});
      await tester.pump(const Duration(seconds: 9));
      expect(api.requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests, hasLength(2));
      expect(api.requests.last, (
        method: ApiMethod.put,
        path: '/session/session/heartbeat',
        body: null,
      ));
      await tester.pump(const Duration(seconds: 10));
      expect(api.requests, hasLength(3));
      expect(api.requests.last.body, isNull);
      service.stopHeartbeat();
    },
  );

  for (final seconds in <int?>[0, null]) {
    testWidgets('first heartbeat preserves a startup allowance of $seconds', (
      tester,
    ) async {
      final api = _RecordingApiService();
      final service = RealtimeSessionService(apiService: api);
      addTearDown(service.stopHeartbeat);
      service.startHeartbeat(
        sessionID: 'session',
        firstHeartbeatGraceSeconds: seconds,
        onFailure: (_, error) async =>
            fail('Unexpected heartbeat error: $error'),
      );
      await tester.pump();
      expect(api.requests, hasLength(1));
      expect(
        api.requests.single.body,
        seconds == null ? null : {'firstHeartbeatGraceSeconds': 0},
      );
      service.stopHeartbeat();
    });
  }

  testWidgets('stopping before the first heartbeat prevents the request', (
    tester,
  ) async {
    final api = _RecordingApiService();
    final service = RealtimeSessionService(apiService: api);
    service.startHeartbeat(
      sessionID: 'session',
      firstHeartbeatGraceSeconds: 2,
      onFailure: (_, error) async => fail('Unexpected heartbeat error: $error'),
    );
    service.stopHeartbeat();
    await tester.pump(const Duration(seconds: 30));
    expect(api.requests, isEmpty);
  });

  testWidgets(
    'replacement before the first heartbeat sends only the latest allowance',
    (tester) async {
      final api = _RecordingApiService();
      final service = RealtimeSessionService(apiService: api);
      addTearDown(service.stopHeartbeat);
      for (final (id, seconds) in [('old', 3), ('new', 7)]) {
        service.startHeartbeat(
          sessionID: id,
          firstHeartbeatGraceSeconds: seconds,
          onFailure: (_, error) async =>
              fail('Unexpected heartbeat error: $error'),
        );
      }
      await tester.pump();
      expect(api.requests, hasLength(1));
      expect(api.requests.single.method, ApiMethod.put);
      expect(api.requests.single.path, '/session/new/heartbeat');
      expect(api.requests.single.body, {'firstHeartbeatGraceSeconds': 7});
      await tester.pump(const Duration(seconds: 10));
      expect(api.requests, hasLength(2));
      expect(api.requests.last, (
        method: ApiMethod.put,
        path: '/session/new/heartbeat',
        body: null,
      ));
      service.stopHeartbeat();
    },
  );

  testWidgets(
    'slow heartbeats never overlap and intervals begin after completion',
    (tester) async {
      final api = _RecordingApiService();
      final response = Completer<void>();
      api.onHeartbeat = (_) => response.future;
      final service = RealtimeSessionService(apiService: api);
      addTearDown(service.stopHeartbeat);
      service.startHeartbeat(
        sessionID: 'session',
        firstHeartbeatGraceSeconds: 5,
        onFailure: (_, error) async =>
            fail('Unexpected heartbeat error: $error'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(api.requests, hasLength(1));
      response.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(api.requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests, hasLength(2));
      expect(api.requests.last.body, isNull);
      service.stopHeartbeat();
    },
  );

  for (final failing in [false, true]) {
    testWidgets(
      'stale ${failing ? 'failure' : 'success'} cannot restart or terminate a replacement cycle',
      (tester) async {
        final api = _RecordingApiService();
        final response = Completer<void>();
        api.onHeartbeat = (_) async {
          await response.future;
          if (failing) throw StateError('old heartbeat failed');
        };
        final service = RealtimeSessionService(apiService: api);
        addTearDown(service.stopHeartbeat);
        var failures = 0;
        service.startHeartbeat(
          sessionID: 'old',
          firstHeartbeatGraceSeconds: 3,
          onFailure: (_, _) async => failures++,
        );
        await tester.pump();
        api.onHeartbeat = null;
        service.startHeartbeat(
          sessionID: 'new',
          firstHeartbeatGraceSeconds: 7,
          onFailure: (_, _) async => failures++,
        );
        await tester.pump();
        response.complete();
        await tester.pump();
        await tester.pump(const Duration(seconds: 10));
        expect(api.requests.map((request) => request.path), [
          '/session/old/heartbeat',
          '/session/new/heartbeat',
          '/session/new/heartbeat',
        ]);
        expect(api.requests.last.body, isNull);
        expect(failures, 0);
        service.stopHeartbeat();
      },
    );
  }

  testWidgets(
    'negative startup allowance reports failure without sending HTTP',
    (tester) async {
      final api = _RecordingApiService();
      final service = RealtimeSessionService(apiService: api);
      Object? failure;
      service.startHeartbeat(
        sessionID: 'session',
        firstHeartbeatGraceSeconds: -1,
        onFailure: (_, error) async => failure = error,
      );
      await tester.pump();
      expect(api.requests, isEmpty);
      expect(
        failure,
        isA<XmaxError>().having(
          (error) => error.code,
          'code',
          XmaxErrorCode.invalidConfiguration,
        ),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(api.requests, isEmpty);
      service.stopHeartbeat();
    },
  );

  testWidgets(
    'current heartbeat failure reports once and stops future requests',
    (tester) async {
      final api = _RecordingApiService();
      final expected = StateError('heartbeat failed');
      api.onHeartbeat = (_) async => throw expected;
      final service = RealtimeSessionService(apiService: api);
      final failures = <Object>[];
      String? failedSessionID;
      service.startHeartbeat(
        sessionID: 'session',
        firstHeartbeatGraceSeconds: 4,
        onFailure: (id, error) async {
          failedSessionID = id;
          failures.add(error);
        },
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(api.requests, hasLength(1));
      expect(failedSessionID, 'session');
      expect(failures, [same(expected)]);
      service.stopHeartbeat();
    },
  );

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
  final requests = <({ApiMethod method, String path, Object? body})>[];

  @override
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(Object? json) decode,
    Future<void>? cancellation,
  }) async {
    requests.add((method: method, path: path, body: body));
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
