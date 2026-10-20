//
//  StorageManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'StorageModels.dart';

/// 对象上传与 HTTP 文件下载的底层传输接口。
abstract interface class StorageManaging {

  /// 使用本次临时凭证执行普通 PUT 上传，不自动切换为分片上传。
  ///
  /// - [source]：待上传的内存字节或本地文件来源。
  /// - [objectKey]：对象在存储桶内的完整键，不是本地文件路径。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [configuration]：本次上传使用的存储桶、区域、服务地址和临时凭证。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> upload({
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
    StorageProgressListener? progress,
  });

  /// 流式下载文件到本地目标，并返回实际写入的字节数。
  ///
  /// - [remoteURL]：待下载文件的 HTTP 或 HTTPS URL。
  /// - [destinationURL]：下载目标的本地 file URI。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回已下载文件的本地 URI 和实际字节数。
  Future<DownloadedFile> download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  });
}
