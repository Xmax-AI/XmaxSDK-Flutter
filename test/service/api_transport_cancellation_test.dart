import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/service/network/ApiService.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  late HttpServer server;
  late HttpClient client;
  late _Client bridge;
  late Future<void> Function(HttpRequest) handle;
  late ApiService service;
  const deadline = Duration(milliseconds: 200);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
    bridge = _Client(client, server.port);
    service = ApiService(
      apiKey: 'test',
      timeout: deadline,
      transport: HttpApiTransport(client: bridge),
    );
    server.listen((request) {
      request.response.bufferOutput = false;
      unawaited(() async {
        try {
          await handle(request);
        } catch (_) {
          // Cancellation and timeout intentionally close sockets before the server finishes.
        }
      }());
    });
  });
  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  Future<Object> request({Future<void>? cancellation}) => service.get<Object>(
    '/session',
    (json) => json!,
    cancellation: cancellation,
  );
  Future<void> success(HttpRequest request) async {
    request.response.write('{"success":true,"data":{"ok":true}}');
    await request.response.close();
  }

  final cancelled = throwsA(
    isA<XmaxError>().having(
      (error) => error.code,
      'code',
      XmaxErrorCode.cancelled,
    ),
  );
  final networkError = throwsA(
    isA<XmaxError>().having(
      (error) => error.code,
      'code',
      XmaxErrorCode.networkError,
    ),
  );

  test('an already cancelled request never opens HTTP', () async {
    handle = success;
    await expectLater(request(cancellation: Future.value()), cancelled);
    expect(bridge.requests, 0);
  });

  test(
    'cancellation aborts a stalled response header wait and preserves the client',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      handle = (request) async {
        started.complete();
        await release.future;
        await success(request);
      };
      final cancellation = Completer<void>();
      final pending = expectLater(
        request(cancellation: cancellation.future),
        cancelled,
      );
      await started.future;
      cancellation.complete();
      await pending.timeout(const Duration(seconds: 1));
      release.complete();
      handle = success;
      expect(await request(), {'ok': true});
    },
  );

  test('cancellation interrupts an established response body', () async {
    final release = Completer<void>();
    handle = (request) async {
      request.response.contentLength = 16384;
      request.response.add(List.filled(8192, 1));
      await request.response.flush();
      await release.future;
      request.response.add(List.filled(8192, 2));
      await request.response.close();
    };
    final cancellation = Completer<void>();
    final pending = expectLater(
      request(cancellation: cancellation.future),
      cancelled,
    );
    await bridge.subscribed.future;
    cancellation.complete();
    await pending.timeout(const Duration(seconds: 1));
    release.complete();
  });

  test(
    'stalled headers time out and do not poison subsequent requests',
    () async {
      final release = Completer<void>();
      handle = (request) async {
        await release.future;
        await success(request);
      };
      await expectLater(request(), networkError);
      release.complete();
      handle = success;
      expect(await request(), {'ok': true});
    },
  );

  test(
    'a stalled response body times out after headers have arrived',
    () async {
      final release = Completer<void>();
      handle = (request) async {
        request.response.contentLength = 16384;
        request.response.add(List.filled(8192, 1));
        await request.response.flush();
        await release.future;
        await request.response.close();
      };
      final pending = expectLater(request(), networkError);
      await bridge.subscribed.future;
      await pending.timeout(const Duration(seconds: 1));
      release.complete();
      handle = success;
      expect(await request(), {'ok': true});
    },
  );

  test('ongoing response reads reset the inactivity deadline', () async {
    final bytes = utf8.encode('{"success":true,"data":{"ok":true}}');
    handle = (request) async {
      for (var i = 0; i < bytes.length; i += 4) {
        request.response.add(
          bytes.sublist(i, i + 4 > bytes.length ? bytes.length : i + 4),
        );
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      await request.response.close();
    };
    final clock = Stopwatch()..start();
    expect(await request(), {'ok': true});
    expect(clock.elapsed, greaterThan(deadline));
  });

  test(
    'one cancellation does not abort another request on the same client',
    () async {
      final arrived = Completer<void>();
      final release = Completer<void>();
      var count = 0;
      handle = (request) async {
        if (++count == 2) arrived.complete();
        await release.future;
        await success(request);
      };
      final cancellation = Completer<void>();
      final first = expectLater(
        request(cancellation: cancellation.future),
        cancelled,
      );
      final second = request();
      await arrived.future;
      cancellation.complete();
      await first;
      release.complete();
      expect(await second, {'ok': true});
    },
  );

  for (final cancelling in [true, false]) {
    test(
      'late connection handles are aborted after ${cancelling ? 'cancellation' : 'timeout'}',
      () async {
        final deferred = _DeferredClient();
        service = ApiService(
          apiKey: 'test',
          timeout: deadline,
          transport: HttpApiTransport(client: deferred),
        );
        final signal = Completer<void>();
        final failed = expectLater(
          request(cancellation: cancelling ? signal.future : null),
          cancelling ? cancelled : networkError,
        );
        await deferred.started.future;
        if (cancelling) signal.complete();
        await failed;
        final late = _LateRequest();
        deferred.connected.complete(late);
        await Future<void>.delayed(Duration.zero);
        expect(late.aborts, 1);
      },
    );
  }
}

class _Client implements HttpClient {
  _Client(this.client, this.port);
  final HttpClient client;
  final int port;
  final subscribed = Completer<void>();
  int requests = 0;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests++;
    final request = await client.openUrl(
      method,
      url.replace(scheme: 'http', host: '127.0.0.1', port: port),
    );
    return _Request(request, subscribed);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.request, this.subscribed);
  final HttpClientRequest request;
  final Completer<void> subscribed;
  @override
  HttpHeaders get headers => request.headers;
  @override
  Future<HttpClientResponse> get done => request.done;
  @override
  void add(List<int> data) => request.add(data);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      request.abort(exception, stackTrace);
  @override
  Future<HttpClientResponse> close() async =>
      _Response(await request.close(), subscribed);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.response, this.subscribed);
  final HttpClientResponse response;
  final Completer<void> subscribed;
  @override
  int get statusCode => response.statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (!subscribed.isCompleted) subscribed.complete();
    return response.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredClient implements HttpClient {
  final started = Completer<void>();
  final connected = Completer<HttpClientRequest>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    started.complete();
    return connected.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LateRequest implements HttpClientRequest {
  final completed = Completer<HttpClientResponse>();
  int aborts = 0;
  @override
  Future<HttpClientResponse> get done => completed.future;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts++;
    completed.completeError(
      exception ?? const HttpException('aborted'),
      stackTrace,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
