//
//  StorageManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'DownloadedFile.dart';
import 'StorageConfiguration.dart';
import 'StorageProgressListener.dart';
import 'StorageUploadSource.dart';
import 'StoredFile.dart';

/// A transport interface for object uploads and HTTP file downloads.
abstract interface class StorageManaging {

  /// Uploads with a single PUT using request-scoped temporary credentials, without multipart
  /// fallback.
  ///
  /// Parameters:
  /// - [source]: The in-memory bytes or local file to upload.
  /// - [objectKey]: The full object key within the bucket, not a local file path.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [configuration]: The bucket, region, endpoint, and temporary credentials for this upload.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> upload({
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
    StorageProgressListener? progress,
  });

  /// Downloads a file and replaces the destination only after the transfer and file write succeed.
  ///
  /// A failed transfer leaves an existing destination unchanged and removes its staged partial file.
  /// The destination's parent directory must exist; directory destinations are rejected.
  ///
  /// Parameters:
  /// - [remoteURL]: The HTTP or HTTPS URL of the file to download.
  /// - [destinationURL]: The destination file URI.
  /// - [progress]: Receives bytes written and expected bytes; zero total means unknown until
  ///   completion. Observer exceptions do not interrupt the transfer.
  ///
  /// Returns the downloaded file's local URI and actual byte count.
  /// Only this future's successful completion confirms that the destination was committed.
  Future<DownloadedFile> download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  });
}
