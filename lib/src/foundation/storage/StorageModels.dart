//
//  StorageModels.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

/// 按已完成字节数和总字节数接收传输进度的回调。
///
/// - [completedBytes]：已经传输的字节数。
/// - [totalBytes]：传输的总字节数。
typedef StorageProgressListener =
    void Function(
      int completedBytes,
      int totalBytes,
    );

/// 对象存储请求使用的临时访问密钥和会话令牌。
final class StorageCredential {

  /// 创建对象存储临时凭证。
  const StorageCredential({
    required this.accessKeyID,
    required this.secretAccessKey,
    required this.sessionToken,
  });

  /// 临时访问密钥标识。
  final String accessKeyID;

  /// 临时访问密钥内容，不得写入日志。
  final String secretAccessKey;

  /// 临时访问凭证中的会话令牌。
  final String sessionToken;
}

/// 单次对象上传所需的存储桶、区域、服务地址和临时凭证。
final class StorageConfiguration {

  /// 创建对象存储连接配置。
  const StorageConfiguration({
    required this.bucket,
    required this.region,
    required this.endpoint,
    required this.credential,
  });

  /// 对象存储桶名称。
  final String bucket;

  /// 对象存储区域标识。
  final String region;

  /// 对象存储服务的访问地址。
  final String endpoint;

  /// 本次传输使用的临时访问凭证。
  final StorageCredential credential;
}

/// 对象上传的数据来源，仅接受内存字节或本地文件。
sealed class StorageUploadSource {

  /// 创建文件上传来源。
  const StorageUploadSource();
}

/// 以内存字节作为上传来源。
final class StorageDataUploadSource extends StorageUploadSource {

  /// 以图片或视频字节作为上传来源。
  const StorageDataUploadSource(
    this.data,
  );

  /// 待上传的原始文件字节。
  final Uint8List data;
}

/// 以本地文件 URI 作为上传来源，不将整个文件读入 Dart 内存。
final class StorageFileUploadSource extends StorageUploadSource {

  /// 以本地文件作为上传来源。
  const StorageFileUploadSource(
    this.fileURL,
  );

  /// 本地文件的 file URI。
  final Uri fileURL;
}

/// 底层上传结果，包含对象访问地址、对象键和 ETag。
final class StoredFile {

  /// 创建底层文件上传结果。
  const StoredFile({
    required this.url,
    required this.objectKey,
    this.etag,
  });

  /// 上传对象的访问地址。
  final Uri url;

  /// 对象在存储桶内的完整键，不是本地文件路径。
  final String objectKey;

  /// 对象存储返回的 ETag；服务未返回时为空。
  final String? etag;
}

/// 底层下载结果，包含目标文件 URI 和实际写入字节数。
final class DownloadedFile {

  /// 创建底层文件下载结果。
  const DownloadedFile({
    required this.fileURL,
    required this.byteCount,
  });

  /// 本地文件的 file URI。
  final Uri fileURL;

  /// 文件大小，单位为字节。
  final int byteCount;
}
