//
//  StorageModels.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

/// A transfer progress callback receiving completed and total byte counts.
///
/// Parameters:
/// - [completedBytes]: The number of bytes transferred.
/// - [totalBytes]: The total transfer size, in bytes.
typedef StorageProgressListener =
    void Function(
      int completedBytes,
      int totalBytes,
    );

/// Temporary access keys and a session token for object storage requests.
final class StorageCredential {

  /// Creates temporary object storage credentials.
  const StorageCredential({
    required this.accessKeyID,
    required this.secretAccessKey,
    required this.sessionToken,
  });

  /// The temporary access key identifier.
  final String accessKeyID;

  /// The temporary secret access key; must not be logged.
  final String secretAccessKey;

  /// The temporary credential session token.
  final String sessionToken;
}

/// The bucket, region, endpoint, and temporary credentials for one object upload.
final class StorageConfiguration {

  /// Creates an object storage connection configuration.
  const StorageConfiguration({
    required this.bucket,
    required this.region,
    required this.endpoint,
    required this.credential,
  });

  /// The object storage bucket name.
  final String bucket;

  /// The object storage region identifier.
  final String region;

  /// The object storage service endpoint.
  final String endpoint;

  /// The temporary credentials used for this transfer.
  final StorageCredential credential;
}

/// An object upload source backed by in-memory bytes or a local file.
sealed class StorageUploadSource {

  /// Creates a file upload source.
  const StorageUploadSource();
}

/// Creates an upload source from in-memory bytes.
final class StorageDataUploadSource extends StorageUploadSource {

  /// Creates an upload source from image or video bytes.
  const StorageDataUploadSource(
    this.data,
  );

  /// The encoded file bytes to upload.
  final Uint8List data;
}

/// Creates an upload source from a local file URI without loading the entire file into Dart memory.
final class StorageFileUploadSource extends StorageUploadSource {

  /// Creates an upload source from a local file.
  const StorageFileUploadSource(
    this.fileURL,
  );

  /// The local file URI.
  final Uri fileURL;
}

/// A transport upload result containing the object URL, key, and ETag.
final class StoredFile {

  /// Creates a transport upload result.
  const StoredFile({
    required this.url,
    required this.objectKey,
    this.etag,
  });

  /// The uploaded object's access URL.
  final Uri url;

  /// The full object key within the bucket, not a local file path.
  final String objectKey;

  /// The ETag returned by storage, or null when not provided.
  final String? etag;
}

/// A transport download result containing the destination URI and actual byte count.
final class DownloadedFile {

  /// Creates a transport download result.
  const DownloadedFile({
    required this.fileURL,
    required this.byteCount,
  });

  /// The local file URI.
  final Uri fileURL;

  /// The file size, in bytes.
  final int byteCount;
}
