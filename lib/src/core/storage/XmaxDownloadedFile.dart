//
//  XmaxDownloadedFile.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A downloaded file's local location and byte count.
final class XmaxDownloadedFile {

  /// Creates a file download result.
  const XmaxDownloadedFile._({
    required this.fileURL,
    required this.byteCount,
  });

  /// The local file URI.
  final Uri fileURL;

  /// The file size, in bytes.
  final int byteCount;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxDownloadedFile &&
          fileURL == other.fileURL &&
          byteCount == other.byteCount;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    fileURL,
    byteCount,
  );
}

/// Creates a download result from a local file and its byte count.
///
/// Parameters:
/// - [fileURL]: The local file URI.
/// - [byteCount]: The file size, in bytes.
///
/// Returns the downloaded file URI and its byte count.
XmaxDownloadedFile createXmaxDownloadedFile({
  required Uri fileURL,
  required int byteCount,
}) => XmaxDownloadedFile._(
  fileURL: fileURL,
  byteCount: byteCount,
);
