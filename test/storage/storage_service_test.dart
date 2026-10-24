import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManaging.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageProgressListener.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageConfiguration.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageUploadSource.dart';
import 'package:xmax_sdk/src/foundation/storage/StoredFile.dart';
import 'package:xmax_sdk/src/foundation/storage/DownloadedFile.dart';
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/storage/StorageService.dart';
import 'package:xmax_sdk/src/core/storage/XmaxStorageManager.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const metadataChannel = MethodChannel('ai.xmax.sdk/media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(metadataChannel, null));
  late _FakeApiService apiService;
  late _FakeStorageManager storageManager;
  late StorageService service;

  setUp(() {
    apiService = _FakeApiService();
    storageManager = _FakeStorageManager();
    service = StorageService(
      apiService: apiService,
      storageManager: storageManager,
      dateGenerator: () => DateTime.fromMillisecondsSinceEpoch(1234),
      identifierGenerator: () => 'ABC-123',
    );
  });

  for (final stage in ['/cos/sts', '/cos/image/check']) {
    test(
      'public cancellation aborts $stage without continuing the upload workflow',
      () async {
        final started = Completer<void>();
        apiService.beforeRequest = (path, cancellation) async {
          if (path == stage) {
            expect(cancellation, isNotNull);
            started.complete();
            await cancellation;
            throw const XmaxError(
              code: XmaxErrorCode.cancelled,
              message: 'cancelled',
            );
          }
        };
        final public = XmaxStorageManager(storageService: service);
        final token = XmaxStorageCancellationToken();
        final failed = expectLater(
          public.uploadImageWithSafetyCheck(
            data: Uint8List.fromList([1, 2, 3]),
            fileName: 'image.png',
            contentType: 'image/png',
            cancellationToken: token,
          ),
          throwsA(
            isA<XmaxError>().having(
              (error) => error.code,
              'code',
              XmaxErrorCode.cancelled,
            ),
          ),
        );
        await started.future;
        token.cancel();
        await failed.timeout(const Duration(seconds: 1));
        expect(storageManager.uploads, stage == '/cos/sts' ? 0 : 1);
        expect(
          apiService.paths,
          stage == '/cos/sts' ? ['/cos/sts'] : ['/cos/sts', '/cos/image/check'],
        );
      },
    );
  }

  test(
    'pre-cancelled public upload performs no credential or native upload work',
    () async {
      final public = XmaxStorageManager(storageService: service);
      await expectLater(
        public.uploadVideo(
          data: Uint8List.fromList([1]),
          fileName: 'video.mp4',
          contentType: 'video/mp4',
          cancellationToken: XmaxStorageCancellationToken()..cancel(),
        ),
        throwsA(
          isA<XmaxError>().having(
            (error) => error.code,
            'code',
            XmaxErrorCode.cancelled,
          ),
        ),
      );
      expect(apiService.paths, isEmpty);
      expect(storageManager.uploads, 0);
    },
  );

  test(
    'global storage logs keep bilingual titles and English details',
    () async {
      final messages = <String>[];
      messenger.setMockMethodCallHandler(
        metadataChannel,
        (_) async => {'width': 1920, 'height': 1080},
      );
      XmaxLogger.configure(
        options: XmaxLoggerOption.all,
        environment: XmaxEnvironment.global,
      );
      XmaxLogger.setSink((_, message) => messages.add(message));
      addTearDown(XmaxLogger.reset);
      await service.uploadImage(
        data: Uint8List.fromList(<int>[1]),
        fileName: 'image.png',
        contentType: 'image/png',
      );
      expect(messages.first, contains('开始上传 (Upload Started)'));
      expect(messages.first, contains('├─ Type: image'));
      expect(messages.first, contains('├─ Resolution: 1920 × 1080'));
      expect(messages.first, contains('└─ Safety Check: false'));
      expect(messages.last, contains('├─ URL: https://bucket.example/'));
      expect(messages.last, contains('└─ Duration: '));
      storageManager.uploadError = const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'AccessDenied',
      );
      await expectLater(
        service.uploadVideo(
          data: Uint8List.fromList(<int>[1]),
          fileName: 'video.mp4',
          contentType: 'video/mp4',
        ),
        throwsA(isA<XmaxError>()),
      );
      expect(messages.last, contains('上传失败 (Upload Failed)'));
      expect(messages.last, contains('├─ Error Code: UPLOAD_ERROR'));
      expect(messages.last, contains('├─ Reason: AccessDenied'));
    },
  );

  test(
    'uploadImage fetches STS and builds iOS-compatible object key',
    () async {
      final result = await service.uploadImage(
        data: Uint8List.fromList(<int>[1, 2, 3]),
        fileName: ' look @ 1.png ',
        contentType: 'image/png',
      );

      expect(apiService.paths, <String>['/cos/sts']);
      expect(storageManager.objectKey, 'uploads/1234_abc-123_look_1.png');
      expect(storageManager.contentType, 'image/png');
      expect(result.objectKey, storageManager.objectKey);
    },
  );

  test('uploadImageWithSafetyCheck returns checked URL', () async {
    apiService.safetyPayload = <String, dynamic>{
      'safe': true,
      'url': 'https://safe.example/result.png',
    };

    final result = await service.uploadImageWithSafetyCheck(
      data: Uint8List.fromList(<int>[1]),
      fileName: 'image.png',
      contentType: 'image/png',
    );

    expect(result.url, Uri.parse('https://safe.example/result.png'));
    expect(apiService.paths, <String>['/cos/sts', '/cos/image/check']);
  });

  test('uploadImageWithSafetyCheck maps unsafe image', () async {
    apiService.safetyPayload = <String, dynamic>{'safe': false};

    await expectLater(
      service.uploadImageWithSafetyCheck(
        data: Uint8List.fromList(<int>[1]),
        fileName: 'image.png',
        contentType: 'image/png',
      ),
      throwsA(
        isA<XmaxError>().having(
          (error) => error.code,
          'code',
          XmaxErrorCode.unsafeImage,
        ),
      ),
    );
  });

  test('upload validates source, content type, and file name', () async {
    await expectLater(
      service.uploadVideo(
        data: Uint8List(0),
        fileName: 'video.mp4',
        contentType: 'video/mp4',
      ),
      throwsA(isA<XmaxError>()),
    );
    await expectLater(
      service.uploadImage(
        data: Uint8List.fromList(<int>[1]),
        fileName: 'image.png',
        contentType: 'video/mp4',
      ),
      throwsA(
        isA<XmaxError>().having(
          (error) => error.code,
          'code',
          XmaxErrorCode.invalidConfiguration,
        ),
      ),
    );
  });

  test('download validates remote and destination URLs', () async {
    await expectLater(
      service.downloadImage(
        remoteURL: Uri.parse('file:///remote.png'),
        destinationURL: Uri.file('/tmp/result.png'),
      ),
      throwsA(isA<XmaxError>()),
    );
    await expectLater(
      service.downloadImage(
        remoteURL: Uri.parse('https://example.com/image.png'),
        destinationURL: Uri.parse('https://example.com/result.png'),
      ),
      throwsA(isA<XmaxError>()),
    );
  });

  test('upload maps an aborted platform request to cancelled', () async {
    storageManager.uploadError = const HttpException(
      'Request has been aborted',
    );

    await expectLater(
      service.uploadImage(
        data: Uint8List.fromList(<int>[1]),
        fileName: 'image.png',
        contentType: 'image/png',
      ),
      throwsA(
        isA<XmaxError>()
            .having((error) => error.code, 'code', XmaxErrorCode.cancelled)
            .having(
              (error) => error.message,
              'message',
              'Storage upload was cancelled',
            ),
      ),
    );
  });

  test(
    'upload failures include a storage diagnostic and preserve the error',
    () async {
      final messages = <String>[];
      XmaxLogger.configure(options: XmaxLoggerOption.all);
      XmaxLogger.setSink((level, message) => messages.add(message));
      addTearDown(XmaxLogger.reset);
      const error = XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'COS signature failed',
      );
      storageManager.uploadError = error;

      await expectLater(
        service.uploadImage(
          data: Uint8List.fromList(<int>[1]),
          fileName: 'image.png',
          contentType: 'image/png',
        ),
        throwsA(same(error)),
      );
      expect(
        messages.where((message) => message.contains('Upload Failed')),
        hasLength(1),
      );
      expect(messages.last, contains('COS signature failed'));
    },
  );
}

