import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManager.dart';

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
