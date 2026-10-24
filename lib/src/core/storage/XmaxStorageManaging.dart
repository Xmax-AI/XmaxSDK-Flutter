//
//  XmaxStorageManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import '../../foundation/storage/XmaxStorageCancellationToken.dart';
import 'XmaxDownloadedFile.dart';
import 'XmaxStorageProgressHandler.dart';
import 'XmaxUploadedFile.dart';

/// An interface for uploading and downloading media files.
///
/// Provide exactly one upload source: data or at.
/// Byte-backed uploads require both fileName and contentType.
/// File-backed uploads use the path's filename and infer contentType from its extension when
/// omitted.
///
/// An optional cancellation token covers credential retrieval, transfer, and safety checking.
/// Cancelled uploads may leave an object already accepted by storage; cancellation does not delete it.
abstract interface class XmaxStorageManaging {

  /// Uploads an image to object storage; see [XmaxStorageManaging] for source constraints.
  ///
  /// Parameters:
  /// - [data]: The encoded image bytes.
  /// - [at]: The local image file URI.
  /// - [fileName]: The filename including its extension for byte uploads; ignored for local files.
  /// - [contentType]: The MIME type stored as Content-Type, such as image/jpeg.
  /// - [progress]: The progress callback receiving completed and total bytes.
  /// - [cancellationToken]: The optional signal cancelling credentials, upload, and safety checking.
  ///
  /// Returns the object URL, key, and ETag when provided by storage.
  Future<XmaxUploadedFile> uploadImage({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  });

  /// Uploads an image and performs a safety check, rejecting unsafe content with unsafeImage.
  ///
  /// Safety checking runs after upload, so a rejected file may already exist in COS.
  /// See [uploadImage] and [XmaxStorageManaging] for upload source constraints.
  ///
  /// Parameters:
  /// - [data]: The encoded image bytes.
  /// - [at]: The local image file URI.
  /// - [fileName]: The filename for byte-backed uploads.
  /// - [contentType]: The image MIME type.
  /// - [progress]: The progress handler receiving uploaded and total bytes.
  /// - [cancellationToken]: The optional signal cancelling credentials, upload, and safety checking.
  ///
  /// Returns the object URL and key, with a null ETag if storage does not provide one.
  Future<XmaxUploadedFile> uploadImageWithSafetyCheck({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  });

  /// Uploads a video file without creating a realtime video input stream.
  ///
  /// Source constraints follow [XmaxStorageManaging]; filename rules follow [uploadImage].
  ///
  /// Parameters:
  /// - [data]: The encoded video bytes.
  /// - [at]: The local video file URI.
  /// - [fileName]: The filename for byte-backed uploads.
  /// - [contentType]: The video MIME type, such as video/mp4.
  /// - [progress]: The progress callback receiving completed and total bytes.
  /// - [cancellationToken]: The optional signal cancelling credentials, upload, and safety checking.
  ///
  /// Returns the object URL, key, and ETag when provided by storage.
  Future<XmaxUploadedFile> uploadVideo({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  });

  /// Downloads an image to a local file.
  ///
  /// Replaces an existing file only after download succeeds. Failed or cancelled transfers remove
  /// staged data without changing the existing file. The parent directory must exist; [to] cannot
  /// be a directory. Cancellation does not affect other transfers unless they share the same token.
  ///
  /// Parameters:
  /// - [from]: The remote file's HTTP or HTTPS URL.
  /// - [to]: The destination file URI.
  /// - [progress]: Receives bytes written and expected bytes, with zero total when unknown until
  ///   completion. Observer exceptions do not interrupt the transfer.
  /// - [cancellationToken]: The optional one-shot signal that cancels this download before commit.
  ///
  /// Returns the downloaded file URI and its byte count.
  /// Successful completion confirms that the destination has been committed.
  ///
  /// The returned future completes with an `XmaxError` whose code is `XmaxErrorCode.cancelled` if
  /// cancellation is accepted before replacement starts. Later cancellation cannot undo replacement
  /// or change a successful result.
  Future<XmaxDownloadedFile> downloadImage({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  });

  /// Downloads a video to a local file.
  ///
  /// File replacement, failure cleanup, and progress behavior follow [downloadImage].
  ///
  /// Parameters:
  /// - [from]: The remote file's HTTP or HTTPS URL.
  /// - [to]: The destination file URI.
  /// - [progress]: Receives bytes written and expected bytes, with zero total when unknown until
  ///   completion. Observer exceptions do not interrupt the transfer.
  /// - [cancellationToken]: The optional one-shot signal that cancels this download before commit.
  ///
  /// Returns the downloaded file URI and its byte count.
  /// Successful completion confirms that the destination has been committed.
  Future<XmaxDownloadedFile> downloadVideo({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
    XmaxStorageCancellationToken? cancellationToken,
  });
}
