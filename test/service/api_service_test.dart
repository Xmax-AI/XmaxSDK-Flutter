import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/runtime/RuntimeInfo.dart';
import 'package:xmax_sdk/src/service/network/ApiService.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test('ApiService sends X-Api-Key and decodes data envelope', () async {
    final transport = _FakeTransport(
      response: ApiTransportResponse(
        statusCode: 200,
        body: utf8.encode('{"success":true,"data":{"id":"session-1"}}'),
      ),
    );
    final service = ApiService(apiKey: ' key ', transport: transport);

    final result = await service.post<Map<String, dynamic>>(
      '/session',
      (json) => json! as Map<String, dynamic>,
      body: <String, Object?>{'model': 'x2.0'},
    );

    expect(result['id'], 'session-1');
    expect(transport.headers?['X-Api-Key'], 'key');
    final runtime = await RuntimeInfo.resolve();
    expect(transport.headers?['X-Platform'], runtime.platform);
    expect(transport.headers?['X-OS-Version'], runtime.osVersion);
    expect(transport.headers?['X-SDK-Version'], runtime.sdkVersion);
    expect(transport.headers?['X-Device-Model'], runtime.deviceModel);
    expect(transport.url.toString(), '${ApiService.defaultBaseURL}/session');
    expect(utf8.decode(transport.body!), '{"model":"x2.0"}');
  });

  test('ApiService routes global environment to the overseas API', () async {
    final transport = _FakeTransport(
      response: ApiTransportResponse(
        statusCode: 200,
        body: utf8.encode('{"success":true,"data":{}}'),
      ),
    );
    final service = ApiService(
      apiKey: 'key',
      environment: XmaxEnvironment.global,
      transport: transport,
    );

    await service.get<Map<String, dynamic>>(
      '/session',
      (json) => json! as Map<String, dynamic>,
    );

    expect(
      transport.url.toString(),
      'https://api.xmax.cloud/open/api/v1/session',
    );
  });

  test('ApiService maps failed envelope to apiError', () async {
    final service = ApiService(
      apiKey: 'key',
      transport: _FakeTransport(
        response: ApiTransportResponse(
          statusCode: 403,
          body: utf8.encode('{"success":false,"code":4001,"message":"denied"}'),
        ),
      ),
    );

    await expectLater(
      service.get<Object>('/session', (json) => json!),
      throwsA(
        isA<XmaxError>()
            .having((error) => error.code, 'code', XmaxErrorCode.apiError)
            .having((error) => error.apiCode, 'apiCode', 4001)
            .having((error) => error.httpStatus, 'httpStatus', 403),
      ),
    );
  });

  test('ApiService rejects an empty API key before transport', () async {
    final service = ApiService(
      apiKey: ' ',
      transport: _FakeTransport(
        response: const ApiTransportResponse(statusCode: 200, body: <int>[]),
      ),
    );

    await expectLater(
      service.get<Object>('/session', (json) => json!),
      throwsA(
        isA<XmaxError>().having(
          (error) => error.code,
          'code',
          XmaxErrorCode.invalidAPIKey,
        ),
      ),
    );
  });

  test('ApiService maps an aborted request to cancelled', () async {
    final service = ApiService(
      apiKey: 'key',
      transport: _FailingTransport(
        const HttpException('Request has been aborted'),
      ),
    );

    await expectLater(
      service.get<Object>('/session', (json) => json!),
      throwsA(
        isA<XmaxError>()
            .having((error) => error.code, 'code', XmaxErrorCode.cancelled)
            .having(
              (error) => error.message,
              'message',
              'API request was cancelled',
            ),
      ),
    );
  });
}

final class _FailingTransport implements ApiTransport {
  const _FailingTransport(this.error);

  final Object error;

  @override
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
    Future<void>? cancellation,
  }) async => throw error;
}

final class _FakeTransport implements ApiTransport {
  _FakeTransport({required this.response});

  final ApiTransportResponse response;
  Uri url = Uri();
  Map<String, String>? headers;
  List<int>? body;

  @override
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
    Future<void>? cancellation,
  }) async {
    this.url = url;
    this.headers = headers;
    this.body = body;
    return response;
  }
}
