//
//  XmaxStorageProgressHandler.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 文件传输的字节进度和完成比例。
final class XmaxStorageProgress {

  /// 创建传输进度；断言字节数非负，且已传输字节数不超过总字节数。
  const XmaxStorageProgress({
    required this.completedBytes,
    required this.totalBytes,
  }) : assert(completedBytes >= 0),
       assert(totalBytes >= 0),
       assert(completedBytes <= totalBytes);

  /// 已经传输的字节数。
  final int completedBytes;

  /// 传输的总字节数。
  final int totalBytes;

  /// 已完成字节数占总字节数的比例，范围为 0～1；总字节数为零时为 0。
  double get fractionCompleted =>
      totalBytes > 0 ? completedBytes / totalBytes : 0;

  /// 与 [other] 比较类型及 [completedBytes]、[totalBytes] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is XmaxStorageProgress &&
          completedBytes == other.completedBytes &&
          totalBytes == other.totalBytes;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(completedBytes, totalBytes);
}

/// 接收不可变文件传输进度的回调。
///
/// - [progress]：包含已传输字节数、总字节数和完成比例的进度快照。
typedef XmaxStorageProgressHandler =
    void Function(
      XmaxStorageProgress progress,
    );
