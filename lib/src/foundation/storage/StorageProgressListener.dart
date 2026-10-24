//
//  StorageProgressListener.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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
