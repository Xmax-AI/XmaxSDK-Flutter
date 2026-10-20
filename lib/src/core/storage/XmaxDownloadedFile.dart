//
//  XmaxDownloadedFile.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 文件下载结果，包含本地文件位置和实际字节数。
final class XmaxDownloadedFile {

  /// 创建文件下载结果。
  const XmaxDownloadedFile._({
    required this.fileURL,
    required this.byteCount,
  });

  /// 本地文件的 file URI。
  final Uri fileURL;

  /// 文件大小，单位为字节。
  final int byteCount;

  /// 与 [other] 比较类型及 [fileURL]、[byteCount] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is XmaxDownloadedFile &&
          fileURL == other.fileURL &&
          byteCount == other.byteCount;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(fileURL, byteCount);
}

/// 将本地文件位置和实际字节数封装为下载结果。
///
/// - [fileURL]：本地文件的 file URI。
/// - [byteCount]：文件大小，单位为字节。
///
/// 返回下载后的本地文件 URI 和实际字节数。
XmaxDownloadedFile createXmaxDownloadedFile({
  required Uri fileURL,
  required int byteCount,
}) => XmaxDownloadedFile._(fileURL: fileURL, byteCount: byteCount);
