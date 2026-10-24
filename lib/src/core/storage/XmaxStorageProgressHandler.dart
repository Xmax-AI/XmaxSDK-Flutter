//
//  XmaxStorageProgressHandler.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The transferred byte counts and completion fraction for a file operation.
final class XmaxStorageProgress {

  /// Creates progress with nonnegative byte counts and completed bytes no greater than the total.
  const XmaxStorageProgress({
    required this.completedBytes,
    required this.totalBytes,
  }) : assert(completedBytes >= 0),
       assert(totalBytes >= 0),
       assert(completedBytes <= totalBytes);

  /// The number of bytes transferred.
  final int completedBytes;

  /// The total transfer size, in bytes.
  final int totalBytes;

  /// The completion fraction from 0 to 1, or 0 when the total is zero.
  double get fractionCompleted =>
      totalBytes > 0 ? completedBytes / totalBytes : 0;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxStorageProgress &&
          completedBytes == other.completedBytes &&
          totalBytes == other.totalBytes;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    completedBytes,
    totalBytes,
  );
}

/// A callback receiving immutable file transfer progress.
///
/// Parameters:
/// - [progress]: The transferred bytes, total bytes, and completion fraction.
typedef XmaxStorageProgressHandler =
    void Function(
      XmaxStorageProgress progress,
    );
