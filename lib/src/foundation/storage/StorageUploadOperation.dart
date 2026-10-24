//
//  StorageUploadOperation.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';

import 'package:tencentcloud_cos_sdk_plugin_nobeacon/cos_transfer_manger.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/enums.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/pigeon.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/transfer_task.dart';

import '../errors/ErrorMessageFormatter.dart';
import '../errors/ErrorNormalizer.dart';
import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import '../tasks/OperationCancellation.dart';
import 'StorageConfiguration.dart';
import 'StorageProgressListener.dart';
import 'StorageUploadSource.dart';
import 'StoredFile.dart';
import 'XmaxStorageCancellationToken.dart';

/// Owns one COS upload, its callbacks, and cancellation of its native transfer task.
final class StorageUploadOperation {

  /// Creates an upload with independent progress and cancellation.
  const StorageUploadOperation({
    StorageProgressListener? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) : _progress = progress,
       _cancellationToken = cancellationToken;

  /// The observer receiving uploaded and expected bytes.
  final StorageProgressListener? _progress;

  /// The caller's optional cancellation token.
  final XmaxStorageCancellationToken? _cancellationToken;

  /// Registers a single PUT and awaits its result, cancelling only its own native task.
  ///
  /// Cancellation during registration waits for the native task handle before cancelling it.
  /// Late progress and completion callbacks cannot change the first result.
  ///
  /// Parameters:
  /// - [transferManager]: Resolves shared region resources without starting this transfer.
  /// - [source]: The byte-backed or local file source.
  /// - [objectKey]: The destination object key.
  /// - [contentType]: The MIME type stored on the object.
  /// - [configuration]: The region, bucket, and request-specific credentials.
  /// - [resolveURL]: Resolves and validates the URL returned by COS.
  ///
  /// Returns the stored object's metadata, or completes with an upload or cancellation error.
  Future<StoredFile> value({
    required Future<CosTransferManger> Function() transferManager,
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
    required Uri Function(
      String? candidate,
    ) resolveURL,
  }) async {
    final operation = OperationCancellation();
    final detach = _cancellationToken == null
        ? null
        : observeStorageCancellation(
          _cancellationToken,
          operation.cancel,
        );
    final result = Completer<StoredFile>();

    result.future.ignore();
    TransferTask? task;
    Future<void>? cancelling;

    Future<void> cancelTask() async {
      try {
        await task?.cancel();
      } catch (_) {
        // Preserve the cancellation result if the native task has already ended.
      }
    }

    operation.observe(() {
      if (!result.isCompleted) {
        result.completeError(OperationCancellation.error);
      }
      if (task != null) {
        cancelling ??= cancelTask();
      }
    });

    try {
      operation.check();
      final manager = await operation.wait(transferManager());
      final credential = configuration.credential;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sessionCredentials = SessionQCloudCredentials(
        secretId: credential.accessKeyID,
        secretKey: credential.secretAccessKey,
        token: credential.sessionToken,
        startTime: now - 60,
        expiredTime: now + 25 * 60,
      );
      final listener = ResultListener(
        (
          headers,
          stored,
        ) {
          if (operation.isCancelled || result.isCompleted) {
            return;
          }

          try {
            final candidate = stored?.accessUrl ?? headers?['location'] ?? headers?['Location'];

            result.complete(
              StoredFile(
                url: resolveURL(candidate),
                objectKey: objectKey,
                etag: stored?.eTag ?? headers?['etag'] ?? headers?['ETag'],
              ),
            );
            operation.finish();
          } catch (error, stackTrace) {
            result.completeError(
              error,
              stackTrace,
            );
            operation.finish();
          }
        },
        (
          clientException,
          serviceException,
        ) {
          if (!result.isCompleted) {
            final error = serviceException ?? clientException;

            result.completeError(
              XmaxError(
                code: XmaxErrorCode.uploadError,
                message: error == null ? 'Storage upload failed' : ErrorMessageFormatter.format(error),
              ),
            );
            operation.finish();
          }
        },
      );

      void stateChanged(
        TransferState state,
      ) {
        if (state == TransferState.CANCELED && !result.isCompleted) {
          result.completeError(OperationCancellation.error);
          operation.finish();
        }
      }

      void progress(
        int completed,
        int total,
      ) {
        if (result.isCompleted || operation.isCancelled) {
          return;
        }
        try {
          _progress?.call(
            completed,
            total,
          );
        } catch (_) {
          try {
            XmaxLogger.warn(
              category: XmaxLoggerCategory.storage,
              message: XmaxLogger.localized(
                '上传进度回调失败 (Upload Progress Callback Failed)',
                'Upload Progress Callback Failed',
              ),
            );
          } catch (_) {}
        }
      }

      // Registration creates an owned native task; do not abandon its future on cancellation.
      switch (source) {
        case StorageDataUploadSource(:final data):
          task = await manager.upload(
            configuration.bucket,
            objectKey,
            region: configuration.region,
            byteArr: data,
            customHeaders: <String, String>{'Content-Type': contentType},
            sessionCredentials: sessionCredentials,
            resultListener: listener,
            stateCallback: stateChanged,
            progressCallBack: progress,
          );
        case StorageFileUploadSource(:final fileURL):
          task = await manager.upload(
            configuration.bucket,
            objectKey,
            region: configuration.region,
            filePath: fileURL.toFilePath(),
            customHeaders: <String, String>{'Content-Type': contentType},
            sessionCredentials: sessionCredentials,
            resultListener: listener,
            stateCallback: stateChanged,
            progressCallBack: progress,
          );
      }

      if (operation.isCancelled) {
        cancelling ??= cancelTask();
        await cancelling;
        operation.check();
      }
      return await result.future;
    } on XmaxError {
      rethrow;
    } catch (error) {
      operation.check();
      if (ErrorNormalizer.isCancellation(error)) {
        throw OperationCancellation.error;
      }
      throw XmaxError(
        code: XmaxErrorCode.uploadError,
        message: ErrorMessageFormatter.format(error),
      );
    } finally {
      detach?.call();
      operation.finish();
      await cancelling;
    }
  }
}
