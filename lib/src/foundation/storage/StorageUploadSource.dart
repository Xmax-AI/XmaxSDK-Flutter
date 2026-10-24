//
//  StorageUploadSource.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

/// An object upload source backed by in-memory bytes or a local file.
sealed class StorageUploadSource {

  /// Creates a file upload source.
  const StorageUploadSource();
}

/// An upload source backed by in-memory bytes.
final class StorageDataUploadSource extends StorageUploadSource {

  /// Creates an upload source from image or video bytes.
  const StorageDataUploadSource(
    this.data,
  );

  /// The encoded file bytes to upload.
  final Uint8List data;
}

/// A local file upload source that does not load the entire file into Dart memory.
final class StorageFileUploadSource extends StorageUploadSource {

  /// Creates an upload source from a local file.
  const StorageFileUploadSource(
    this.fileURL,
  );

  /// The local file URI.
  final Uri fileURL;
}
