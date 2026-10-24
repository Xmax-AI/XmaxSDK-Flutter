//
//  StoredFile.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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
