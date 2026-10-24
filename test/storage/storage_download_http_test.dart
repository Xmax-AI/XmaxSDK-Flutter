import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManager.dart';
import 'package:xmax_sdk/src/core/storage/XmaxStorageManager.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/storage/StorageService.dart';
import 'package:xmax_sdk/xmax_sdk.dart' show XmaxStorageCancellationToken;

void main() {
  late Directory directory;
  late File destination;
  late HttpServer server;
  late HttpClient client;
  late StorageManager manager;
  late Future<void> Function(HttpRequest request) handle;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'xmax-download-http-test-',
    );
    destination = File('${directory.path}/download');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
    manager = StorageManager(httpClient: client);
    server.listen((request) {
      request.response.bufferOutput = false;
      unawaited(() async {
        try {
          await handle(request);
        } catch (_) {
          // Tests intentionally terminate sockets to exercise transfer failures.
        }
      }());
    });
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Uri remote() => Uri.parse('http://127.0.0.1:${server.port}/file');

  test(
    'public unknown-size progress preserves bytes and reports the actual total at completion',
    () async {
      final firstWritten = Completer<void>();
      final release = Completer<void>();
      final observed = <(int, int)>[];
      handle = (request) async {
        request.response.add(List.filled(8192, 1));
        await request.response.flush();
        await release.future;
        request.response.add([2, 3]);
        await request.response.close();
      };
      final storage = XmaxStorageManager(
        storageService: StorageService(
          apiService: _UnusedAPI(),
          storageManager: manager,
        ),
      );
      final download = storage.downloadImage(
        from: remote(),
        to: destination.uri,
        progress: (value) {
          observed.add((value.completedBytes, value.totalBytes));
          if (value.totalBytes == 0 &&
              value.completedBytes > 0 &&
              !firstWritten.isCompleted) {
            expect(value.fractionCompleted, 0);
            firstWritten.complete();
          }
        },
      );
      await firstWritten.future.timeout(const Duration(seconds: 5));
      release.complete();
      final result = await download;
      expect(result.byteCount, 8194);
      expect(observed.first, (8192, 0));
      expect(observed.last, (8194, 8194));
    },
  );

  test(
    'public download cancellation interrupts a real response header wait',
    () async {
      await destination.writeAsString('previous');
      final started = Completer<void>();
      final release = Completer<void>();
      handle = (request) async {
        started.complete();
        await release.future;
        await request.response.close();
      };
      final storage = XmaxStorageManager(
        storageService: StorageService(
          apiService: _UnusedAPI(),
          storageManager: manager,
        ),
      );
      final token = XmaxStorageCancellationToken();
      final downloading = storage.downloadImage(
        from: remote(),
        to: destination.uri,
        cancellationToken: token,
        progress: (_) => fail('No body progress expected'),
      );
      final failed = expectLater(
        downloading.timeout(const Duration(seconds: 5)),
        _cancelled,
      );
      await started.future.timeout(const Duration(seconds: 5));
      token.cancel();
      await failed;
      expect(await destination.readAsString(), 'previous');
      expect(directory.listSync().length, 1);
      release.complete();
    },
  );

  test(
    'public video cancellation stops a real stalled body without closing other transfers',
    () async {
      await destination.writeAsString('previous');
      final received = Completer<void>();
      final otherStarted = Completer<void>();
      final release = Completer<void>();
      handle = (request) async {
        if (request.uri.path == '/other') {
          otherStarted.complete();
          await release.future;
          request.response.add([7, 8, 9]);
          await request.response.close();
          return;
        }
        request.response.contentLength = 16384;
        request.response.add(List<int>.filled(8192, 1));
        await request.response.flush();
        await release.future;
        request.response.add(List<int>.filled(8192, 2));
        await request.response.close();
      };
      final storage = XmaxStorageManager(
        storageService: StorageService(
          apiService: _UnusedAPI(),
          storageManager: manager,
        ),
      );
      final token = XmaxStorageCancellationToken();
      var notifications = 0;
      final downloading = storage.downloadVideo(
        from: remote(),
        to: destination.uri,
        cancellationToken: token,
        progress: (_) {
          notifications++;
          if (!received.isCompleted) received.complete();
        },
      );
      final failed = expectLater(
        downloading.timeout(const Duration(seconds: 5)),
        _cancelled,
      );
      await received.future.timeout(const Duration(seconds: 5));
      final other = File('${directory.path}/other');
      final unaffected = storage.downloadImage(
        from: remote().replace(path: '/other'),
        to: other.uri,
      );
      await otherStarted.future.timeout(const Duration(seconds: 5));
      token.cancel();
      await failed;
      final countAfterCancellation = notifications;
      release.complete();
      await unaffected.timeout(const Duration(seconds: 5));
      expect(notifications, countAfterCancellation);
      expect(await destination.readAsString(), 'previous');
      expect(await other.readAsBytes(), [7, 8, 9]);
      expect(directory.listSync().length, 2);
    },
  );

  test(
    'real streamed HTTP download preserves the existing file until commit',
    () async {
      await destination.writeAsString('previous');
      final received = Completer<void>();
      final release = Completer<void>();
      final payload = List<int>.generate(16384, (index) => index % 256);
      handle = (request) async {
        request.response.contentLength = payload.length;
        request.response.add(payload.sublist(0, 8192));
        await request.response.flush();
        await release.future;
        request.response.add(payload.sublist(8192));
        await request.response.close();
      };
      final downloading = manager.download(
        remoteURL: remote(),
        destinationURL: destination.uri,
        progress: (completed, total) {
          if (completed > 0 && completed < total && !received.isCompleted) {
            received.complete();
          }
        },
      );
      await received.future.timeout(const Duration(seconds: 5));
      expect(await destination.readAsString(), 'previous');
      release.complete();
      final result = await downloading;
      expect(result.byteCount, payload.length);
      expect(await destination.readAsBytes(), payload);
      expect(directory.listSync().length, 1);
    },
  );

  test('real gzip responses use the decompressed on-disk byte count', () async {
    final payload = List<int>.filled(32768, 42);
    final compressed = gzip.encode(payload);
    handle = (request) async {
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.contentLength = compressed.length;
      request.response.add(compressed);
      await request.response.close();
    };
    final progress = <(int, int)>[];
    final result = await manager.download(
      remoteURL: remote(),
      destinationURL: destination.uri,
      progress: (completed, total) => progress.add((completed, total)),
    );
    expect(result.byteCount, payload.length);
    expect(await destination.readAsBytes(), payload);
    expect(progress.any((event) => event.$1 > 0 && event.$2 == 0), isTrue);
    expect(progress.last, (payload.length, payload.length));
    expect(directory.listSync().length, 1);
  });

  test(
    'a truncated real HTTP body cannot replace an existing destination',
    () async {
      await destination.writeAsString('previous');
      handle = (request) async {
        request.response.contentLength = 16384;
        request.response.add(List<int>.filled(8192, 1));
        await request.response.flush();
        request.response.deadline = const Duration(milliseconds: 20);
      };
      await expectLater(
        manager
            .download(remoteURL: remote(), destinationURL: destination.uri)
            .timeout(const Duration(seconds: 5)),
        throwsA(
          isA<XmaxError>().having(
            (error) => error.code,
            'code',
            XmaxErrorCode.downloadError,
          ),
        ),
      );
      expect(await destination.readAsString(), 'previous');
      expect(directory.listSync().length, 1);
    },
  );

  test(
    'closing an active HTTP transport leaves no partial destination',
    () async {
      await destination.writeAsString('previous');
      final received = Completer<void>();
      final release = Completer<void>();
      handle = (request) async {
        request.response.contentLength = 16384;
        request.response.add(List<int>.filled(8192, 1));
        await request.response.flush();
        await release.future;
        await request.response.close();
      };
      final downloading = manager.download(
        remoteURL: remote(),
        destinationURL: destination.uri,
        progress: (completed, total) {
          if (completed > 0 && completed < total && !received.isCompleted) {
            received.complete();
          }
        },
      );
      final failed = expectLater(
        downloading.timeout(const Duration(seconds: 5)),
        throwsA(isA<XmaxError>()),
      );
      await received.future.timeout(const Duration(seconds: 5));
      client.close(force: true);
      release.complete();
      await failed;
      expect(await destination.readAsString(), 'previous');
      expect(directory.listSync().length, 1);
    },
  );
}

final _cancelled = throwsA(
  isA<XmaxError>().having(
    (error) => error.code,
    'code',
    XmaxErrorCode.cancelled,
  ),
);

final class _UnusedAPI implements ApiServicing {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
