import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManager.dart';

void main() {
  late Directory directory;
  late File destination;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xmax-download-test-');
    destination = File('${directory.path}/video.mp4');
  });
  tearDown(() async => directory.delete(recursive: true));

  List<String> remainingFiles() =>
      directory
          .listSync()
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();

  test(
    'keeps the existing file unchanged until the completed download is committed',
    () async {
      await destination.writeAsBytes([9, 9]);
      final release = Completer<void>();
      final received = Completer<void>();
      Stream<List<int>> body() async* {
        yield [1, 2];
        await release.future;
        yield [3, 4];
      }

      final progress = <(int, int)>[];
      final observedFiles = <List<int>>[];
      final client = _Client((_) => _Response(body(), length: 4));
      final downloading = StorageManager(httpClient: client).download(
        remoteURL: Uri.parse('https://example.com/video'),
        destinationURL: destination.uri,
        progress: (completed, total) {
          progress.add((completed, total));
          observedFiles.add(destination.readAsBytesSync());
          if (!received.isCompleted) received.complete();
        },
      );
      await received.future;
      expect(await destination.readAsBytes(), [9, 9]);
      expect(progress.first, (2, 4));
      release.complete();
      final result = await downloading;

      expect(result.fileURL, destination.uri);
      expect(result.byteCount, 4);
      expect(await destination.readAsBytes(), [1, 2, 3, 4]);
      expect(observedFiles.first, [9, 9]);
      expect(observedFiles.last, [1, 2, 3, 4]);
      expect(progress.last, (4, 4));
      expect(remainingFiles(), ['video.mp4']);
      expect(
        client.closed,
        isFalse,
        reason: 'One operation must not close a shared HTTP client',
      );
    },
  );

  test(
    'unknown lengths report incremental bytes with zero total until completion',
    () async {
      final progress = <(int, int)>[];
      final manager = StorageManager(
        httpClient: _Client(
          (_) => _Response(
            Stream.fromIterable([
              [1, 2],
              [3],
            ]),
          ),
        ),
      );
      final result = await manager.download(
        remoteURL: Uri.parse('https://example.com/unknown'),
        destinationURL: destination.uri,
        progress: (completed, total) => progress.add((completed, total)),
      );
      expect(result.byteCount, 3);
      expect(progress, [(2, 0), (3, 0), (3, 3)]);
      expect(remainingFiles(), ['video.mp4']);
    },
  );

  test(
    'empty responses commit an empty file and report zero-byte completion',
    () async {
      await destination.writeAsBytes([9]);
      final progress = <(int, int)>[];
      final manager = StorageManager(
        httpClient: _Client((_) => _Response(const Stream.empty(), length: 0)),
      );
      final result = await manager.download(
        remoteURL: Uri.parse('https://example.com/empty'),
        destinationURL: destination.uri,
        progress: (completed, total) => progress.add((completed, total)),
      );
      expect(result.byteCount, 0);
      expect(await destination.length(), 0);
      expect(progress, [(0, 0)]);
      expect(remainingFiles(), ['video.mp4']);
    },
  );

  test(
    'HTTP failure preserves the existing file, suppresses progress, and cancels the response',
    () async {
      await destination.writeAsBytes([9]);
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final progress = <(int, int)>[];
      final manager = StorageManager(
        httpClient: _Client((_) => _Response(body.stream, status: 403)),
      );
      await expectLater(
        manager.download(
          remoteURL: Uri.parse('https://example.com/forbidden'),
          destinationURL: destination.uri,
          progress: (completed, total) => progress.add((completed, total)),
        ),
        throwsA(
          isA<XmaxError>()
              .having(
                (error) => error.code,
                'code',
                XmaxErrorCode.downloadError,
              )
              .having((error) => error.httpStatus, 'status', 403),
        ),
      );
      expect(await destination.readAsBytes(), [9]);
      expect(progress, isEmpty);
      expect(cancelled, isTrue);
      expect(remainingFiles(), ['video.mp4']);
      await body.close();
    },
  );

  for (final hasDestination in [true, false]) {
    test(
      'interrupted transfer cleans staging (existing destination: $hasDestination)',
      () async {
        if (hasDestination) await destination.writeAsBytes([9]);
        Stream<List<int>> body() async* {
          yield [1, 2];
          throw const SocketException('connection lost');
        }

        final progress = <(int, int)>[];
        final manager = StorageManager(
          httpClient: _Client((_) => _Response(body(), length: 4)),
        );
        await expectLater(
          manager.download(
            remoteURL: Uri.parse('https://example.com/interrupted'),
            destinationURL: destination.uri,
            progress: (completed, total) => progress.add((completed, total)),
          ),
          throwsA(_downloadError),
        );
        expect(progress, [(2, 4)]);
        expect(remainingFiles(), hasDestination ? ['video.mp4'] : isEmpty);
        if (hasDestination) expect(await destination.readAsBytes(), [9]);
      },
    );
  }

  test(
    'aborted transport preserves the existing file and maps cancellation',
    () async {
      await destination.writeAsBytes([9]);
      Stream<List<int>> body() async* {
        yield [1, 2];
        throw const HttpException('Request has been aborted');
      }

      final manager = StorageManager(
        httpClient: _Client((_) => _Response(body(), length: 4)),
      );
      await expectLater(
        manager.download(
          remoteURL: Uri.parse('https://example.com/aborted'),
          destinationURL: destination.uri,
        ),
        throwsA(
          isA<XmaxError>().having(
            (error) => error.code,
            'code',
            XmaxErrorCode.cancelled,
          ),
        ),
      );
      expect(await destination.readAsBytes(), [9]);
      expect(remainingFiles(), ['video.mp4']);
    },
  );

  for (final expected in [1, 8]) {
    test(
      'inconsistent content length $expected cannot replace a valid destination',
      () async {
        await destination.writeAsBytes([9]);
        final manager = StorageManager(
          httpClient: _Client(
            (_) => _Response(Stream.value([1, 2]), length: expected),
          ),
        );
        await expectLater(
          manager.download(
            remoteURL: Uri.parse('https://example.com/truncated'),
            destinationURL: destination.uri,
          ),
          throwsA(_downloadError),
        );
        expect(await destination.readAsBytes(), [9]);
        expect(remainingFiles(), ['video.mp4']);
      },
    );
  }

  test(
    'directory destinations are not modified and do not start a request',
    () async {
      final original = File('${directory.path}/keep.txt');
      await original.writeAsString('keep');
      final client = _Client((_) => _Response(Stream.value([1]), length: 1));
      await expectLater(
        StorageManager(httpClient: client).download(
          remoteURL: Uri.parse('https://example.com/file'),
          destinationURL: directory.uri,
        ),
        throwsA(_downloadError),
      );
      expect(await original.readAsString(), 'keep');
      expect(client.requests, 0);
      expect(remainingFiles(), ['keep.txt']);
    },
  );

  test(
    'directory symlink destinations are rejected without modifying the target',
    () async {
      final folder = await Directory('${directory.path}/folder').create();
      final keep = File('${folder.path}/keep.txt');
      await keep.writeAsString('keep');
      final link = await Link('${directory.path}/link').create(folder.path);
      final client = _Client((_) => _Response(Stream.value([1]), length: 1));
      await expectLater(
        StorageManager(httpClient: client).download(
          remoteURL: Uri.parse('https://example.com/file'),
          destinationURL: link.uri,
        ),
        throwsA(_downloadError),
      );
      expect(await keep.readAsString(), 'keep');
      expect(await link.exists(), isTrue);
      expect(client.requests, 0);
      expect(remainingFiles(), ['folder', 'link']);
    },
  );

  test(
    'staging failure cancels an unread response without creating a partial file',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = _Client((_) => _Response(body.stream));
      final target = File('${directory.path}/missing/file');
      await expectLater(
        StorageManager(httpClient: client).download(
          remoteURL: Uri.parse('https://example.com/file'),
          destinationURL: target.uri,
        ),
        throwsA(_downloadError),
      );
      expect(cancelled, isTrue);
      expect(remainingFiles(), isEmpty);
      await body.close();
    },
  );

  test(
    'a directory appearing before commit is preserved and staging is removed',
    () async {
      final manager = StorageManager(
        httpClient: _Client((_) => _Response(Stream.value([1]), length: 1)),
      );
      var created = false;
      await expectLater(
        manager.download(
          remoteURL: Uri.parse('https://example.com/file'),
          destinationURL: destination.uri,
          progress: (_, _) {
            if (created) return;
            created = true;
            Directory(destination.path).createSync();
            File('${destination.path}/keep.txt').writeAsStringSync('keep');
          },
        ),
        throwsA(_downloadError),
      );
      expect(await File('${destination.path}/keep.txt').readAsString(), 'keep');
      expect(remainingFiles(), ['video.mp4']);
    },
  );

  test(
    'invalid source and destination URLs fail before any network request',
    () async {
      final client = _Client((_) => _Response(const Stream.empty()));
      final manager = StorageManager(httpClient: client);
      for (final urls in [
        (Uri.parse('ftp://example.com/file'), destination.uri),
        (
          Uri.parse('https://example.com/file'),
          Uri.parse('https://example.com/destination'),
        ),
      ]) {
        await expectLater(
          manager.download(remoteURL: urls.$1, destinationURL: urls.$2),
          throwsA(_downloadError),
        );
      }
      expect(client.requests, 0);
      expect(remainingFiles(), isEmpty);
    },
  );

  test(
    'progress observer failures cannot fail a completed file commit',
    () async {
      final manager = StorageManager(
        httpClient: _Client((_) => _Response(Stream.value([1, 2]), length: 2)),
      );
      final result = await manager.download(
        remoteURL: Uri.parse('https://example.com/file'),
        destinationURL: destination.uri,
        progress: (_, _) => throw StateError('observer failed'),
      );
      expect(result.byteCount, 2);
      expect(await destination.readAsBytes(), [1, 2]);
      expect(remainingFiles(), ['video.mp4']);
    },
  );

  test(
    'decompressed response length is not compared with its compressed Content-Length',
    () async {
      final progress = <(int, int)>[];
      final manager = StorageManager(
        httpClient: _Client(
          (_) => _Response(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            length: 30,
            compression: HttpClientResponseCompressionState.decompressed,
          ),
        ),
      );
      final result = await manager.download(
        remoteURL: Uri.parse('https://example.com/compressed'),
        destinationURL: destination.uri,
        progress: (completed, total) => progress.add((completed, total)),
      );
      expect(result.byteCount, 4);
      expect(progress, [(2, 0), (4, 0), (4, 4)]);
    },
  );

  test(
    'concurrent downloads keep their staged data and progress separate',
    () async {
      final second = File('${directory.path}/second.mp4');
      final gates = [Completer<void>(), Completer<void>()];
      final started = [Completer<void>(), Completer<void>()];
      Stream<List<int>> body(int index) async* {
        yield [index + 1];
        await gates[index].future;
        yield [index + 1];
      }

      final manager = StorageManager(
        httpClient: _Client(
          (url) => _Response(body(url.path == '/first' ? 0 : 1), length: 2),
        ),
      );
      final progress = <List<(int, int)>>[[], []];
      final downloads = [destination, second].indexed
          .map(
            (entry) => manager.download(
              remoteURL: Uri.parse(
                'https://example.com/${entry.$1 == 0 ? 'first' : 'second'}',
              ),
              destinationURL: entry.$2.uri,
              progress: (completed, total) {
                progress[entry.$1].add((completed, total));
                if (!started[entry.$1].isCompleted) {
                  started[entry.$1].complete();
                }
              },
            ),
          )
          .toList();
      await Future.wait(started.map((event) => event.future));
      expect(await destination.exists(), isFalse);
      expect(await second.exists(), isFalse);
      gates[1].complete();
      await downloads[1];
      expect(await second.readAsBytes(), [2, 2]);
      expect(await destination.exists(), isFalse);
      gates[0].complete();
      final result = await downloads[0];
      expect(result.byteCount, 2);
      expect(await destination.readAsBytes(), [1, 1]);
      expect(progress[0], [(1, 2), (2, 2), (2, 2)]);
      expect(progress[1], progress[0]);
      expect(remainingFiles(), ['second.mp4', 'video.mp4']);
    },
  );
}

final _downloadError = isA<XmaxError>().having(
  (error) => error.code,
  'code',
  XmaxErrorCode.downloadError,
);

final class _Client implements HttpClient {
  _Client(this.response);
  final _Response Function(Uri) response;
  int requests = 0;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return _Request(response(url));
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;

  @override
  Future<HttpClientResponse> get done => Future.value(response);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.body, {
    int length = -1,
    this.status = 200,
    this.compression = HttpClientResponseCompressionState.notCompressed,
  }) : expectedLength = length;
  final Stream<List<int>> body;
  final int expectedLength;
  final int status;
  final HttpClientResponseCompressionState compression;

  @override
  int get contentLength => expectedLength;

  @override
  int get statusCode => status;

  @override
  HttpClientResponseCompressionState get compressionState => compression;

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
