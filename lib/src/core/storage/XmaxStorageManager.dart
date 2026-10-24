//
//  XmaxStorageManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/storage/DownloadedFile.dart';
import '../../foundation/storage/StorageProgressListener.dart';
import '../../foundation/storage/StoredFile.dart';
import '../../foundation/storage/XmaxStorageCancellationToken.dart';
import '../../service/storage/StorageServicing.dart';
import 'XmaxDownloadedFile.dart';
import 'XmaxStorageManaging.dart';
import 'XmaxStorageProgressHandler.dart';
import 'XmaxUploadedFile.dart';

/// Provides public file transfer operations backed by the storage service.
final class XmaxStorageManager implements XmaxStorageManaging {

  /// Creates a storage manager.
  XmaxStorageManager({
    required StorageServicing storageService,
  }) : _storageService = storageService;

  /// The service that retrieves credentials and performs file safety checks.
  final StorageServicing _storageService;

  /// Uploads an image to object storage; see [XmaxStorageManaging] for source constraints.
  ///
  /// See [XmaxStorageManaging.uploadImage] for the usage contract.
  @override
  Future<XmaxUploadedFile> uploadImage({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  }) => _upload(
    data: data,
    at: at,
    fileName: fileName,
    contentType: contentType,
    progress: progress,
    dataOperation: _storageService.uploadImage,
    fileOperation: _storageService.uploadImageFile,
  );

  /// Uploads an image and performs a safety check, rejecting unsafe content with unsafeImage.
  ///
  /// See [XmaxStorageManaging.uploadImageWithSafetyCheck] for the usage contract.
  @override
  Future<XmaxUploadedFile> uploadImageWithSafetyCheck({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  }) => _upload(
    data: data,
    at: at,
    fileName: fileName,
    contentType: contentType,
    progress: progress,
    dataOperation: _storageService.uploadImageWithSafetyCheck,
    fileOperation: _storageService.uploadImageFileWithSafetyCheck,
  );

  /// Uploads a video file without creating a realtime video input stream.
  ///
  /// See [XmaxStorageManaging.uploadVideo] for the usage contract.
  @override
  Future<XmaxUploadedFile> uploadVideo({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  }) => _upload(
    data: data,
    at: at,
    fileName: fileName,
    contentType: contentType,
    progress: progress,
    dataOperation: _storageService.uploadVideo,
    fileOperation: _storageService.uploadVideoFile,
  );

  /// Downloads an image to a local file.
  ///
  /// See [XmaxStorageManaging.downloadImage] for the usage contract.
  @override
  Future<XmaxDownloadedFile> downloadImage({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) async => _downloadedFile(
    await _storageService.downloadImage(
      remoteURL: from,
      destinationURL: to,
      progress: _progressListener(progress),
      cancellationToken: cancellationToken,
    ),
  );

  /// Downloads a video to a local file.
  ///
  /// See [XmaxStorageManaging.downloadVideo] for the usage contract.
  @override
  Future<XmaxDownloadedFile> downloadVideo({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) async => _downloadedFile(
    await _storageService.downloadVideo(
      remoteURL: from,
      destinationURL: to,
      progress: _progressListener(progress),
      cancellationToken: cancellationToken,
    ),
  );

  /// Validates an upload source and returns the stored object.
  ///
  /// Parameters:
  /// - [data]: The encoded file bytes to upload.
  /// - [at]: The local file URI, mutually exclusive with data; its path supplies the filename.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [progress]: The progress callback receiving completed and total bytes.
  /// - [dataOperation]: The upload operation for byte-backed sources.
  /// - [fileOperation]: The upload operation for local files.
  ///
  /// Returns the object URL, key, and ETag when provided by storage.
  Future<XmaxUploadedFile> _upload({
    required Uint8List? data,
    required Uri? at,
    required String? fileName,
    required String? contentType,
    required XmaxStorageProgressHandler? progress,
    required Future<StoredFile> Function({
      required Uint8List data,
      required String fileName,
      required String contentType,
      StorageProgressListener? progress,
    })
    dataOperation,
    required Future<StoredFile> Function({
      required Uri fileURL,
      String? contentType,
      StorageProgressListener? progress,
    })
    fileOperation,
  }) async {
    if ((data == null) == (at == null)) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Exactly one of data or at must be provided',
      );
    }

    final StoredFile stored;

    if (data != null) {
      final resolvedFileName = fileName?.trim() ?? '';
      final resolvedContentType = contentType?.trim() ?? '';

      if (resolvedFileName.isEmpty || resolvedContentType.isEmpty) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Data uploads require fileName and contentType',
        );
      }

      stored = await dataOperation(
        data: data,
        fileName: resolvedFileName,
        contentType: resolvedContentType,
        progress: _progressListener(progress),
      );
    } else {
      stored = await fileOperation(
        fileURL: at!,
        contentType: contentType,
        progress: _progressListener(progress),
      );
    }

    return createXmaxUploadedFile(
      url: stored.url,
      objectKey: stored.objectKey,
      etag: stored.etag,
    );
  }

  /// Adapts byte progress to the public SDK progress value.
  ///
  /// Parameters:
  /// - [handler]: The public progress handler, or null to omit progress adaptation.
  ///
  /// Returns a byte progress listener, or null when no handler is supplied.
  StorageProgressListener? _progressListener(
    XmaxStorageProgressHandler? handler,
  ) => handler == null
      ? null
      : (
        completedBytes,
        totalBytes,
      ) => handler(
          XmaxStorageProgress(
            completedBytes: completedBytes.clamp(
              0,
              totalBytes,
            ),
            totalBytes: totalBytes,
          ),
        );

  /// Converts a storage download result to the public file result.
  ///
  /// Parameters:
  /// - [file]: The local file result returned by storage.
  ///
  /// Returns the downloaded file URI and its byte count.
  XmaxDownloadedFile _downloadedFile(
    DownloadedFile file,
  ) => createXmaxDownloadedFile(
    fileURL: file.fileURL,
    byteCount: file.byteCount,
  );
}
