import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/XmaxSDK.dart' as compatibility;
import 'package:xmax_sdk/src/service/network/ApiService.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  for (final (environment, endpoint) in [
    (XmaxEnvironment.china, 'https://cloud.xmax.22duck.cn/open/api/v1/balance'),
    (XmaxEnvironment.global, 'https://api.xmax.cloud/open/api/v1/balance'),
  ]) {
    test(
      'queries the general ${environment.name} API without a session',
      () async {
        final transport = _Transport(
          (_) =>
              _response('{"success":true,"data":{"currentBalance":1250.75}}'),
        );
        final client = _client(
          transport,
          apiKey: '  balance-key\n',
          environment: environment,
        );

        final compatibility.XmaxCreditBalance balance = await client
            .getCreditBalance();

        expect(balance.currentBalance, 1250.75);
        expect(transport.requests, hasLength(1));
        final request = transport.requests.single;
        expect(request.method, ApiMethod.get);
        expect(request.url.toString(), endpoint);
        expect(request.headers['X-Api-Key'], 'balance-key');
        expect(request.headers['X-SDK-Version'], XmaxSDKInfo.version);
        expect(request.body, isNull);
      },
    );
  }

  test(
    'each invocation fetches fresh credits and preserves integers and fractions',
    () async {
      final values = <num>[0, 0.25, 1250.75, 100, 1e308];
      var calls = 0;
      final transport = _Transport(
        (_) => _response(
          jsonEncode({
            'success': true,
            'data': {'currentBalance': values[calls++]},
          }),
        ),
      );
      final client = _client(transport);

      for (final value in values) {
        expect(
          (await client.getCreditBalance()).currentBalance,
          value.toDouble(),
        );
      }

      expect(transport.requests, hasLength(values.length));
      expect(
        transport.requests.every(
          (request) => request.url.path.endsWith('/balance'),
        ),
        isTrue,
      );
    },
  );

  test('empty API key fails before invoking the injected service', () async {
    final transport = _Transport((_) => throw StateError('Unexpected request'));
    final client = XmaxClient.internal(
      configuration: XmaxConfiguration(apiKey: ' \n '),
      apiService: ApiService(apiKey: 'transport-key', transport: transport),
    );

    await expectLater(
      client.getCreditBalance(),
      _error(XmaxErrorCode.invalidAPIKey),
    );
    expect(transport.requests, isEmpty);
  });

  for (final payload in [
    'null',
    '[]',
    'true',
    '1250.75',
    '"1250.75"',
    '{}',
    '{"currentBalance":null}',
    '{"currentBalance":true}',
    '{"currentBalance":"1250.75"}',
    '{"currentBalance":-1}',
    '{"currentBalance":-0.25}',
    '{"currentBalance":1e400}',
    '{"currentBalance":NaN}',
    '{"currentBalance":Infinity}',
    '{"currentBalance":[]}',
    '{"currentBalance":{}}',
  ]) {
    test(
      'rejects invalid balance payload $payload instead of returning zero',
      () async {
        final client = _client(
          _Transport((_) => _response('{"success":true,"data":$payload}')),
        );

        await expectLater(
          client.getCreditBalance(),
          throwsA(
            isA<XmaxError>()
                .having((error) => error.code, 'code', XmaxErrorCode.apiError)
                .having((error) => error.httpStatus, 'httpStatus', 200),
          ),
        );
      },
    );
  }

  test('invalid response JSON remains an API error', () async {
    final client = _client(_Transport((_) => _response('not-json')));

    await expectLater(
      client.getCreditBalance(),
      throwsA(
        isA<XmaxError>()
            .having((error) => error.code, 'code', XmaxErrorCode.apiError)
            .having((error) => error.httpStatus, 'httpStatus', 200),
      ),
    );
  });

  for (final status in [200, 401, 403, 429, 500]) {
    test('business errors preserve server details with HTTP $status', () async {
      final client = _client(
        _Transport(
          (_) => _response(
            '{"success":false,"code":46002,"message":"Invalid API key","data":null}',
            statusCode: status,
          ),
        ),
      );

      await expectLater(
        client.getCreditBalance(),
        throwsA(
          XmaxError(
            code: XmaxErrorCode.apiError,
            message: 'Invalid API key',
            apiCode: 46002,
            httpStatus: status,
          ),
        ),
      );
    });
  }

  test('transport failures remain network errors', () async {
    final client = _client(
      _Transport((_) => throw const SocketException('offline')),
    );

    await expectLater(
      client.getCreditBalance(),
      _error(XmaxErrorCode.networkError),
    );
  });

  test('aborted transport remains cancelled', () async {
    final client = _client(
      _Transport((_) => throw const HttpException('Request has been aborted')),
    );

    await expectLater(
      client.getCreditBalance(),
      _error(XmaxErrorCode.cancelled),
    );
  });

  test('SDK cancellation errors are preserved', () async {
    const cancellation = XmaxError(
      code: XmaxErrorCode.cancelled,
      message: 'cancelled',
    );
    final client = _client(_Transport((_) => throw cancellation));

    await expectLater(client.getCreditBalance(), throwsA(same(cancellation)));
  });

  test('concurrent queries keep independent response ownership', () async {
    final started = Completer<void>();
    final pending = [
      Completer<ApiTransportResponse>(),
      Completer<ApiTransportResponse>(),
    ];
    var calls = 0;
    final transport = _Transport((_) {
      final response = pending[calls++].future;
      if (calls == 2) started.complete();
      return response;
    });
    final client = _client(transport);

    final first = client.getCreditBalance();
    final second = client.getCreditBalance();
    await started.future;
    pending[1].complete(
      _response('{"success":true,"data":{"currentBalance":25.5}}'),
    );
    expect((await second).currentBalance, 25.5);
    pending[0].complete(
      _response('{"success":true,"data":{"currentBalance":100}}'),
    );
    expect((await first).currentBalance, 100.0);
    expect(transport.requests, hasLength(2));
  });

  test('balances provide value equality and consistent hashing', () async {
    final transport = _Transport(
      (_) => _response('{"success":true,"data":{"currentBalance":1250.75}}'),
    );
    final client = _client(transport);
    final first = await client.getCreditBalance();
    final second = await client.getCreditBalance();
    final other = await _client(
      _Transport(
        (_) => _response('{"success":true,"data":{"currentBalance":0}}'),
      ),
    ).getCreditBalance();

    expect(identical(first, second), isFalse);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(other));
    expect(first, isNot(Object()));
    expect({first, second, other}, hasLength(2));
  });
}

Matcher _error(XmaxErrorCode code) =>
    throwsA(isA<XmaxError>().having((error) => error.code, 'code', code));

XmaxClient _client(
  ApiTransport transport, {
  String apiKey = 'balance-key',
  XmaxEnvironment environment = XmaxEnvironment.china,
}) {
  final configuration = XmaxConfiguration(
    apiKey: apiKey,
    environment: environment,
  );
  return XmaxClient.internal(
    configuration: configuration,
    apiService: ApiService(
      apiKey: configuration.apiKey,
      environment: configuration.environment,
      transport: transport,
    ),
  );
}

ApiTransportResponse _response(String body, {int statusCode = 200}) =>
    ApiTransportResponse(statusCode: statusCode, body: utf8.encode(body));

typedef _Request = ({
  ApiMethod method,
  Uri url,
  Map<String, String> headers,
  List<int>? body,
});

final class _Transport implements ApiTransport {
  _Transport(this.respond);

  final FutureOr<ApiTransportResponse> Function(_Request request) respond;
  final requests = <_Request>[];

  @override
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
    Future<void>? cancellation,
  }) async {
    final request = (method: method, url: url, headers: headers, body: body);
    requests.add(request);
    return await respond(request);
  }
}
