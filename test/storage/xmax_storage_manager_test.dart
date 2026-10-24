import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/core/storage/XmaxStorageManager.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageProgressListener.dart';
import 'package:xmax_sdk/src/foundation/storage/StoredFile.dart';
import 'package:xmax_sdk/src/foundation/storage/DownloadedFile.dart';
import 'package:xmax_sdk/src/service/storage/StorageServicing.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  late _FakeStorageService service;
  late XmaxStorageManager manager;

  setUp(() {
    service = _FakeStorageService();
    manager = XmaxStorageManager(storageService: service);
  });

  test('data and at are mutually exclusive', () async {
    await expectLater(
      manager.uploadImage(),
      throwsA(
        isA<XmaxError>().having(
          (error) => error.code,
          'code',
          XmaxErrorCode.invalidConfiguration,
        ),
      ),
    );
    await expectLater(
      manager.uploadImage(
        data: Uint8List.fromList(<int>[1]),
        at: Uri.file('/tmp/image.png'),
        fileName: 'image.png',
        contentType: 'image/png',
      ),
      throwsA(isA<XmaxError>()),
    );
  });

  test('data upload requires fileName and contentType', () async {
    await expectLater(
      manager.uploadImage(data: Uint8List.fromList(<int>[1])),
      throwsA(isA<XmaxError>()),
    );
  });

  test('progress is mapped to XmaxStorageProgress', () async {
    XmaxStorageProgress? received;
    final uploaded = await manager.uploadImage(
      data: Uint8List.fromList(<int>[1]),
      fileName: 'image.png',
      contentType: 'image/png',
      progress: (progress) => received = progress,
    );

    expect(uploaded.url, Uri.parse('https://example.com/file'));
    expect(
      received,
      const XmaxStorageProgress(completedBytes: 5, totalBytes: 10),
    );
    expect(received?.fractionCompleted, 0.5);
  });
}

final class _FakeStorageService implements StorageServicing {
  StoredFile get _stored => StoredFile(
    url: Uri.parse('https://example.com/file'),
    objectKey: 'file',
    etag: 'etag',
  );

  @override
  Future<StoredFile> uploadImage({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  }) async {
    progress?.call(5, 10);
    return _stored;
  }

  @override
  Future<StoredFile> uploadImageFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  }) async => _stored;

  @override
  Future<StoredFile> uploadImageFileWithSafetyCheck({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  }) async => _stored;

  @override
  Future<StoredFile> uploadImageWithSafetyCheck({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  }) async => _stored;

  @override
  Future<StoredFile> uploadVideo({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  }) async => _stored;

  @override
  Future<StoredFile> uploadVideoFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  }) async => _stored;

  @override
  Future<DownloadedFile> downloadImage({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) async => DownloadedFile(fileURL: destinationURL, byteCount: 1);

  @override
  Future<DownloadedFile> downloadVideo({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) async => DownloadedFile(fileURL: destinationURL, byteCount: 1);
}
