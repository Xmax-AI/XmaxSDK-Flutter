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

/// 读取媒体文件的像素尺寸；读取失败时返回占位文本，不阻断文件上传。
final class MediaFileMetadataManager {

  /// 创建媒体尺寸读取入口。
  const MediaFileMetadataManager();

  /// 与原生平台通信的方法通道。
  static const _channel = MethodChannel('ai.xmax.sdk/media');

  /// 读取图片或视频的宽高文本；无法读取时返回 --。
  ///
  /// - [source]：待处理媒体或上传数据的来源。
  /// - [isVideo]：是否按视频文件读取媒体信息。
  ///
  /// 返回“宽 × 高”的像素尺寸文本；内存视频或两秒内无法完成读取时返回 --。
  Future<String> readResolution(
    StorageUploadSource source, {
    required bool isVideo,
  }) async {
    // 内存视频不为日志额外创建临时文件；本地视频读取旋转后的显示尺寸。
    if (isVideo && source is StorageDataUploadSource) return '--';

    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('readResolution', <String, Object>{
            'mediaType': isVideo ? 'video' : 'image',
            ...switch (source) {
              StorageDataUploadSource(:final data) => {'data': data},
              StorageFileUploadSource(:final fileURL) => {
                'filePath': fileURL.toFilePath(),
              },
            },
          })
          .timeout(const Duration(seconds: 2));
      final width = result?['width'];
      final height = result?['height'];

      if (width is int && height is int && width > 0 && height > 0) {
        return '$width × $height';
      }
    } catch (_) {
      // 媒体尺寸仅用于日志。插件缺失、文件损坏或读取超时，都不能阻止上传。
    }

    return '--';
  }
}