final class _FakeApiService implements ApiServicing {
  Future<void> Function(String, Future<void>?)? beforeRequest;
  final List<String> paths = <String>[];
  Map<String, dynamic> safetyPayload = <String, dynamic>{
    'safe': true,
    'url': 'https://safe.example/image.png',
  };

  @override
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(Object? json) decode,
    Future<void>? cancellation,
  }) async {
    paths.add(path);
    await beforeRequest?.call(path, cancellation);
    if (path == '/cos/sts') {
      return decode(<String, dynamic>{
        'bucket': 'bucket-123',
        'region': 'ap-shanghai',
        'endpoint': '',
        'prefix': 'uploads/',
        'credentials': <String, dynamic>{
          'accessKeyId': 'id',
          'secretAccessKey': 'secret',
          'sessionToken': 'token',
        },
      });
    }
    return decode(safetyPayload);
  }
}

final class _FakeStorageManager implements StorageManaging {
  int uploads = 0;
  String objectKey = '';
  String contentType = '';
  Object? uploadError;

  @override
  Future<StoredFile> upload({
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
    StorageProgressListener? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) async {
    uploads++;
    final error = uploadError;
    if (error != null) {
      throw error;
    }
    this.objectKey = objectKey;
    this.contentType = contentType;
    progress?.call(3, 3);
    return StoredFile(
      url: Uri.parse('https://bucket.example/$objectKey'),
      objectKey: objectKey,
      etag: 'etag',
    );
  }

  @override
  Future<DownloadedFile> download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) async => DownloadedFile(fileURL: destinationURL, byteCount: 10);
}
