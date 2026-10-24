import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManager.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  late Directory directory;
  late File destination;
  final cancelled = throwsA(
    isA<XmaxError>().having(
      (error) => error.code,
      'code',
      XmaxErrorCode.cancelled,
    ),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xmax-cancel-test-');
    destination = File('${directory.path}/download');
    await destination.writeAsBytes([9]);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> expectPreserved() async {
    expect(await destination.readAsBytes(), [9]);
    expect(directory.listSync().map((file) => file.path), [destination.path]);
  }

  test(
    'an already cancelled token makes no request and cannot be reset',
    () async {
      final token = XmaxStorageCancellationToken()..cancel();
      token.cancel();
      final client = _Client((_) => throw StateError('No request expected'));
      final manager = StorageManager(httpClient: client);
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          manager.download(
            remoteURL: Uri.parse('https://example.com/file'),
            destinationURL: destination.uri,
            cancellationToken: token,
            progress: (_, _) => fail('No progress expected'),
          ),
          cancelled,
        );
      }
      expect(token.isCancelled, isTrue);
      expect(client.requests, 0);
      await expectPreserved();
    },
  );

  test(
    'cancellation interrupts connection setup and aborts a late request',
    () async {
      final connected = Completer<HttpClientRequest>();
      final client = _Client((_) => connected.future);
      final token = XmaxStorageCancellationToken();
      final downloading = StorageManager(httpClient: client).download(
        remoteURL: Uri.parse('https://example.com/file'),
        destinationURL: destination.uri,
        cancellationToken: token,
      );
      final failed = expectLater(downloading, cancelled);
      await client.started.future;
      token.cancel();
      await failed;
      await expectPreserved();

      final request = _Request();
      connected.complete(request);
      await Future<void>.delayed(Duration.zero);
      expect(request.aborts, 1);
      expect(request.closed.isCompleted, isFalse);
      expect(client.closed, isFalse);
    },
  );

  test('cancellation interrupts a stalled response header wait', () async {
    final request = _Request();
    final client = _Client((_) async => request);
    final token = XmaxStorageCancellationToken();
    final downloading = StorageManager(httpClient: client).download(
      remoteURL: Uri.parse('https://example.com/file'),
      destinationURL: destination.uri,
      cancellationToken: token,
    );
    final failed = expectLater(downloading, cancelled);
    await request.closed.future;
    token.cancel();
    token.cancel();
    await failed;
    expect(request.aborts, 1);
    expect(client.closed, isFalse);
    await expectPreserved();
  });

  test(
    'a response arriving after cancellation is released without staging',
    () async {
      final request = _Request(completeOnAbort: false);
      final token = XmaxStorageCancellationToken();
      final downloading =
          StorageManager(httpClient: _Client((_) async => request)).download(
            remoteURL: Uri.parse('https://example.com/file'),
            destinationURL: destination.uri,
            cancellationToken: token,
          );
      final failed = expectLater(downloading, cancelled);
      await request.closed.future;
      token.cancel();
      await failed;

      final released = Completer<void>();
      final body = StreamController<List<int>>(onCancel: released.complete);
      request.responseReady.complete(_Response(body.stream));
      await released.future;
      await body.close();
      await expectPreserved();
    },
  );

  for (final existing in [true, false]) {
    test(
      'cancellation releases a stalled body; existing file: $existing',
      () async {
        if (!existing) await destination.delete();
        final body = StreamController<List<int>>();
        final request = _Request()
          ..responseReady.complete(_Response(body.stream, length: 4));
        final token = XmaxStorageCancellationToken();
        final received = Completer<void>();
        final progress = <(int, int)>[];
        final downloading =
            StorageManager(httpClient: _Client((_) async => request)).download(
              remoteURL: Uri.parse('https://example.com/file'),
              destinationURL: destination.uri,
              cancellationToken: token,
              progress: (completed, total) {
                progress.add((completed, total));
                if (!received.isCompleted) received.complete();
              },
            );
        final failed = expectLater(downloading, cancelled);
        body.add([1, 2]);
        await received.future;
        token.cancel();
        await failed;
        body.add([3, 4]);
        await body.close();
        expect(progress, [(2, 4)]);
        expect(request.aborts, 1);
        if (existing) {
          await expectPreserved();
        } else {
          expect(directory.listSync(), isEmpty);
        }
      },
    );
  }

  test(
    'cancelling from the last write progress prevents replacement',
    () async {
      final token = XmaxStorageCancellationToken();
      final request = _Request()
        ..responseReady.complete(_Response(Stream.value([1, 2]), length: 2));
      var notifications = 0;
      await expectLater(
        StorageManager(httpClient: _Client((_) async => request)).download(
          remoteURL: Uri.parse('https://example.com/file'),
          destinationURL: destination.uri,
          cancellationToken: token,
          progress: (_, _) {
            notifications++;
            token.cancel();
            throw StateError('Observer failure must not hide cancellation');
          },
        ),
        cancelled,
      );
      expect(notifications, 1);
      await expectPreserved();
    },
  );

  test(
    'cancellation during completion notification cannot undo commit',
    () async {
      final token = XmaxStorageCancellationToken();
      final request = _Request()
        ..responseReady.complete(_Response(Stream.value([1, 2]), length: 2));
      var notifications = 0;
      final result =
          await StorageManager(
            httpClient: _Client((_) async => request),
          ).download(
            remoteURL: Uri.parse('https://example.com/file'),
            destinationURL: destination.uri,
            cancellationToken: token,
            progress: (_, _) {
              notifications++;
              if (notifications == 2) token.cancel();
            },
          );
      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(request.aborts, 0);
      expect(result.byteCount, 2);
      expect(await destination.readAsBytes(), [1, 2]);
      expect(directory.listSync().length, 1);
    },
  );

  test(
    'a shared token cancels both active downloads but a fresh token can retry',
    () async {
      final bodies = [
        StreamController<List<int>>(),
        StreamController<List<int>>(),
      ];
      final requests = bodies
          .map(
            (body) =>
                _Request()
                  ..responseReady.complete(_Response(body.stream, length: 4)),
          )
          .toList();
      final started = [Completer<void>(), Completer<void>()];
      final second = File('${directory.path}/second');
      var next = 0;
      final manager = StorageManager(
        httpClient: _Client((_) async => requests[next++]),
      );
      final token = XmaxStorageCancellationToken();
      final failures = [destination, second].indexed.map((entry) {
        return expectLater(
          manager.download(
            remoteURL: Uri.parse('https://example.com/${entry.$1}'),
            destinationURL: entry.$2.uri,
            cancellationToken: token,
            progress: (_, _) {
              if (!started[entry.$1].isCompleted) started[entry.$1].complete();
            },
          ),
          cancelled,
        );
      }).toList();
      for (final body in bodies) {
        body.add([1, 2]);
      }
      await Future.wait(started.map((event) => event.future));
      token.cancel();
      await Future.wait(failures);
      for (final body in bodies) {
        await body.close();
      }
      expect(requests.map((request) => request.aborts), [1, 1]);
      await expectPreserved();

      final retryRequest = _Request()
        ..responseReady.complete(_Response(Stream.value([3, 4]), length: 2));
      final retryToken = XmaxStorageCancellationToken();
      final result =
          await StorageManager(
            httpClient: _Client((_) async => retryRequest),
          ).download(
            remoteURL: Uri.parse('https://example.com/retry'),
            destinationURL: destination.uri,
            cancellationToken: retryToken,
          );
      retryToken.cancel();
      expect(result.byteCount, 2);
      expect(await destination.readAsBytes(), [3, 4]);
      expect(retryRequest.aborts, 0);
    },
  );
}

final class _Client implements HttpClient {
  _Client(this.connect);
  final Future<HttpClientRequest> Function(Uri) connect;
  final started = Completer<void>();
  int requests = 0;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests++;
    if (!started.isCompleted) started.complete();
    return connect(url);
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Request implements HttpClientRequest {
  _Request({this.completeOnAbort = true});
  final bool completeOnAbort;
  final responseReady = Completer<HttpClientResponse>();
  final closed = Completer<void>();
  int aborts = 0;

  @override
  Future<HttpClientResponse> get done => responseReady.future;

  @override
  Future<HttpClientResponse> close() {
    closed.complete();
    return responseReady.future;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts++;
    if (completeOnAbort && !responseReady.isCompleted) {
      responseReady.completeError(exception!, stackTrace);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body, {int length = -1}) : expectedLength = length;
  final Stream<List<int>> body;
  final int expectedLength;

  @override
  int get contentLength => expectedLength;

  @override
  int get statusCode => 200;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
