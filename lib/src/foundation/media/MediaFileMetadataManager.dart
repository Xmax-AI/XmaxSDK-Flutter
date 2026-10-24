//
//  MediaFileMetadataManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/services.dart';

import '../storage/StorageModels.dart';

/// Reads media pixel dimensions, returning a placeholder on failure without blocking uploads.
final class MediaFileMetadataManager {

  /// Creates a media dimension reader.
  const MediaFileMetadataManager();

  /// The method channel for communication with the native platform.
  static const _channel = MethodChannel('ai.xmax.sdk/media');

  /// Reads image or video dimensions as text; returns -- when unavailable.
  ///
  /// Parameters:
  /// - [source]: The media or upload data source to inspect.
  /// - [isVideo]: Whether to read metadata as a video file.
  ///
  /// Returns pixel dimensions as width × height, or -- for in-memory video or a read exceeding two
  /// seconds.
  Future<String> readResolution(
    StorageUploadSource source, {
    required bool isVideo,
  }) async {
    // Avoid temporary files for in-memory video diagnostics; use rotated display dimensions for local video.
    if (isVideo && source is StorageDataUploadSource) {
      return '--';
    }

    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>(
            'readResolution',
            <String, Object>{
            'mediaType': isVideo ? 'video' : 'image',
            ...switch (source) {
              StorageDataUploadSource(:final data) => {'data': data},
              StorageFileUploadSource(:final fileURL) => {
                'filePath': fileURL.toFilePath(),
              },
            },
          },
          )
          .timeout(const Duration(seconds: 2));
      final width = result?['width'];
      final height = result?['height'];

      if (width is int && height is int && width > 0 && height > 0) {
        return '$width × $height';
      }
    } catch (_) {
      // Dimensions are diagnostic only; missing plugins, corrupt files, and timeouts must not block uploads.
    }

    return '--';
  }
}
