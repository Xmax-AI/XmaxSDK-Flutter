//
//  XmaxUploadedFile.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A stored object's access URL, key, and optional ETag.
final class XmaxUploadedFile {

  /// Creates a file upload result.
  const XmaxUploadedFile._({
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

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxUploadedFile &&
          url == other.url &&
          objectKey == other.objectKey &&
          etag == other.etag;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    url,
    objectKey,
    etag,
  );
}

/// Creates an upload result from an object URL, key, and ETag.
///
/// Parameters:
/// - [url]: The uploaded object's access URL.
/// - [objectKey]: The full object key within the bucket, not a local file path.
/// - [etag]: The ETag returned by storage, or null when not provided.
///
/// Returns the object URL, key, and ETag when provided by storage.
XmaxUploadedFile createXmaxUploadedFile({
  required Uri url,
  required String objectKey,
  String? etag,
}) => XmaxUploadedFile._(
  url: url,
  objectKey: objectKey,
  etag: etag,
);
