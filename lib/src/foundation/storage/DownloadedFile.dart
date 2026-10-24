//
//  DownloadedFile.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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
